import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'date.dart';
import 'deck.dart';
import 'fsrs.dart';
import 'grade.dart';
import 'phone.dart';

abstract class Persistence {
  Future<String?> read();
  Future<void> write(String contents);

  /// Keeps an unreadable save aside instead of overwriting months of work.
  Future<void> quarantine(String contents);
}

enum Direction { recognize, recall }

enum WordStatus { fresh, learning, lasting, known }

int cardId(int wordIndex, Direction d) => wordIndex * 2 + d.index;

class StudyCard {
  const StudyCard(this.word, this.direction, this.state);

  final Word word;
  final Direction direction;

  /// Null the first time the card is seen.
  final CardState? state;

  int get id => cardId(word.index, direction);
  bool get isNewWord => state == null && direction == Direction.recognize;
}

class Settings {
  int newPerDay = 15;
  bool reminder = true;
  int reminderMinute = 20 * 60;
  bool autoSpeak = true;

  Map<String, dynamic> toJson() => {
        'newPerDay': newPerDay,
        'reminder': reminder,
        'reminderMinute': reminderMinute,
        'autoSpeak': autoSpeak,
      };

  static Settings fromJson(Map<String, dynamic> j) => Settings()
    ..newPerDay = j['newPerDay'] as int
    ..reminder = j['reminder'] as bool
    ..reminderMinute = j['reminderMinute'] as int
    ..autoSpeak = j['autoSpeak'] as bool;
}

class DayLog {
  DayLog([
    this.reviews = 0,
    this.newWords = 0,
    this.newRecalls = 0,
    this.graded = 0,
    this.correct = 0,
  ]);

  int reviews;
  int newWords;
  int newRecalls;

  /// Answers on matured cards, the only fair measure of what was kept.
  int graded;
  int correct;

  DayLog copy() => DayLog(reviews, newWords, newRecalls, graded, correct);
  List<int> toJson() => [reviews, newWords, newRecalls, graded, correct];
  static DayLog fromJson(List<dynamic> j) =>
      DayLog(j[0] as int, j[1] as int, j[2] as int, j[3] as int, j[4] as int);
}

class Stats {
  const Stats({
    required this.total,
    required this.started,
    required this.lasting,
    required this.known,
    required this.streak,
    required this.retention,
    required this.lastDays,
    required this.nextDays,
  });

  final int total;
  final int started;

  /// Words remembered for three weeks or more, in both directions.
  final int lasting;
  final int known;
  final int streak;

  /// Share of matured reviews answered right in the last 30 days, 0..1.
  final double? retention;
  final List<int> lastDays;
  final List<int> nextDays;
}

class _Undo {
  _Undo(this.id, this.previous, this.day, this.log, this.sinceNew);

  final int id;
  final CardState? previous;
  final String day;
  final DayLog log;
  final int sinceNew;
}

class _Queue {
  final learningDue = <StudyCard>[];
  final learningSoon = <StudyCard>[];
  final reviews = <StudyCard>[];
  final news = <StudyCard>[];

  int get remaining =>
      learningDue.length + learningSoon.length + reviews.length + news.length;
}

/// How far ahead a card still in learning may be shown once nothing else is
/// left, so a session can finish instead of waiting ten minutes.
const _learnAhead = Duration(minutes: 20);

/// Reviews beyond this many days' worth of new words slow new ones down: new
/// words are what creates tomorrow's load, and a pile of reviews kills habits.
const _softLoad = 15;
const _hardLoad = 25;

const _lastingDays = 21.0;

/// From here on a meaning is settled enough to be tried before seeing choices.
const _heldChoicesDays = 7.0;
const _choiceCount = 4;
const _choiceRange = 200;
const _forecastDays = 14;
const _reminderDays = 7;
const _saveDelay = Duration(milliseconds: 800);

