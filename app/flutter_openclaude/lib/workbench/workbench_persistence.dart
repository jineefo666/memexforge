import 'workbench_persistence_platform_stub.dart'
    if (dart.library.html) 'workbench_persistence_web.dart'
    if (dart.library.io) 'workbench_persistence_io.dart';
import 'workbench_persistence_store.dart';

export 'workbench_persistence_store.dart';

WorkbenchPersistenceStore createDefaultWorkbenchPersistenceStore() {
  return createPlatformWorkbenchPersistenceStore();
}
