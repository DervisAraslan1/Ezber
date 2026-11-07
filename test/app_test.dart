import 'dart:io';

import 'package:ezber/core/deck.dart';
import 'package:ezber/core/fsrs.dart';
import 'package:ezber/core/phone.dart';
import 'package:ezber/core/store.dart';
import 'package:ezber/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'store_test.dart' show MemoryPersistence, makeWords;

class SpeechPhone extends Phone {
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);
}

void main() {
  late Store store;
  late SpeechPhone phone;

  setUp(() {
    phone = SpeechPhone();
    store = Store(
      words: makeWords(30),
      persistence: MemoryPersistence(),
      phone: phone,
    );
  });

  testWidgets('a new word is shown, then asked, and the app grades it',
      (tester) async {
    var time = DateTime(2026, 11, 7, 12);
    store = Store(
      words: makeWords(30),
      persistence: MemoryPersistence(),
      phone: phone,
      clock: () => time,
    );
    store.updateSettings((s) => s.newPerDay = 1);
    await tester.pumpWidget(EzberApp(store: store));

    await tester.tap(find.text('Başla'));
    await tester.pumpAndSettle();
    expect(find.text('YENİ KELİME'), findsOneWidget);
    expect(find.text('kelime0'), findsOneWidget);
    expect(phone.spoken, ['word0']);

    await tester.tap(find.text('Devam'));
    time = time.add(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(find.text('YENİ KELİME'), findsNothing);
    expect(find.text('Devam'), findsNothing);

    await tester.tap(find.text('kelime0'));
    await tester.pumpAndSettle();
    expect(find.text('Doğru'), findsOneWidget);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    await store.flush();
  });

  testWidgets('a wrong choice is called wrong and shows the answer',
      (tester) async {
    var time = DateTime(2026, 11, 7, 12);
    store = Store(
      words: makeWords(30),
      persistence: MemoryPersistence(),
      phone: phone,
      clock: () => time,
    );
    store.introduce(store.next()!);
    time = time.add(const Duration(minutes: 2));
    await tester.pumpWidget(EzberApp(store: store));
    await tester.tap(find.text('Başla'));
    await tester.pumpAndSettle();

    final card = store.next()!;
    final wrong = store.choicesFor(card).firstWhere((w) => w.index != 0);
    await tester.tap(find.text(wrong.meaning));
    await tester.pumpAndSettle();
    expect(find.text('Yanlış'), findsOneWidget);
    expect(find.text('kelime0'), findsOneWidget);
    await store.flush();
  });

  testWidgets('writing the word: hidden sound, checked answer, overrule',
      (tester) async {
    var time = DateTime(2026, 11, 7, 12);
    store = Store(
      words: makeWords(1),
      persistence: MemoryPersistence(),
      phone: phone,
      clock: () => time,
    );
    final word = store.words.first;
    store.answer(store.next()!, Rating.easy);
    time = time.add(const Duration(days: 40));
    store.answer(store.next()!, Rating.easy);
    time = time.add(const Duration(days: 1));
    store.answer(store.next()!, Rating.good);
    time = time.add(const Duration(minutes: 2));

    await tester.pumpWidget(EzberApp(store: store));
    await tester.tap(find.text('Başla'));
    await tester.pumpAndSettle();
    expect(find.text(word.word), findsNothing);
    expect(phone.spoken, isEmpty);

    await tester.enterText(find.byType(TextField), 'yanlis');
    await tester.pump();
    await tester.tap(find.text('Kontrol et'));
    await tester.pumpAndSettle();
    expect(find.text('Yanlış'), findsOneWidget);
    expect(find.text(word.word), findsOneWidget);
    expect(phone.spoken, [word.word]);

    await tester.tap(find.text('Aslında doğruydu'));
    await tester.pumpAndSettle();
    expect(find.text('Doğru'), findsOneWidget);
    await store.flush();
  });

  testWidgets('every step fits a narrow phone with big text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    var time = DateTime(2026, 11, 7, 12);
    store = Store(
      words: makeWords(30),
      persistence: MemoryPersistence(),
      phone: phone,
      clock: () => time,
    );
    await tester.pumpWidget(EzberApp(store: store));
    await tester.tap(find.text('Başla'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Devam'));
    time = time.add(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await store.flush();
  });

  test('the shipped deck is complete', () {
    final words = parseDeck(File('assets/deck.json').readAsStringSync());
    expect(words.length, greaterThanOrEqualTo(2800));
    for (final word in words) {
      expect(word.meaning, isNotEmpty, reason: word.word);
      expect(word.example, isNotEmpty, reason: word.word);
      expect(word.exampleTr, isNotEmpty, reason: word.word);
      expect(word.exampleParts.$2, isNotEmpty, reason: word.word);
    }
    expect(words.map((w) => w.word).toSet().length, words.length);
  });
}
