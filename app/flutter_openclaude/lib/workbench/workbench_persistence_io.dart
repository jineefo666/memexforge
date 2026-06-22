import 'dart:convert';
import 'dart:io';

import 'app_branding.dart';
import 'workbench_persistence_store.dart';

WorkbenchPersistenceStore createPlatformWorkbenchPersistenceStore() {
  return FileWorkbenchPersistenceStore();
}

final class FileWorkbenchPersistenceStore implements WorkbenchPersistenceStore {
  FileWorkbenchPersistenceStore({String? filePath})
    : _file = File(filePath ?? _defaultPersistencePath());

  final File _file;

  @override
  Future<Map<String, dynamic>?> load() async {
    if (!await _file.exists()) return null;
    final decoded = jsonDecode(await _file.readAsString());
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot),
    );
  }
}

String _defaultPersistencePath() {
  final home = Platform.environment['HOME'];
  final appData = Platform.environment['APPDATA'];
  final xdgConfigHome = Platform.environment['XDG_CONFIG_HOME'];
  final baseDirectory = switch (true) {
    _ when Platform.isMacOS && home != null =>
      '$home/Library/Application Support/$appStorageName',
    _ when Platform.isWindows && appData != null => '$appData\\$appStorageName',
    _ when xdgConfigHome != null => '$xdgConfigHome/memexforge',
    _ when home != null => '$home/.config/memexforge',
    _ => Directory.current.path,
  };
  return '$baseDirectory${Platform.pathSeparator}workbench-state.json';
}
