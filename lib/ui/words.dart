import 'dart:async';

import 'package:flutter/material.dart';

import '../core/deck.dart';
import '../core/store.dart';
import 'study.dart';

class WordsScreen extends StatefulWidget {
  const WordsScreen({super.key, required this.store});

  final Store store;

  @override
  State<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends State<WordsScreen> {
  var _query = '';

  bool _matches(Word w) =>
      w.word.contains(_query) || w.meaning.toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    final words =
        _query.isEmpty ? widget.store.words : widget.store.words.where(_matches).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Kelime ara (İngilizce ya da Türkçe)',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainer,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) => ListView.builder(
              itemCount: words.length,
              itemExtent: 64,
              itemBuilder: (context, i) => _Row(store: widget.store, word: words[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.store, required this.word});

  final Store store;
  final Word word;

  @override
  Widget build(BuildContext context) {
    final status = store.statusOf(word);
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(word.word,
          maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(word.meaning, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Semantics(
        label: _statusLabel(status),
        child: Icon(
          switch (status) {
            WordStatus.fresh => Icons.circle_outlined,
            WordStatus.learning => Icons.timelapse,
            WordStatus.lasting => Icons.check_circle,
            WordStatus.known => Icons.done_all,
          },
          size: 20,
          color: status == WordStatus.fresh
              ? colors.outlineVariant
              : colors.primary,
        ),
      ),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _Detail(store: store, word: word),
      ),
    );
  }
}

String _statusLabel(WordStatus status) => switch (status) {
      WordStatus.fresh => 'Henüz sırası gelmedi',
      WordStatus.learning => 'Öğreniliyor',
      WordStatus.lasting => 'Kalıcı',
      WordStatus.known => 'Biliyorum olarak işaretli',
    };

class _Detail extends StatelessWidget {
  const _Detail({required this.store, required this.word});

  final Store store;
  final Word word;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final status = store.statusOf(word);
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(word.word,
                        style: text.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Dinle',
                    icon: const Icon(Icons.volume_up_outlined),
                    onPressed: () => unawaited(store.phone.speak(word.word)),
                  ),
                ],
              ),
              Text(word.meaning,
                  style: text.titleMedium?.copyWith(color: colors.primary)),
              const SizedBox(height: 16),
              ExampleText(word: word),
              const SizedBox(height: 4),
              Text(word.exampleTr,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              Text(
                '#${word.index + 1} · ${_statusLabel(status)}',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              if (status == WordStatus.fresh)
                OutlinedButton(
                  onPressed: () => store.markKnown(word),
                  child: const Text('Bunu zaten biliyorum'),
                )
              else if (status == WordStatus.known)
                OutlinedButton(
                  onPressed: () => store.unmarkKnown(word),
                  child: const Text('Çalışılacaklara geri al'),
                ),
            ],
          ),
        );
      },
    );
  }
}
