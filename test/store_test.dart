import 'dart:convert';

import 'package:ezber/core/date.dart';
import 'package:ezber/core/deck.dart';
import 'package:ezber/core/fsrs.dart';
import 'package:ezber/core/grade.dart';
import 'package:ezber/core/phone.dart';
import 'package:ezber/core/store.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryPersistence implements Persistence {
  String? saved;
  String? bad;

  @override
  Future<String?> read() async => saved;

  @override
  Future<void> write(String contents) async => saved = contents;

  @override
  Future<void> quarantine(String contents) async => bad = contents;
}

class RecordingPhone extends Phone {
  List<Reminder> reminders = [];
  WidgetData? widget;

  @override
  Future<void> schedule(List<Reminder> reminders) async =>
      this.reminders = reminders;

  @override
  Future<void> updateWidget(WidgetData data) async => widget = data;
}

List<Word> makeWords(int count) => [
      for (var i = 0; i < count; i++)
        Word(
          index: i,
          word: 'word$i',
          meaning: 'kelime$i',
          example: 'A word$i here.',
          exampleTr: 'Burada kelime$i.',
          form: 'word$i',
        ),
    ];

class Fixture {
  Fixture({int words = 100}) {
    store = Store(
      words: makeWords(words),
      persistence: persistence,
      phone: phone,
      clock: () => time,
    );
  }

  DateTime time = DateTime(2026, 11, 7, 12);
  final persistence = MemoryPersistence();
  final phone = RecordingPhone();
  late final Store store;

  /// Answers everything left today with [rating], minding the clock.
  int finishDay(Rating rating) {
    var count = 0;
    for (var card = store.next(); card != null; card = store.next()) {
      store.answer(card, rating);
      time = time.add(const Duration(seconds: 10));
      count++;
      if (count > 3000) fail('oturum bitmiyor');
    }
    return count;
  }

  void nextDay() => time = DateTime(time.year, time.month, time.day + 1, 12);
}