class Store extends ChangeNotifier {
  Store({
    required this.words,
    required this.persistence,
    required this.phone,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final List<Word> words;
  final Persistence persistence;
  final Phone phone;
  final DateTime Function() _clock;

  Settings settings = Settings();
  final _cards = <int, CardState>{};
  final _days = <String, DayLog>{};
  int _bonusNew = 0;
  String _bonusDay = '';
  int _sinceNew = 0;
  _Undo? _undo;
  Timer? _saveTimer;

  DateTime get now => _clock();

  late final Set<String> wordSet = {for (final w in words) normalize(w.word)};

  CardMode modeOf(StudyCard card) {
    final state = card.state;
    if (card.direction == Direction.recall) {
      return state == null ? CardMode.chooseWord : CardMode.typeWord;
    }
    if (state == null) return CardMode.intro;
    final settled =
        state.phase == Phase.review && state.stability >= _heldChoicesDays;
    return settled ? CardMode.chooseMeaningHeld : CardMode.chooseMeaning;
  }

  /// The right answer among neighbours in the frequency list. Verbs only meet
  /// verbs: if just one choice ended in -mek, the grammar would give it away.
  /// Stable for a card's turn, so a redraw cannot reshuffle the options.
  List<Word> choicesFor(StudyCard card) {
    final word = card.word;
    final random = Random(card.id * 31 + (card.state?.reps ?? 0));
    final around = [
      for (final w in words)
        if (w.index != word.index &&
            (w.index - word.index).abs() <= _choiceRange &&
            w.meaning != word.meaning)
          w,
    ]..shuffle(random);
    final sameKind = around.where((w) => _isVerb(w) == _isVerb(word));
    final picks = [...sameKind.take(_choiceCount - 1)];
    for (final w in around) {
      if (picks.length == _choiceCount - 1) break;
      if (!picks.contains(w)) picks.add(w);
    }
    return [word, ...picks]..shuffle(random);
  }

  bool _isVerb(Word word) {
    final first = word.meaning.split(RegExp('[,;(]')).first.trim();
    return first.endsWith('mek') || first.endsWith('mak');
  }

  Future<void> load() async {
    final raw = await persistence.read();
    if (raw == null) return;
    try {
      _apply(raw);
    } on Object {
      await persistence.quarantine(raw);
    }
    notifyListeners();
  }

  /// Parses everything first, so a bad file leaves the current state whole.
  void _apply(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final cards = {
      for (final e in (j['cards'] as Map<String, dynamic>).entries)
        int.parse(e.key): CardState.fromJson(e.value as List<dynamic>),
    };
    final days = {
      for (final e in (j['days'] as Map<String, dynamic>).entries)
        e.key: DayLog.fromJson(e.value as List<dynamic>),
    };
    final loaded = Settings.fromJson(j['settings'] as Map<String, dynamic>);
    _cards
      ..clear()
      ..addAll(cards);
    _days
      ..clear()
      ..addAll(days);
    settings = loaded;
  }

  String export() => jsonEncode({
        'v': 1,
        'cards': {
          for (final e in _cards.entries) '${e.key}': e.value.toJson(),
        },
        'days': {
          for (final e in _days.entries) e.key: e.value.toJson(),
        },
        'settings': settings.toJson(),
      });

  /// Replaces all progress. Returns false and changes nothing if [raw] is not
  /// a backup.
  Future<bool> import(String raw) async {
    try {
      _apply(raw);
    } on Object {
      return false;
    }
    _undo = null;
    await flush();
    await syncPhone();
    notifyListeners();
    return true;
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    await persistence.write(export());
  }

  DayLog get _today => _days[dayKey(now)] ?? DayLog();

  DayLog get _todayForWriting => _days.putIfAbsent(dayKey(now), DayLog.new);

  int get _dailyNewLimit =>
      settings.newPerDay + (_bonusDay == dayKey(now) ? _bonusNew : 0);

  /// A word's two directions never meet on one day: seeing one gives the
  /// other away, and the second answer would prove nothing.
  bool _siblingSeenToday(int index, Direction d, DateTime t) {
    final other = d == Direction.recognize ? Direction.recall : Direction.recognize;
    final state = _cards[cardId(index, other)];
    return state != null && daysBetween(state.lastReview, t) == 0;
  }

  _Queue _scan() {
    final t = now;
    final queue = _Queue();
    final endOfDay = dayStart(t, 1);
    final recallNew = <StudyCard>[];

    for (final word in words) {
      final i = word.index;
      final first = _cards[cardId(i, Direction.recognize)];
      if (first == null || first.phase == Phase.known) continue;
      // A word takes one review slot a day, however many of its cards are due.
      var reviewed = false;
      for (final d in Direction.values) {
        final state = _cards[cardId(i, d)];
        if (state == null) {
          // The recall card opens once the word has survived a night.
          if (!reviewed &&
              first.phase == Phase.review &&
              daysBetween(first.lastReview, t) > 0) {
            recallNew.add(StudyCard(word, d, null));
          }
          continue;
        }
        final card = StudyCard(word, d, state);
        if (state.phase == Phase.review) {
          if (!reviewed &&
              state.due.isBefore(endOfDay) &&
              !_siblingSeenToday(i, d, t)) {
            queue.reviews.add(card);
            reviewed = true;
          }
        } else if (!state.due.isAfter(t)) {
          queue.learningDue.add(card);
        } else if (state.due.difference(t) <= _learnAhead) {
          queue.learningSoon.add(card);
        }
      }
    }

    int byDue(StudyCard a, StudyCard b) => a.state!.due.compareTo(b.state!.due);
    queue.reviews.sort(byDue);
    queue.learningDue.sort(byDue);
    queue.learningSoon.sort(byDue);

    final recallRoom = settings.newPerDay - _today.newRecalls;
    if (recallRoom > 0) queue.reviews.addAll(recallNew.take(recallRoom));

    final allowance = _allowance(queue.reviews.length);
    for (final word in words) {
      if (queue.news.length >= allowance) break;
      if (!_cards.containsKey(cardId(word.index, Direction.recognize))) {
        queue.news.add(StudyCard(word, Direction.recognize, null));
      }
    }
    return queue;
  }

  int _allowance(int reviewsLeft) {
    final left = _dailyNewLimit - _today.newWords;
    if (left <= 0) return 0;
    final perDay = settings.newPerDay;
    if (reviewsLeft >= perDay * _hardLoad) return 0;
    if (reviewsLeft >= perDay * _softLoad) return (left / 2).ceil();
    return left;
  }

  /// What is left today, finishing the day's learning steps included.
  ({int reviews, int fresh}) get todayCounts {
    final q = _scan();
    return (
      reviews: q.reviews.length + q.learningDue.length + q.learningSoon.length,
      fresh: q.news.length,
    );
  }

  int get remaining => _scan().remaining;

  /// True when new words were held back today because reviews piled up.
  bool get newWordsPaused {
    final left = _dailyNewLimit - _today.newWords;
    final unseen = words.length - _startedWords;
    return left > 0 && _scan().news.length < left.clamp(0, unseen);
  }

  int get _startedWords => words
      .where((w) => _cards.containsKey(cardId(w.index, Direction.recognize)))
      .length;

  StudyCard? next() {
    final q = _scan();
    if (q.learningDue.isNotEmpty) return q.learningDue.first;
    // New words are dealt among reviews, not left for a tired end of session.
    if (q.news.isNotEmpty && (q.reviews.isEmpty || _sinceNew >= 3)) {
      return q.news.first;
    }
    if (q.reviews.isNotEmpty) return q.reviews.first;
    if (q.learningSoon.isNotEmpty) return q.learningSoon.first;
    return null;
  }

  void answer(StudyCard card, Rating rating) =>
      _commit(card, rating, schedule(_cards[card.id], rating, now));

  /// Records that a new word was shown. Its first real answer comes later.
  void introduce(StudyCard card) => _commit(card, null, introduced(now));

  void _commit(StudyCard card, Rating? rating, CardState next) {
    final t = now;
    final previous = _cards[card.id];
    final log = _todayForWriting;
    _undo = _Undo(card.id, previous, dayKey(t), log.copy(), _sinceNew);

    log.reviews++;
    if (card.isNewWord) {
      log.newWords++;
      _sinceNew = 0;
    } else {
      _sinceNew++;
      if (previous == null) log.newRecalls++;
      if (previous?.phase == Phase.review) {
        log.graded++;
        if (rating != Rating.again) log.correct++;
      }
    }

    _cards[card.id] = next;
    _changed();
  }

  bool get canUndo => _undo != null;

  void undo() {
    final u = _undo;
    if (u == null) return;
    if (u.previous == null) {
      _cards.remove(u.id);
    } else {
      _cards[u.id] = u.previous!;
    }
    _days[u.day] = u.log;
    _sinceNew = u.sinceNew;
    _undo = null;
    _changed();
  }

  bool isKnown(Word word) =>
      _cards[cardId(word.index, Direction.recognize)]?.phase == Phase.known;

  /// Takes a word out of study without touching the day's counts: skipping
  /// a word is not learning it.
  void markKnown(Word word) {
    _setKnown(word);
    _undo = null;
    _changed();
  }

  void _setKnown(Word word) {
    final t = now;
    final state = CardState(
      phase: Phase.known,
      step: 0,
      due: t,
      stability: 0,
      difficulty: 0,
      lastReview: t,
      reps: 0,
      lapses: 0,
    );
    for (final d in Direction.values) {
      _cards[cardId(word.index, d)] = state;
    }
  }

  void unmarkKnown(Word word) {
    for (final d in Direction.values) {
      _cards.remove(cardId(word.index, d));
    }
    _undo = null;
    _changed();
  }

  /// Marks the [count] most common untouched words as known.
  void skipFirst(int count) {
    for (final word in words.take(count)) {
      if (!_cards.containsKey(cardId(word.index, Direction.recognize))) {
        _setKnown(word);
      }
    }
    _undo = null;
    _changed();
  }

  void addBonusNew(int count) {
    final key = dayKey(now);
    if (_bonusDay != key) {
      _bonusDay = key;
      _bonusNew = 0;
    }
    _bonusNew += count;
    _changed();
  }

  void updateSettings(void Function(Settings) change) {
    change(settings);
    _changed();
    unawaited(syncPhone());
  }

  WordStatus statusOf(Word word) {
    final first = _cards[cardId(word.index, Direction.recognize)];
    if (first == null) return WordStatus.fresh;
    if (first.phase == Phase.known) return WordStatus.known;
    final second = _cards[cardId(word.index, Direction.recall)];
    final lasting = first.stability >= _lastingDays &&
        second != null &&
        second.stability >= _lastingDays;
    return lasting ? WordStatus.lasting : WordStatus.learning;
  }

  /// Cards falling due on each of the next [days] study days; anything overdue
  /// counts on the first.
  List<int> _forecast(int days) {
    final t = now;
    final counts = List.filled(days, 0);
    for (final state in _cards.values) {
      if (state.phase == Phase.known) continue;
      final inDays = daysBetween(t, state.due);
      if (inDays < days) counts[inDays < 0 ? 0 : inDays]++;
    }
    return counts;
  }

  Stats get stats {
    final t = now;
    var started = 0;
    var lasting = 0;
    var known = 0;
    for (final word in words) {
      switch (statusOf(word)) {
        case WordStatus.fresh:
          break;
        case WordStatus.known:
          known++;
        case WordStatus.lasting:
          lasting++;
          started++;
        case WordStatus.learning:
          started++;
      }
    }
    var graded = 0;
    var correct = 0;
    final last = <int>[];
    for (var i = 29; i >= 0; i--) {
      final log = _days[dayKey(dayStart(t, -i))];
      graded += log?.graded ?? 0;
      correct += log?.correct ?? 0;
      if (i < 14) last.add(log?.reviews ?? 0);
    }
    return Stats(
      total: words.length,
      started: started,
      lasting: lasting,
      known: known,
      streak: streak,
      retention: graded == 0 ? null : correct / graded,
      lastDays: last,
      nextDays: _forecast(7),
    );
  }

  /// Days in a row studied. Today only adds to it, it cannot break it yet.
  int get streak {
    final t = now;
    var offset = (_days[dayKey(t)]?.reviews ?? 0) > 0 ? 0 : -1;
    var count = 0;
    while ((_days[dayKey(dayStart(t, offset))]?.reviews ?? 0) > 0) {
      count++;
      offset--;
    }
    return count;
  }

  Future<void> syncPhone() async {
    final t = now;
    final forecast = _forecast(_forecastDays);
    final open = todayCounts;
    forecast[0] = open.reviews + open.fresh;

    final today = logicalDate(t);
    await phone.updateWidget(WidgetData(
      firstDay: DateTime.utc(today.year, today.month, today.day)
              .millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay,
      forecast: forecast,
      streak: streak,
    ));

    final reminders = <Reminder>[];
    if (settings.reminder) {
      for (var i = 0; i < _reminderDays; i++) {
        final at = DateTime(today.year, today.month, today.day + i,
            settings.reminderMinute ~/ 60, settings.reminderMinute % 60);
        final waiting = i == 0 ? forecast[0] : forecast[i] + settings.newPerDay;
        if (at.isAfter(t) && waiting > 0) {
          reminders.add(Reminder(
            id: 100 + i,
            at: at,
            body: '$waiting kelime seni bekliyor.',
          ));
        }
      }
    }
    await phone.schedule(reminders);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
