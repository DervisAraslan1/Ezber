import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/timezone.dart' as tz;

import 'phone.dart';

const _widgetProvider = 'dev.ezber.ezber.EzberWidgetProvider';

const _details = NotificationDetails(
  android: AndroidNotificationDetails(
    'ezber_hatirlatma',
    'Günlük hatırlatma',
    channelDescription: 'Günün kelimeleri hazır olduğunda haber verir',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    icon: 'ic_notification',
  ),
);

class AndroidPhone extends Phone {
  final _notifications = FlutterLocalNotificationsPlugin();
  final _tts = FlutterTts();

  Future<void> init() async {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.42);
  }

  @override
  Future<bool> requestNotifications() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Times are absolute instants, so no time zone database is needed. Inexact
  /// delivery needs no alarm permission and is fine for a daily nudge.
  @override
  Future<void> schedule(List<Reminder> reminders) async {
    await _notifications.cancelAllPendingNotifications();
    for (final item in reminders) {
      await _notifications.zonedSchedule(
        id: item.id,
        title: 'Ezber vakti',
        body: item.body,
        scheduledDate: tz.TZDateTime.from(item.at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> updateWidget(WidgetData data) async {
    await Future.wait([
      HomeWidget.saveWidgetData('firstDay', data.firstDay),
      HomeWidget.saveWidgetData('forecast', data.forecast.join(',')),
      HomeWidget.saveWidgetData('streak', data.streak),
    ]);
    await HomeWidget.updateWidget(qualifiedAndroidName: _widgetProvider);
  }

  @override
  Future<void> speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  Future<void> shareBackup(String contents) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/ezber-yedek.json');
    await file.writeAsString(contents, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  @override
  Future<String?> pickBackup() async {
    final picked = await FilePicker.pickFile();
    return picked == null ? null : utf8.decode(await picked.readAsBytes());
  }
}