void main() {
  group('fsrs', () {
    final now = DateTime(2026, 11, 7, 12);

    test('a new card climbs the learning steps, then leaves for a day', () {
      final one = schedule(null, Rating.good, now);
      expect(one.phase, Phase.learning);
      expect(one.due, now.add(const Duration(minutes: 10)));
      final two = schedule(one, Rating.good, one.due);
      expect(two.phase, Phase.review);
      expect(two.due.isAfter(now.add(const Duration(hours: 12))), isTrue);
    });

    test('forgetting sends a card back and counts a lapse', () {
      final mature = CardState(
        phase: Phase.review,
        step: 0,
        due: now,
        stability: 40,
        difficulty: 5,
        lastReview: now.subtract(const Duration(days: 40)),
        reps: 6,
        lapses: 0,
      );
      final next = schedule(mature, Rating.again, now);
      expect(next.phase, Phase.relearning);
      expect(next.lapses, 1);
      expect(next.stability, lessThan(mature.stability));
    });

    test('intervals grow with each success, and better grades wait longer', () {
      var card = schedule(schedule(null, Rating.good, now), Rating.good, now);
      var last = 0;
      for (var i = 0; i < 6; i++) {
        final when = card.due.add(const Duration(hours: 8));
        final waits = {
          for (final r in [Rating.hard, Rating.good, Rating.easy])
            r: daysBetween(when, schedule(card, r, when).due),
        };
        expect(waits[Rating.hard]!, lessThan(waits[Rating.good]!));
        expect(waits[Rating.good]!, lessThan(waits[Rating.easy]!));
        expect(waits[Rating.good]!, greaterThan(last));
        last = waits[Rating.good]!;
        card = schedule(card, Rating.good, when);
      }
      expect(last, greaterThan(60));
    });

    test('a review on the due date lands on the 90% target', () {
      expect(retrievability(10, 10), closeTo(targetRetention, 0.001));
    });

    test('preview labels read as promised', () {
      final labels = previews(null, now);
      expect(labels[Rating.again], '1 dk');
      expect(labels[Rating.good], '10 dk');
      expect(labels[Rating.easy], endsWith('gün'));
    });
  });

  group('dates', () {
    test('the study day runs until 04:00', () {
      expect(dayKey(DateTime(2026, 11, 8, 3, 59)), '2026-11-07');
      expect(dayKey(DateTime(2026, 11, 8, 4)), '2026-11-08');
    });
  });

  group('queue', () {
    test('words arrive in frequency order and stop at the daily limit', () {
      final f = Fixture();
      final first = f.store.next()!;
      expect(first.word.index, 0);
      expect(first.isNewWord, isTrue);
      f.finishDay(Rating.good);
      expect(f.store.todayCounts.fresh, 0);
      expect(f.store.stats.started, f.store.settings.newPerDay);
    });

    test('a session finishes without waiting out the learning steps', () {
      final f = Fixture();
      f.finishDay(Rating.good);
      expect(f.store.next(), isNull);
    });

    test('a missed word keeps coming back until it is known', () {
      final f = Fixture(words: 1);
      final card = f.store.next()!;
      f.store.answer(card, Rating.again);
      f.time = f.time.add(const Duration(minutes: 2));
      expect(f.store.next()!.id, card.id);
    });

    test('the two directions of a word never share a day', () {
      final f = Fixture();
      for (var day = 0; day < 12; day++) {
        final seen = <int, Set<Direction>>{};
        for (var card = f.store.next(); card != null; card = f.store.next()) {
          seen.putIfAbsent(card.word.index, () => {}).add(card.direction);
          f.store.answer(card, Rating.good);
          f.time = f.time.add(const Duration(seconds: 5));
        }
        expect(seen.values.where((d) => d.length > 1), isEmpty, reason: 'gün $day');
        f.nextDay();
      }
    });

    test('the count on the home screen is what the session delivers', () {
      final f = Fixture();
      f.finishDay(Rating.easy);
      f.time = f.time.add(const Duration(days: 40));
      f.store.updateSettings((s) => s.newPerDay = 0);
      final promised = f.store.todayCounts.reviews;
      expect(promised, 15);
      expect(f.finishDay(Rating.easy), promised);
    });

    test('recall opens only after a night', () {
      final f = Fixture(words: 1);
      f.finishDay(Rating.easy);
      expect(f.store.next(), isNull);
      f.time = f.store.now.add(const Duration(days: 40));
      final directions = <Direction>{};
      for (var day = 0; day < 3; day++) {
        for (var card = f.store.next(); card != null; card = f.store.next()) {
          directions.add(card.direction);
          f.store.answer(card, Rating.easy);
        }
        f.nextDay();
      }
      expect(directions, contains(Direction.recall));
    });

    test('a pile of reviews slows new words, and a bigger one stops them', () {
      final f = Fixture(words: 800);
      f.store.updateSettings((s) => s.newPerDay = 5);
      f.store.addBonusNew(500);
      f.finishDay(Rating.good);
      f.time = f.time.add(const Duration(days: 60));
      expect(f.store.todayCounts.reviews, greaterThan(125));
      expect(f.store.todayCounts.fresh, 0);
      expect(f.store.newWordsPaused, isTrue);
    });

    test('new words are mixed in among reviews', () {
      final f = Fixture();
      f.finishDay(Rating.good);
      f.time = f.time.add(const Duration(days: 5));
      final order = <bool>[];
      for (var card = f.store.next();
          card != null && order.length < 12;
          card = f.store.next()) {
        order.add(card.isNewWord);
        f.store.answer(card, Rating.easy);
      }
      final fresh = [
        for (final (i, isNew) in order.indexed)
          if (isNew) i,
      ];
      expect(fresh.length, greaterThanOrEqualTo(2));
      expect(fresh[1] - fresh[0], greaterThan(1));
    });
  });

  group('grading', () {
    const went = Word(
      index: 0,
      word: 'go',
      meaning: 'gitmek',
      example: 'She went home.',
      exampleTr: 'Eve gitti.',
      form: 'went',
    );
    const quite = Word(
      index: 1,
      word: 'quite',
      meaning: 'oldukça',
      example: 'It is quite good.',
      exampleTr: 'Oldukça iyi.',
      form: 'quite',
    );
    const before = Word(
      index: 2,
      word: 'before',
      meaning: 'önce',
      example: 'Come before noon.',
      exampleTr: 'Öğleden önce gel.',
      form: 'before',
    );

    test('takes the word or the form in the sentence', () {
      expect(checkTyped('go', went, {}), Verdict.right);
      expect(checkTyped(' Went ', went, {}), Verdict.right);
    });

    test('a Turkish keyboard is not a spelling mistake', () {
      expect(checkTyped('quıte', quite, {}), Verdict.right);
      expect(checkTyped('QUİTE', quite, {}), Verdict.right);
    });

    test('forgives one slip in a long word, not in a short one', () {
      expect(checkTyped('befor', before, {}), Verdict.close);
      expect(checkTyped('beofre', before, {}), Verdict.close);
      expect(checkTyped('wnet', went, {}), Verdict.wrong);
      expect(checkTyped('bfr', before, {}), Verdict.wrong);
    });

    test('another real word is wrong, however close', () {
      expect(checkTyped('quiet', quite, {'quiet', 'quite'}), Verdict.wrong);
    });

    test('an empty answer is wrong', () {
      expect(checkTyped('  ', went, {}), Verdict.wrong);
    });

    test('grades come from the answer', () {
      Rating rate(Verdict v, int seconds, CardMode mode) =>
          ratingFor(v, Duration(seconds: seconds), mode: mode, state: null);
      expect(rate(Verdict.wrong, 1, CardMode.typeWord), Rating.again);
      expect(rate(Verdict.close, 1, CardMode.typeWord), Rating.hard);
      expect(rate(Verdict.right, 3, CardMode.chooseMeaning), Rating.good);
      expect(rate(Verdict.right, 12, CardMode.chooseMeaning), Rating.hard);
      expect(rate(Verdict.right, 12, CardMode.chooseMeaningHeld), Rating.good);
      expect(rate(Verdict.right, 2, CardMode.typeWord), Rating.good,
          reason: 'öğrenme aşamasında kolay yok');
    });
  });

  group('modes', () {
    test('a word goes from shown, to chosen, to written', () {
      final f = Fixture(words: 1);
      final fresh = f.store.next()!;
      expect(f.store.modeOf(fresh), CardMode.intro);
      f.store.introduce(fresh);

      f.time = f.time.add(const Duration(minutes: 2));
      final test = f.store.next()!;
      expect(test.id, fresh.id, reason: 'testi aynı oturumda gelir');
      expect(f.store.modeOf(test), CardMode.chooseMeaning);
      f.store.answer(test, Rating.good);
      f.time = f.time.add(const Duration(minutes: 11));
      f.store.answer(f.store.next()!, Rating.good);

      f.time = f.time.add(const Duration(days: 40));
      f.store.answer(f.store.next()!, Rating.good);
      f.nextDay();
      final recall = f.store.next()!;
      expect(recall.direction, Direction.recall);
      expect(f.store.modeOf(recall), CardMode.chooseWord);
      f.store.answer(recall, Rating.good);
      f.time = f.time.add(const Duration(minutes: 2));
      expect(f.store.modeOf(f.store.next()!), CardMode.typeWord);
    });

    test('a settled meaning hides its choices at first', () {
      final f = Fixture(words: 1);
      f.store.answer(f.store.next()!, Rating.easy);
      f.time = f.time.add(const Duration(days: 40));
      expect(f.store.modeOf(f.store.next()!), CardMode.chooseMeaningHeld);
    });

    test('showing a word counts it once, as started', () {
      final f = Fixture();
      f.store.introduce(f.store.next()!);
      expect(f.store.todayCounts.fresh, f.store.settings.newPerDay - 1);
      expect(f.store.stats.started, 1);
    });

    test('choices are four, hold the answer, repeat nothing and stay put', () {
      final f = Fixture(words: 400);
      for (final index in [0, 200, 399]) {
        final card = StudyCard(f.store.words[index], Direction.recognize, null);
        final choices = f.store.choicesFor(card);
        expect(choices, hasLength(4));
        expect(choices, contains(card.word));
        expect(choices.toSet(), hasLength(4));
        expect(f.store.choicesFor(card), choices);
      }
    });

    test('a verb is only offered among verbs', () {
      final words = [
        for (var i = 0; i < 40; i++)
          Word(
            index: i,
            word: 'w$i',
            meaning: i.isEven ? 'yapmak$i, etmek' : 'ev$i',
            example: 'w$i',
            exampleTr: 'w$i',
            form: 'w$i',
          ),
      ];
      final verbs = [
        for (final w in words)
          Word(
            index: w.index,
            word: w.word,
            meaning: w.index.isEven ? 'yapmak, ${w.index}' : w.meaning,
            example: w.example,
            exampleTr: w.exampleTr,
            form: w.form,
          ),
      ];
      final store = Store(
          words: verbs, persistence: MemoryPersistence(), phone: SilentPhone());
      final choices =
          store.choicesFor(StudyCard(verbs[10], Direction.recognize, null));
      expect(choices.every((w) => w.index.isEven), isTrue);
    });
  });

  group('known words', () {
    test('a known word leaves study and does not use up the day', () {
      final f = Fixture();
      final card = f.store.next()!;
      f.store.markKnown(card.word);
      expect(f.store.next()!.word.index, 1);
      expect(f.store.todayCounts.fresh, f.store.settings.newPerDay);
      expect(f.store.statusOf(card.word), WordStatus.known);
    });

    test('skipFirst leaves studied words alone', () {
      final f = Fixture();
      f.store.answer(f.store.next()!, Rating.good);
      f.store.skipFirst(50);
      expect(f.store.statusOf(f.store.words[0]), WordStatus.learning);
      expect(f.store.statusOf(f.store.words[1]), WordStatus.known);
      expect(f.store.statusOf(f.store.words[50]), WordStatus.fresh);
    });

    test('unmarking brings a word back', () {
      final f = Fixture();
      final word = f.store.next()!.word;
      f.store.markKnown(word);
      f.store.unmarkKnown(word);
      expect(f.store.next()!.word.index, word.index);
    });
  });

  group('undo', () {
    test('restores the card and the day', () {
      final f = Fixture();
      final card = f.store.next()!;
      f.store.answer(card, Rating.easy);
      expect(f.store.streak, 1);
      f.store.undo();
      expect(f.store.next()!.id, card.id);
      expect(f.store.streak, 0);
      expect(f.store.canUndo, isFalse);
    });
  });

  group('stats', () {
    test('the streak waits for today, and breaks on a gap', () {
      final f = Fixture();
      f.store.answer(f.store.next()!, Rating.good);
      f.nextDay();
      expect(f.store.streak, 1, reason: 'bugün henüz çalışılmadı');
      f.store.answer(f.store.next()!, Rating.good);
      expect(f.store.streak, 2);
      f.nextDay();
      f.nextDay();
      expect(f.store.streak, 0);
    });

    test('a word lasts only when both directions hold', () {
      final f = Fixture(words: 1);
      for (var day = 0; day < 200; day++) {
        f.finishDay(Rating.easy);
        f.nextDay();
      }
      expect(f.store.statusOf(f.store.words[0]), WordStatus.lasting);
    });
  });

  group('saving', () {
    test('progress survives a restart', () async {
      final f = Fixture();
      f.finishDay(Rating.good);
      await f.store.flush();

      final again = Store(
        words: f.store.words,
        persistence: f.persistence,
        phone: SilentPhone(),
        clock: () => f.time,
      );
      await again.load();
      expect(again.export(), f.store.export());
      expect(again.next(), isNull);
    });

    test('an unreadable save is kept aside, not overwritten', () async {
      final f = Fixture();
      f.persistence.saved = '{bozuk';
      await f.store.load();
      expect(f.persistence.bad, '{bozuk');
      expect(f.store.next(), isNotNull);
    });

    test('a file that is not a backup changes nothing', () async {
      final f = Fixture();
      f.store.answer(f.store.next()!, Rating.good);
      final before = f.store.export();
      expect(await f.store.import(jsonEncode({'cards': 1})), isFalse);
      expect(await f.store.import('merhaba'), isFalse);
      expect(f.store.export(), before);
    });

    test('a backup moves everything across', () async {
      final f = Fixture();
      f.finishDay(Rating.good);
      final other = Fixture();
      other.time = f.time;
      expect(await other.store.import(f.store.export()), isTrue);
      expect(other.store.export(), f.store.export());
    });
  });

  group('phone', () {
    test('reminders skip a finished today and keep the coming days', () async {
      final f = Fixture();
      f.finishDay(Rating.good);
      await f.store.syncPhone();
      final days = f.phone.reminders.map((r) => dayKey(r.at)).toList();
      expect(days, isNot(contains('2026-11-07')));
      expect(days, contains('2026-11-08'));
      expect(f.phone.reminders.first.at.hour, 20);
    });

    test('turning reminders off clears them', () async {
      final f = Fixture();
      f.store.updateSettings((s) => s.reminder = false);
      await f.store.syncPhone();
      expect(f.phone.reminders, isEmpty);
    });

    test('the widget gets two weeks, starting from what is open today', () async {
      final f = Fixture();
      await f.store.syncPhone();
      expect(f.phone.widget!.forecast, hasLength(14));
      expect(f.phone.widget!.forecast.first, f.store.settings.newPerDay);
    });
  });

  group('deck', () {
    test('splits an example around the word as written', () {
      const word = Word(
        index: 0,
        word: 'go',
        meaning: 'gitmek',
        example: 'She went home.',
        exampleTr: 'Eve gitti.',
        form: 'went',
      );
      expect(word.exampleParts, ('She ', 'went', ' home.'));
    });
  });
}
