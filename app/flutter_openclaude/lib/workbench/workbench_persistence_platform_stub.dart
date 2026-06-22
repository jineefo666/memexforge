import 'workbench_persistence_store.dart';

WorkbenchPersistenceStore createPlatformWorkbenchPersistenceStore() {
  return const NoopWorkbenchPersistenceStore();
}

final class NoopWorkbenchPersistenceStore implements WorkbenchPersistenceStore {
  const NoopWorkbenchPersistenceStore();

  @override
  Future<Map<String, dynamic>?> load() async => null;

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {}
}
