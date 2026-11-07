import 'dart:math';

import 'date.dart';

enum Rating { again, hard, good, easy }

enum Phase { learning, review, relearning, known }

/// FSRS-5 default weights, fitted by its authors on real review histories.
const _w = [
  0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575,
  0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655,
  0.6621,
];
const _decay = -0.5;
const _factor = 19 / 81;

/// A card comes back when the chance of recalling it falls to this.
const targetRetention = 0.9;
const maxIntervalDays = 3650;
const learnSteps = [Duration(minutes: 1), Duration(minutes: 10)];
const relearnStep = Duration(minutes: 10);

class CardState {
  const CardState({
    required this.phase,
    required this.step,
    required this.due,
    required this.stability,
    required this.difficulty,
    required this.lastReview,
    required this.reps,
    required this.lapses,
  });

  final Phase phase;
  final int step;
  final DateTime due;

  /// Days until recall probability drops to 90%.
  final double stability;
  final double difficulty;
  final DateTime lastReview;
  final int reps;
  final int lapses;

  List<num> toJson() => [
        phase.index,
        step,
        due.millisecondsSinceEpoch,
        stability,
        difficulty,
        lastReview.millisecondsSinceEpoch,
        reps,
        lapses,
      ];

  factory CardState.fromJson(List<dynamic> j) => CardState(
        phase: Phase.values[j[0] as int],
        step: j[1] as int,
        due: DateTime.fromMillisecondsSinceEpoch(j[2] as int),
        stability: (j[3] as num).toDouble(),
        difficulty: (j[4] as num).toDouble(),
        lastReview: DateTime.fromMillisecondsSinceEpoch(j[5] as int),
        reps: j[6] as int,
        lapses: j[7] as int,
      );
}

double retrievability(double elapsedDays, double stability) =>
    pow(1 + _factor * elapsedDays / stability, _decay).toDouble();

int _interval(double stability) {
  final days = stability / _factor * (pow(targetRetention, 1 / _decay) - 1);
  return days.round().clamp(1, maxIntervalDays);
}

double _clampD(double d) => d.clamp(1.0, 10.0);

double _initialDifficulty(Rating r) =>
    _clampD(_w[4] - exp(_w[5] * r.index) + 1);

double _nextDifficulty(double d, Rating r) {
  final delta = -_w[6] * (r.index + 1 - 3);
  final damped = d + delta * (10 - d) / 9;
  // Mean reversion, so one bad day does not mark a word hard for good.
  return _clampD(_w[7] * _initialDifficulty(Rating.easy) + (1 - _w[7]) * damped);
}

double _recallStability(double d, double s, double r, Rating rating) {
  final hard = rating == Rating.hard ? _w[15] : 1.0;
  final easy = rating == Rating.easy ? _w[16] : 1.0;
  return s *
      (1 +
          exp(_w[8]) *
              (11 - d) *
              pow(s, -_w[9]) *
              (exp(_w[10] * (1 - r)) - 1) *
              hard *
              easy);
}

double _forgetStability(double d, double s, double r) {
  final next = _w[11] *
      pow(d, -_w[12]) *
      (pow(s + 1, _w[13]) - 1) *
      exp(_w[14] * (1 - r));
  return min(next, s / exp(_w[17] * _w[18]));
}

double _sameDayStability(double s, Rating r) =>
    s * exp(_w[17] * (r.index + 1 - 3 + _w[18]));

