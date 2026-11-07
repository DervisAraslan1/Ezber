/// Everything that touches the device, so the rest can be tested without one.
abstract class Phone {
  Future<bool> requestNotifications() async => false;
  Future<void> schedule(List<Reminder> reminders) async {}
  Future<void> updateWidget(WidgetData data) async {}
  Future<void> speak(String text) async {}
  Future<void> shareBackup(String contents) async {}
  Future<String?> pickBackup() async => null;
}

class SilentPhone extends Phone {}

class Reminder {
  const Reminder({required this.id, required this.at, required this.body});

  final int id;
  final DateTime at;
  final String body;
}

class WidgetData {
  const WidgetData({
    required this.firstDay,
    required this.forecast,
    required this.streak,
  });

  /// Days since 1970 of the study day [forecast] starts on. The widget picks
  /// its own number from the list, so it stays right on days the app is closed.
  final int firstDay;
  final List<int> forecast;
  final int streak;
}
