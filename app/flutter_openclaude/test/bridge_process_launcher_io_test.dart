import 'package:flutter_openclaude/workbench/bridge_process_launcher.dart';
import 'package:flutter_openclaude/workbench/bridge_process_launcher_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('launch url strategy keeps or switches the managed port', () async {
    await expectLater(
      appBridgeUrlForLaunch(
        preferredBridgeUrl: 'ws://127.0.0.1:58432',
        strategy: BridgeReconnectStrategy.samePort,
      ),
      completion('ws://127.0.0.1:58432'),
    );

    await expectLater(
      appBridgeUrlForLaunch(
        preferredBridgeUrl: 'ws://127.0.0.1:58432',
        strategy: BridgeReconnectStrategy.switchPort,
        choosePort: () async => 58555,
      ),
      completion('ws://127.0.0.1:58555'),
    );
  });

  test('launcher candidates include app-bundled bridge resources', () {
    final candidates = appBridgeLauncherCandidates(
      executableName: 'app-bridge',
      currentDirectory: '/tmp',
      resolvedExecutable:
          '/Applications/MemexForge.app/Contents/MacOS/MemexForge',
    );

    expect(
      candidates,
      contains(
        '/Applications/MemexForge.app/Contents/Resources/openclaude-app/bin/app-bridge',
      ),
    );
  });

  test('agent eval trace directory uses explicit env or app data path', () {
    expect(
      defaultAgentEvalTraceDirectory(
        environment: const {
          'OPENCLAUDE_AGENT_EVAL_TRACE_DIR': '/tmp/openclaude-traces',
          'HOME': '/Users/developer',
        },
      ),
      '/tmp/openclaude-traces',
    );

    final fallback = defaultAgentEvalTraceDirectory(
      environment: const {'HOME': '/Users/developer'},
    );

    expect(fallback, contains('MemexForge'));
    expect(fallback, contains('agent-eval'));
    expect(fallback.startsWith('/'), isTrue);
  });
}
