import 'dart:math';

import 'package:flutter/material.dart';

import '../core/store.dart';
import 'theme.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final stats = store.stats;
          final retention = stats.retention;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('İlerleme',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Tile(
                    value: '${stats.lasting}',
                    label: 'Kalıcı kelime',
                    hint: 'İki yönde 3+ hafta',
                  ),
                  _Tile(value: '${stats.started}', label: 'Çalışılan kelime'),
                  _Tile(
                    value: '${stats.streak}',
                    label: 'Günlük seri',
                    color: stats.streak > 0 ? flame : null,
                  ),
                  _Tile(
                    value: retention == null
                        ? '–'
                        : '%${(retention * 100).round()}',
                    label: 'Hatırlama',
                    hint: 'Son 30 gün',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Bars(title: 'Son 14 gün', values: stats.lastDays),
              const SizedBox(height: 24),
              _Bars(title: 'Önümüzdeki 7 gün', values: stats.nextDays),
              if (stats.known > 0) ...[
                const SizedBox(height: 16),
                Text('${stats.known} kelimeyi bildiğin için atladın.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          );
        },
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, this.hint, this.color});

  final String value;
  final String label;
  final String? hint;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style: text.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: color)),
          Text(label, maxLines: 1, style: text.bodySmall),
          if (hint != null)
            Text(hint!,
                maxLines: 1,
                style: text.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.title, required this.values});

  final String title;
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final top = max(1, values.reduce(max));
    return Semantics(
      label: '$title: ${values.join(', ')} kart',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('en çok ${values.reduce(max)} kart',
                  style: text.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, value) in values.indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    child: Container(
                      height: max(3, 72 * value / top),
                      decoration: BoxDecoration(
                        color: value == 0
                            ? colors.outlineVariant
                            : colors.primary,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
