import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/deck.dart';
import '../core/fsrs.dart';
import '../core/grade.dart';
import '../core/store.dart';
import 'theme.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.store});

  final Store store;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  final _watch = Stopwatch();
  StudyCard? _card;
  CardMode _mode = CardMode.intro;
  List<Word> _choices = [];
  var _done = 0;
  late int _total;

  /// Set once answered; the card stays up until the learner moves on.
  Verdict? _verdict;
  Rating? _rating;
  String? _typed;
  Word? _picked;

  Store get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _total = _store.remaining;
    _load();
  }

  @override
  void dispose() {
    unawaited(_store.flush());
    unawaited(_store.syncPhone());
    super.dispose();
  }

  void _load() {
    final card = _store.next();
    _card = card;
    _verdict = null;
    _rating = null;
    _typed = null;
    _picked = null;
    _watch
      ..reset()
      ..start();
    if (card == null) return;
    _mode = _store.modeOf(card);
    _choices = _store.choicesFor(card);
    // When the English word is the answer, its sound must wait for the end.
    final hidden = _mode == CardMode.chooseWord || _mode == CardMode.typeWord;
    if (!hidden) _speakWord(card.word);
  }

  void _speakWord(Word word) {
    if (_store.settings.autoSpeak) _speak(word.word);
  }

  void _speak(String text) => unawaited(_store.phone.speak(text));

  void _settle(Verdict verdict) {
    final card = _card!;
    _watch.stop();
    HapticFeedback.selectionClick();
    setState(() {
      _verdict = verdict;
      _rating = ratingFor(verdict, _watch.elapsed,
          mode: _mode, state: card.state);
    });
    if (card.direction == Direction.recall) _speakWord(card.word);
  }

  void _pick(Word choice) {
    _picked = choice;
    _settle(choice.index == _card!.word.index ? Verdict.right : Verdict.wrong);
  }

  void _submit(String text) {
    _typed = text;
    _settle(checkTyped(text, _card!.word, _store.wordSet));
  }

  /// A checker cannot know every spelling variant; the learner can overrule it.
  void _overrule() => setState(() {
        _verdict = Verdict.right;
        _rating = Rating.good;
      });

  void _next() {
    final card = _card!;
    if (_mode == CardMode.intro) {
      _store.introduce(card);
    } else {
      _store.answer(card, _rating!);
    }
    setState(() {
      _done++;
      _total = max(_total, _done + _store.remaining);
      _load();
    });
  }

  void _undo() {
    _store.undo();
    setState(() {
      _done = max(0, _done - 1);
      _load();
    });
  }

  void _skipKnown() {
    final word = _card!.word;
    final messenger = ScaffoldMessenger.of(context);
    _store.markKnown(word);
    setState(() {
      _total = max(0, _total - 1);
      _load();
    });
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('“${word.word}” bilinenlere eklendi'),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () {
            _store.unmarkKnown(word);
            setState(() {
              _total++;
              _load();
            });
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Kapat',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _total == 0 ? 1 : _done / _total,
            minHeight: 8,
            backgroundColor: colors.outlineVariant,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Son cevabı geri al',
            icon: const Icon(Icons.undo),
            onPressed: _verdict == null && _store.canUndo ? _undo : null,
          ),
        ],
      ),
      body: SafeArea(
        child: card == null
            ? _Finished(done: _done)
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: _body(card),
              ),
      ),
    );
  }

  Widget _body(StudyCard card) {
    final key = ValueKey('${card.id}-$_done');
    if (_mode == CardMode.intro) {
      return _Intro(
        key: key,
        word: card.word,
        onSpeak: _speak,
        onKnown: _skipKnown,
        onNext: _next,
      );
    }
    if (_mode == CardMode.typeWord) {
      if (_verdict == null) {
        return _TypeAnswer(
          key: key,
          word: card.word,
          onSubmit: _submit,
          onGiveUp: () => _submit(''),
        );
      }
    } else if (_verdict == null || _picked != null) {
      return _Choose(
        key: key,
        card: card,
        mode: _mode,
        choices: _choices,
        picked: _picked,
        onPick: _verdict == null ? _pick : null,
        onSpeak: _speak,
        feedback: _picked == null ? null : _feedback(card),
      );
    }
    return Column(
      children: [
        Expanded(child: _Card(child: SingleChildScrollView(child: _reveal(card)))),
        const SizedBox(height: 16),
        _feedback(card),
      ],
    );
  }

  Widget _reveal(StudyCard card) => Column(
        children: [
          if (_typed != null && _verdict != Verdict.right) ...[
            Text(
              _typed!.trim().isEmpty ? 'Cevap yazmadın' : 'Yazdığın: ${_typed!.trim()}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
          ],
          WordFacts(word: card.word, onSpeak: _speak),
        ],
      );

  Widget _feedback(StudyCard card) => _Feedback(
        verdict: _verdict!,
        wait: previews(card.state, _store.now)[_rating!]!,
        canOverrule: _typed != null &&
            _typed!.trim().isNotEmpty &&
            _verdict != Verdict.right,
        onOverrule: _overrule,
        onNext: _next,
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
      );
}

class _BigWord extends StatelessWidget {
  const _BigWord({required this.word, required this.onSpeak});

  final String word;
  final ValueChanged<String> onSpeak;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                word,
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dinle',
            icon: const Icon(Icons.volume_up_outlined),
            onPressed: () => onSpeak(word),
          ),
        ],
      );
}

/// The word with its meaning and its sentence, tap the sentence to hear it.
class WordFacts extends StatelessWidget {
  const WordFacts({super.key, required this.word, required this.onSpeak});

