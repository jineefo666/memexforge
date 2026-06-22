import 'bridge_process_launcher.dart';

BridgeProcessLauncher createPlatformBridgeProcessLauncher() {
  return const UnsupportedBridgeProcessLauncher();
}

final class UnsupportedBridgeProcessLauncher implements BridgeProcessLauncher {
  const UnsupportedBridgeProcessLauncher();

  @override
  bool get canStart => false;

  @override
  Future<BridgeProcessStartResult> start({
    String? preferredBridgeUrl,
    BridgeReconnectStrategy strategy = BridgeReconnectStrategy.samePort,
    bool agentEvalTraceEnabled = false,
  }) async {
    return const BridgeProcessStartResult(
      started: false,
      message: 'Local app-bridge launch is available only in desktop builds.',
    );
  }
}
