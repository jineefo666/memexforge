import 'bridge_process_launcher_stub.dart'
    if (dart.library.io) 'bridge_process_launcher_io.dart';

abstract interface class BridgeProcessLauncher {
  bool get canStart;

  Future<BridgeProcessStartResult> start({
    String? preferredBridgeUrl,
    BridgeReconnectStrategy strategy = BridgeReconnectStrategy.samePort,
    bool agentEvalTraceEnabled = false,
  });
}

enum BridgeReconnectStrategy { samePort, switchPort }

final class BridgeProcessStartResult {
  const BridgeProcessStartResult({
    required this.started,
    required this.message,
    this.bridgeUrl,
    this.pid,
  });

  final bool started;
  final String message;
  final String? bridgeUrl;
  final int? pid;
}

BridgeProcessLauncher createDefaultBridgeProcessLauncher() {
  return createPlatformBridgeProcessLauncher();
}
