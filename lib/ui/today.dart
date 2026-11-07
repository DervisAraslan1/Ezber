import 'dart:math';

import 'package:flutter/material.dart';

import '../core/store.dart';
import 'settings.dart';
import 'study.dart';
import 'theme.dart';

const _secondsPerCard = 9;

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final stats = store.stats;
          final counts = store.todayCounts;
          final waiting = counts.reviews + counts.fresh;
          final colors = Theme.of(context).colorScheme;
          final text = Theme.of(context).textTheme;
          final reached = stats.started + stats.known;

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Ezber',
                        style: text.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (stats.streak > 0) ...[
                      const Icon(Icons.local_fire_department,
                          color: flame, size: 22),
                      const SizedBox(width: 2),
                      Text('${stats.streak}',
                          semanticsLabel: '${stats.streak} günlük seri',
                          style: text.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      tooltip: 'Ayarlar',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SettingsScreen(store: store),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _Ring(
                  value: reached / stats.total,
                  lasting: (stats.lasting + stats.known) / stats.total,
                  center: waiting > 0 ? '$waiting' : '✓',
                  caption: waiting > 0 ? 'kelime bekliyor' : 'bugünlük tamam',
                ),
                const SizedBox(height: 16),
                Text(
                  '$reached / ${stats.total} kelimeye ulaştın',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const Spacer(),
                if (store.newWordsPaused) ...[
                  Text(
                    'Tekrarlar birikti. Hafızan yetişsin diye yeni kelimeleri '
                    'bugün kıstım.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                ],
                if (waiting > 0) ...[
                  Text(
                    _summary(counts.reviews, counts.fresh),
                    textAlign: TextAlign.center,
                    style: text.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _study(context),
                    child: const Text('Başla'),
                  ),
                ] else
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      store.addBonusNew(5);
                      _study(context);
                    },
                    child: const Text('5 yeni kelime daha'),
                  ),
              ],
            ),
          );
        },
      );

  String _summary(int reviews, int fresh) {
    final minutes = max(1, ((reviews + fresh * 3) * _secondsPerCard / 60).round());
    final parts = [
      if (reviews > 0) '$reviews tekrar',
      if (fresh > 0) '$fresh yeni',
      'yaklaşık $minutes dk',
    ];
    return parts.join(' · ');
  }

  void _study(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => StudyScreen(store: store),
        ),
      );
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.value,
    required this.lasting,
    required this.center,
    required this.caption,
  });

  final double value;
  final double lasting;
  final String center;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SizedBox.square(
        dimension: 240,
        child: CustomPaint(
          painter: _RingPainter(
            value: value,
            lasting: lasting,
            track: colors.outlineVariant,
            reached: colors.primary.withValues(alpha: .35),
            kept: colors.primary,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(center,
                    style: text.displayLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    )),
                Text(caption,
                    style: text.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.lasting,
    required this.track,
    required this.reached,
    required this.kept,
  });

  final double value;
  final double lasting;
  final Color track;
  final Color reached;
  final Color kept;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 14.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(width / 2);
    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(rect.center, arc.width / 2, stroke(track));
    void sweep(double v, Color c) {
      if (v <= 0) return;
      canvas.drawArc(arc, -pi / 2, 2 * pi * v.clamp(0.0, 1.0), false, stroke(c));
    }

    sweep(value, reached);
    sweep(lasting, kept);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.lasting != lasting ||
      old.track != track ||
      old.kept != kept;
}
