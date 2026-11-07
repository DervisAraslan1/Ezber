import 'package:flutter/material.dart';

import '../core/store.dart';

const _newOptions = [5, 10, 15, 20, 30];
const _skipOptions = [100, 300, 500, 1000];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ayarlar')),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final s = store.settings;
            final hour = s.reminderMinute ~/ 60;
            final minute = s.reminderMinute % 60;
            final time = TimeOfDay(hour: hour, minute: minute);
            return ListView(
              children: [
                ListTile(
                  title: const Text('Günlük yeni kelime'),
                  subtitle: Text(_pace(s.newPerDay, store.words.length)),
                  trailing: DropdownButton<int>(
                    value: s.newPerDay,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final n in _newOptions)
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (n) =>
                        store.updateSettings((x) => x.newPerDay = n!),
                  ),
                ),
                ListTile(
                  title: const Text('Sık kelimeleri atla'),
                  subtitle: const Text('Temelin varsa en sık kelimeleri geç'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _chooseSkip(context),
                ),
                SwitchListTile(
                  title: const Text('Kelimeleri otomatik oku'),
                  value: s.autoSpeak,
                  onChanged: (v) => store.updateSettings((x) => x.autoSpeak = v),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Günlük hatırlatma'),
                  value: s.reminder,
                  onChanged: (v) async {
                    if (v) await store.phone.requestNotifications();
                    store.updateSettings((x) => x.reminder = v);
                  },
                ),
                ListTile(
                  enabled: s.reminder,
                  title: const Text('Hatırlatma saati'),
                  trailing: Text(time.format(context)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: time,
                    );
                    if (picked != null) {
                      store.updateSettings((x) => x.reminderMinute =
                          picked.hour * 60 + picked.minute);
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  title: const Text('Yedeği paylaş'),
                  subtitle: const Text(
                      'Telefon değişirse ilerlemen bu dosyayla taşınır'),
                  trailing: const Icon(Icons.ios_share),
                  onTap: () async {
                    await store.flush();
                    await store.phone.shareBackup(store.export());
                  },
                ),
                ListTile(
                  title: const Text('Yedekten yükle'),
                  subtitle: const Text('Buradaki ilerlemenin yerine geçer'),
                  trailing: const Icon(Icons.restore),
                  onTap: () => _restore(context),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Kaynaklar'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _credits(context),
                ),
              ],
            );
          },
        ),
      );

  String _pace(int perDay, int total) {
    final days = total / perDay;
    if (days < 60) return 'Tamamı yaklaşık ${days.round()} gün';
    return 'Tamamı yaklaşık ${(days / 30).round()} ay';
  }

  Future<void> _chooseSkip(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final count = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Kaç kelimeyi atlayalım?'),
        children: [
          for (final n in _skipOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(n),
              child: Text('En sık $n kelime'),
            ),
        ],
      ),
    );
    if (count == null) return;
    store.skipFirst(count);
    messenger.showSnackBar(SnackBar(
      content: Text(
          'En sık $count kelime atlandı. Kelimeler sekmesinden geri alabilirsin.'),
    ));
  }

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yedekten yüklensin mi?'),
        content: const Text('Bu telefondaki ilerlemenin yerine geçer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yükle'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    String? contents;
    try {
      contents = await store.phone.pickBackup();
    } on Object {
      messenger.showSnackBar(const SnackBar(
        content: Text('Dosya okunamadı, ilerlemen değişmedi.'),
      ));
      return;
    }
    if (contents == null) return;
    final ok = await store.import(contents);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Yedek yüklendi.'
          : 'Bu dosya Ezber yedeği değil, ilerlemen değişmedi.'),
    ));
  }

  void _credits(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Kaynaklar'),
          content: const SingleChildScrollView(
            child: Text(
              'Kelime listesi: New General Service List 1.2, Browne, Culligan '
              've Phillips, CC BY-SA 4.0.\n\n'
              'Örnek cümleler: Tatoeba (tatoeba.org), CC BY 2.0 FR. Cümleleri '
              'gönüllüler çevirir, nadiren serbest çeviri çıkabilir.\n\n'
              'Türkçe anlamlar ve bir kısım cümle bu uygulama için yazıldı.\n\n'
              'Tekrar zamanlaması: FSRS-5.\n\n'
              'Yazı tipi: Manrope, SIL Open Font License.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
}
