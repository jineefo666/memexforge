import 'dart:convert';

import 'package:web/web.dart' as web;

import 'workbench_persistence_store.dart';

const _storageKey = 'openclaude.workbench.state.v1';

WorkbenchPersistenceStore createPlatformWorkbenchPersistenceStore() {
  return const BrowserWorkbenchPersistenceStore();
}

final class BrowserWorkbenchPersistenceStore
    implements WorkbenchPersistenceStore {
  const BrowserWorkbenchPersistenceStore();

  @override
  Future<Map<String, dynamic>?> load() async {
    final raw = web.window.localStorage.getItem(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    web.window.localStorage.setItem(_storageKey, jsonEncode(snapshot));
  }
}
