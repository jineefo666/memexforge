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

  test('bridge launch environment adds common Node tool locations', () {
    final environment = appBridgeLaunchEnvironment(
      baseEnvironment: const {'PATH': '/usr/bin', 'HOME': '/Users/developer'},
      host: '127.0.0.1',
      port: '58432',
      agentEvalTraceEnabled: true,
      traceDir: '/tmp/memexforge-traces',
    );

    final pathEntries = environment['PATH']!.split(':');

    expect(pathEntries.first, '/usr/bin');
    expect(pathEntries, contains('/opt/homebrew/bin'));
    expect(pathEntries, contains('/usr/local/bin'));
    expect(environment['APP_BRIDGE_HOST'], '127.0.0.1');
    expect(environment['APP_BRIDGE_PORT'], '58432');
    expect(environment['OPENCLAUDE_AGENT_EVAL_TRACE'], '1');
    expect(
      environment['OPENCLAUDE_AGENT_EVAL_TRACE_DIR'],
      '/tmp/memexforge-traces',
    );
  });
}
