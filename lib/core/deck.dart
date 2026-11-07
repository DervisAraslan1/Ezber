import 'dart:convert';

class Word {
  const Word({
    required this.index,
    required this.word,
    required this.meaning,
    required this.example,
    required this.exampleTr,
    required this.form,
  });

  /// Position in the frequency list, the most common word first.
  final int index;
  final String word;
  final String meaning;
  final String example;
  final String exampleTr;

  /// The way [word] is written inside [example], e.g. "went" for "go".
  final String form;

  /// [example] split around [form]: before, the word as written, after.
  (String, String, String) get exampleParts {
    final match = RegExp('\\b${RegExp.escape(form)}\\b', caseSensitive: false)
        .firstMatch(example);
    if (match == null) return (example, '', '');
    return (
      example.substring(0, match.start),
      match.group(0)!,
      example.substring(match.end),
    );
  }
}

List<Word> parseDeck(String source) {
  final rows = jsonDecode(source) as List<dynamic>;
  return [
    for (final (i, row) in rows.indexed)
      Word(
        index: i,
        word: row['w'] as String,
        meaning: row['t'] as String,
        example: row['e'] as String,
        exampleTr: row['s'] as String,
        form: row['f'] as String,
      ),
  ];
}
