import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/android_phone.dart';
import 'core/deck.dart';
import 'core/file_persistence.dart';
import 'core/store.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final words = parseDeck(await rootBundle.loadString('assets/deck.json'));
  final phone = AndroidPhone();
  final store = Store(words: words, persistence: FilePersistence(), phone: phone);
  await store.load();
  // Reminders and speech are extras: study must open even if they cannot start.
  try {
    await phone.init();
  } catch (error) {
    debugPrint('Telefon özellikleri başlatılamadı: $error');
  }
  runApp(EzberApp(store: store));
}
