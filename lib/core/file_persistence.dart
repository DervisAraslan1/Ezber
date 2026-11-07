import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'store.dart';

class FilePersistence implements Persistence {
  Future<File> _file(String name) async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$name');
  }

  @override
  Future<String?> read() async {
    final file = await _file('ezber.json');
    return await file.exists() ? file.readAsString() : null;
  }

  /// Writes beside the target and renames over it: a crash or a dead battery
  /// mid-save leaves the previous file whole.
  @override
  Future<void> write(String contents) async {
    final temp = await _file('ezber.json.tmp');
    final target = await _file('ezber.json');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(target.path);
  }

  @override
  Future<void> quarantine(String contents) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = await _file('ezber.bozuk.$stamp.json');
    await file.writeAsString(contents, flush: true);
  }
}