/// What a card becomes after [rating]. [card] is null for a first sighting.
CardState schedule(CardState? card, Rating rating, DateTime now) {
  if (card == null) {
    final s = _w[rating.index];
    final d = _initialDifficulty(rating);
    return _step(0, s, d, rating, now, reps: 1, lapses: 0, first: true);
  }

  final reps = card.reps + 1;
  final d = _nextDifficulty(card.difficulty, rating);

  if (card.phase == Phase.review) {
    final elapsed = max(0, daysBetween(card.lastReview, now));
    final r = retrievability(elapsed.toDouble(), card.stability);
    if (rating == Rating.again) {
      return CardState(
        phase: Phase.relearning,
        step: 0,
        due: now.add(relearnStep),
        stability: _forgetStability(card.difficulty, card.stability, r),
        difficulty: d,
        lastReview: now,
        reps: reps,
        lapses: card.lapses + 1,
      );
    }
    final next = {
      for (final g in [Rating.hard, Rating.good, Rating.easy])
        g: _recallStability(card.difficulty, card.stability, r, g),
    };
    // Better grades must always wait longer, even when the formula rounds
    // two of them to the same day.
    final hard = _interval(next[Rating.hard]!);
    final good = max(_interval(next[Rating.good]!), hard + 1);
    final easy = max(_interval(next[Rating.easy]!), good + 1);
    final days = switch (rating) {
      Rating.hard => hard,
      Rating.good => good,
      _ => easy,
    };
    return CardState(
      phase: Phase.review,
      step: 0,
      due: dayStart(now, days),
      stability: next[rating]!,
      difficulty: d,
      lastReview: now,
      reps: reps,
      lapses: card.lapses,
    );
  }

  final s = _sameDayStability(card.stability, rating);
  if (card.phase == Phase.relearning) {
    if (rating == Rating.again || rating == Rating.hard) {
      return CardState(
        phase: Phase.relearning,
        step: 0,
        due: now.add(relearnStep),
        stability: s,
        difficulty: d,
        lastReview: now,
        reps: reps,
        lapses: card.lapses,
      );
    }
    return _graduate(s, d, now, reps, card.lapses);
  }
  return _step(card.step, s, d, rating, now, reps: reps, lapses: card.lapses);
}

/// A word that was only shown so far. Its first test comes a minute later:
/// seeing an answer teaches little, fetching it from memory is what sticks.
CardState introduced(DateTime now) {
  final seen = schedule(null, Rating.good, now);
  return CardState(
    phase: Phase.learning,
    step: 0,
    due: now.add(learnSteps[0]),
    stability: seen.stability,
    difficulty: seen.difficulty,
    lastReview: now,
    reps: 0,
    lapses: 0,
  );
}

CardState _step(
  int step,
  double s,
  double d,
  Rating rating,
  DateTime now, {
  required int reps,
  required int lapses,
  bool first = false,
}) {
  CardState stay(int at, Duration wait) => CardState(
        phase: Phase.learning,
        step: at,
        due: now.add(wait),
        stability: s,
        difficulty: d,
        lastReview: now,
        reps: reps,
        lapses: lapses,
      );

  return switch (rating) {
    Rating.again => stay(0, learnSteps[0]),
    // Halfway to the next step: slower than Good, kinder than Again.
    Rating.hard => stay(step, const Duration(minutes: 6)),
    Rating.good when first || step + 1 < learnSteps.length =>
      stay(first ? 1 : step + 1, learnSteps[first ? 1 : step + 1]),
    _ => _graduate(s, d, now, reps, lapses),
  };
}

CardState _graduate(double s, double d, DateTime now, int reps, int lapses) =>
    CardState(
      phase: Phase.review,
      step: 0,
      due: dayStart(now, _interval(s)),
      stability: s,
      difficulty: d,
      lastReview: now,
      reps: reps,
      lapses: lapses,
    );

/// The wait each button promises, as shown under it.
Map<Rating, String> previews(CardState? card, DateTime now) => {
      for (final r in Rating.values) r: _label(schedule(card, r, now), now),
    };

String _label(CardState next, DateTime now) {
  if (next.phase != Phase.review) {
    return '${next.due.difference(now).inMinutes} dk';
  }
  final days = daysBetween(now, next.due);
  if (days < 30) return '$days gün';
  if (days < 365) return '${(days / 30).round()} ay';
  return '${(days / 365).toStringAsFixed(1)} yıl';
}