  final Word word;
  final ValueChanged<String> onSpeak;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BigWord(word: word.word, onSpeak: onSpeak),
        const SizedBox(height: 8),
        Text(
          word.meaning,
          textAlign: TextAlign.center,
          style: text.titleLarge?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onSpeak(word.example),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                ExampleText(word: word),
                const SizedBox(height: 6),
                Text(
                  word.exampleTr,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    super.key,
    required this.word,
    required this.onSpeak,
    required this.onKnown,
    required this.onNext,
  });

  final Word word;
  final ValueChanged<String> onSpeak;
  final VoidCallback onKnown;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Card(
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: _Tag('YENİ KELİME')),
                      TextButton(
                        onPressed: onKnown,
                        child: const Text('Biliyorum'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: WordFacts(word: word, onSpeak: onSpeak),
                      ),
                    ),
                  ),
                  Text(
                    'Birazdan bunu sana soracağım',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onNext, child: const Text('Devam')),
        ],
      );
}

class _Choose extends StatefulWidget {
  const _Choose({
    super.key,
    required this.card,
    required this.mode,
    required this.choices,
    required this.picked,
    required this.onPick,
    required this.onSpeak,
    required this.feedback,
  });

  final StudyCard card;
  final CardMode mode;
  final List<Word> choices;
  final Word? picked;
  final ValueChanged<Word>? onPick;
  final ValueChanged<String> onSpeak;
  final Widget? feedback;

  @override
  State<_Choose> createState() => _ChooseState();
}

class _ChooseState extends State<_Choose> {
  late var _open = widget.mode != CardMode.chooseMeaningHeld;

  @override
  Widget build(BuildContext context) {
    final word = widget.card.word;
    final showsMeaning = widget.mode == CardMode.chooseWord;
    final text = Theme.of(context).textTheme;
    final answered = widget.picked != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _Card(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (answered)
                    WordFacts(word: word, onSpeak: widget.onSpeak)
                  else if (showsMeaning)
                    Text(
                      word.meaning,
                      textAlign: TextAlign.center,
                      style: text.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    )
                  else
                    _BigWord(word: word.word, onSpeak: widget.onSpeak),
                  if (!_open) ...[
                    const SizedBox(height: 12),
                    Text('Önce aklından söyle', style: text.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!_open)
          FilledButton(
            onPressed: () => setState(() => _open = true),
            child: const Text('Şıkları aç'),
          )
        else if (answered)
          widget.feedback!
        else
          for (final choice in widget.choices)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _Option(
                label: showsMeaning ? choice.word : choice.meaning,
                onTap: () => widget.onPick?.call(choice),
              ),
            ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _TypeAnswer extends StatefulWidget {
  const _TypeAnswer({
    super.key,
    required this.word,
    required this.onSubmit,
    required this.onGiveUp,
  });

  final Word word;
  final ValueChanged<String> onSubmit;
  final VoidCallback onGiveUp;

  @override
  State<_TypeAnswer> createState() => _TypeAnswerState();
}

class _TypeAnswerState extends State<_TypeAnswer> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    if (_input.text.trim().isNotEmpty) widget.onSubmit(_input.text);
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final (before, form, after) = word.exampleParts;
    final hint = '${form.isEmpty ? '' : form[0]}${'_' * max(3, form.length - 1)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _Card(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    word.meaning,
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$before$hint$after',
                    textAlign: TextAlign.center,
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    word.exampleTr,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: 'İngilizcesini yaz',
            filled: true,
            fillColor: colors.surfaceContainer,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.outlineVariant),
            ),
          ),
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(onPressed: widget.onGiveUp, child: const Text('Bilmiyorum')),
            const SizedBox(width: 8),
            Expanded(
              child: ListenableBuilder(
                listenable: _input,
                builder: (context, _) => FilledButton(
                  onPressed: _input.text.trim().isEmpty ? null : _send,
                  child: const Text('Kontrol et'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.verdict,
    required this.wait,
    required this.canOverrule,
    required this.onOverrule,
    required this.onNext,
  });

  final Verdict verdict;
  final String wait;
  final bool canOverrule;
  final VoidCallback onOverrule;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final (base, icon, label) = switch (verdict) {
      Verdict.right => (rightColor, Icons.check_circle, 'Doğru'),
      Verdict.close => (closeColor, Icons.error, 'Neredeyse, bir harf kaçtı'),
      Verdict.wrong => (wrongColor, Icons.cancel, 'Yanlış'),
    };
    // The same hues would be too pale as text on the light background.
    final light = Theme.of(context).brightness == Brightness.light;
    final color = light ? Color.lerp(base, Colors.black, .3)! : base;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '$wait sonra',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        if (canOverrule)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onOverrule,
              child: const Text('Aslında doğruydu'),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(onPressed: onNext, child: const Text('Devam')),
      ],
    );
  }
}

/// The example sentence with the studied word picked out.
class ExampleText extends StatelessWidget {
  const ExampleText({super.key, required this.word});

  final Word word;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (before, form, after) = word.exampleParts;
    return Text.rich(
      TextSpan(
        style: theme.textTheme.titleMedium,
        children: [
          TextSpan(text: before),
          TextSpan(
            text: form,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({required this.done});

  final int done;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Bugünlük tamam',
            textAlign: TextAlign.center,
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '$done kart çalıştın. Kelimeler tam unutmak üzereyken geri gelecek.',
            textAlign: TextAlign.center,
            style: text.bodyLarge,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
}
