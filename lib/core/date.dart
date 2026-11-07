/// A study day ends at 04:00, so a late-night session still counts as today.
const rolloverHour = 4;

DateTime logicalDate(DateTime t) {
  final shifted = t.subtract(const Duration(hours: rolloverHour));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// The moment the study day [days] after [now] begins.
DateTime dayStart(DateTime now, int days) {
  final d = logicalDate(now);
  return DateTime(d.year, d.month, d.day + days, rolloverHour);
}

String dayKey(DateTime t) {
  final d = logicalDate(t);
  final month = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$month-$day';
}

/// Whole study days from [a] to [b].
int daysBetween(DateTime a, DateTime b) {
  final from = logicalDate(a);
  final to = logicalDate(b);
  return DateTime.utc(to.year, to.month, to.day)
      .difference(DateTime.utc(from.year, from.month, from.day))
      .inDays;
}
