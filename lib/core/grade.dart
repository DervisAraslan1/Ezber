import 'deck.dart';
import 'fsrs.dart';

enum Verdict { right, close, wrong }

/// How a card asks for its answer.
enum CardMode {
  /// First sight: nothing to answer yet, the word is only shown.
  intro,

  /// English word, pick the Turkish meaning.
  chooseMeaning,

  /// Same, with the choices hidden until the answer was tried from memory.
  chooseMeaningHeld,

  /// Turkish meaning, pick the English word.
  chooseWord,

  /// Turkish meaning and a gapped sentence, write the English word.
  typeWord,
}

const _quickTyping = Duration(seconds: 4);
const _slowChoice = Duration(seconds: 8);
const _minLengthForTypo = 5;

/// Turkish keyboards turn i into ı or İ; that is not a spelling mistake.
String normalize(String text) => text
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll(RegExp(r"[^a-z' -]"), '')
    .trim();

/// Edits between two words, a swap of neighbouring letters counting as one.
int editDistance(String a, String b) {
  var before = <int>[];
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final row = List.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var best = [
        previous[j] + 1,
        row[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        final swap = before[j - 2] + 1;
        if (swap < best) best = swap;
      }
      row[j] = best;
    }
    before = previous;
    previous = row;
  }
  return previous[b.length];
}

/// Judges a typed answer. One slipped letter is forgiven, unless what was
/// typed is itself a different word of the list: quiet is not quite.
Verdict checkTyped(String input, Word word, Set<String> allWords) {
  final answer = normalize(input);
  final accepted = {normalize(word.word), normalize(word.form)};
  if (accepted.contains(answer)) return Verdict.right;
  if (answer.isEmpty || allWords.contains(answer)) return Verdict.wrong;
  final near = accepted.any(
      (a) => a.length >= _minLengthForTypo && editDistance(answer, a) == 1);
  return near ? Verdict.close : Verdict.wrong;
}

/// Turns what happened into the grade the scheduler needs, so nobody has to
/// judge their own memory.
Rating ratingFor(
  Verdict verdict,
  Duration took, {
  required CardMode mode,
  required CardState? state,
}) {
  if (verdict == Verdict.wrong) return Rating.again;
  if (verdict == Verdict.close) return Rating.hard;
  if (mode == CardMode.typeWord) {
    final settled = state?.phase == Phase.review;
    return settled && took < _quickTyping ? Rating.easy : Rating.good;
  }
  // Time spent before opening held choices is thinking, not hesitation.
  if (mode != CardMode.chooseMeaningHeld && took > _slowChoice) {
    return Rating.hard;
  }
  return Rating.good;
}
