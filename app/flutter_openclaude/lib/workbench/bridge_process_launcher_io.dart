import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_branding.dart';
import 'bridge_process_launcher.dart';

BridgeProcessLauncher createPlatformBridgeProcessLauncher() {
  return const DesktopBridgeProcessLauncher();
}

final class DesktopBridgeProcessLauncher implements BridgeProcessLauncher {
  const DesktopBridgeProcessLauncher();

  @override
  bool get canStart => true;

  @override
  Future<BridgeProcessStartResult> start({
    String? preferredBridgeUrl,
    BridgeReconnectStrategy strategy = BridgeReconnectStrategy.samePort,
    bool agentEvalTraceEnabled = false,
  }) async {
    final launcherPath = await _findAppBridgeLauncher();
    if (launcherPath == null) {
      return const BridgeProcessStartResult(
        started: false,
        message:
            'Could not find bin/app-bridge. Start app-bridge manually or run from a packaged app directory.',
      );
    }

    final bridgeUrl = await appBridgeUrlForLaunch(
      preferredBridgeUrl: preferredBridgeUrl,
      strategy: strategy,
    );
    final uri = Uri.parse(bridgeUrl);
    final host = uri.host.isNotEmpty ? uri.host : '127.0.0.1';
    final port = uri.hasPort ? '${uri.port}' : '58432';
    final traceDir = defaultAgentEvalTraceDirectory(
      environment: Platform.environment,
    );
    final environment = appBridgeLaunchEnvironment(
      baseEnvironment: Platform.environment,
      host: host,
      port: port,
      agentEvalTraceEnabled: agentEvalTraceEnabled,
      traceDir: traceDir,
    );
    final process = await Process.start(
      launcherPath,
      const [],
      mode: ProcessStartMode.detachedWithStdio,
      environment: environment,
    );
    return BridgeProcessStartResult(
      started: true,
      message: agentEvalTraceEnabled
          ? 'Started app-bridge on ws://$host:$port. Trace: $traceDir.'
          : 'Started app-bridge on ws://$host:$port.',
      bridgeUrl: 'ws://$host:$port',
      pid: process.pid,
    );
  }
}

@visibleForTesting
Map<String, String> appBridgeLaunchEnvironment({
  required Map<String, String> baseEnvironment,
  required String host,
  required String port,
  required bool agentEvalTraceEnabled,
  required String traceDir,
}) {
  final pathKey = Platform.isWindows && baseEnvironment.containsKey('Path')
      ? 'Path'
      : 'PATH';
  final path = appBridgePathWithNodeToolFallbacks(
    baseEnvironment[pathKey] ??
        baseEnvironment['PATH'] ??
        baseEnvironment['Path'],
  );
  return {
    ...baseEnvironment,
    if (path.isNotEmpty) pathKey: path,
    'APP_BRIDGE_HOST': host,
    'APP_BRIDGE_PORT': port,
    if (agentEvalTraceEnabled) ...{
      'OPENCLAUDE_AGENT_EVAL_TRACE': '1',
      'OPENCLAUDE_AGENT_EVAL_TRACE_DIR': traceDir,
    },
  };
}

@visibleForTesting
String appBridgePathWithNodeToolFallbacks(String? currentPath) {
  final separator = Platform.isWindows ? ';' : ':';
  final fallbacks = Platform.isWindows
      ? const <String>[]
      : const <String>[
          '/opt/homebrew/bin',
          '/usr/local/bin',
          '/usr/bin',
          '/bin',
          '/usr/sbin',
          '/sbin',
        ];
  final entries = <String>[
    ...?currentPath
        ?.split(separator)
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty),
    ...fallbacks,
  ];
  final seen = <String>{};
  return entries.where(seen.add).join(separator);
}

@visibleForTesting
String defaultAgentEvalTraceDirectory({
  required Map<String, String> environment,
}) {
  final explicit = environment['OPENCLAUDE_AGENT_EVAL_TRACE_DIR']?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;

  final home = environment['HOME']?.trim();
  if (Platform.isMacOS && home != null && home.isNotEmpty) {
    return _join([
      home,
      'Library',
      'Application Support',
      appStorageName,
      'agent-eval',
      'traces',
    ]);
  }

  final appData = environment['APPDATA']?.trim();
  if (Platform.isWindows && appData != null && appData.isNotEmpty) {
    return _join([appData, appStorageName, 'agent-eval', 'traces']);
  }

  if (home != null && home.isNotEmpty) {
    return _join([home, '.memexforge', 'agent-eval', 'traces']);
  }

  return _join([
    Directory.systemTemp.path,
    'memexforge',
    'agent-eval',
    'traces',
  ]);
}

@visibleForTesting
Future<String> appBridgeUrlForLaunch({
  required String? preferredBridgeUrl,
  required BridgeReconnectStrategy strategy,
  Future<int> Function()? choosePort,
}) async {
  final uri = Uri.tryParse(preferredBridgeUrl ?? '');
  final host = uri?.host.isNotEmpty == true ? uri!.host : '127.0.0.1';
  if (strategy == BridgeReconnectStrategy.samePort) {
    final port = uri?.hasPort == true ? uri!.port : 58432;
    return 'ws://$host:$port';
  }
  final port = await (choosePort ?? _chooseAvailableLoopbackPort)();
  return 'ws://$host:$port';
}

Future<int> _chooseAvailableLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<String?> _findAppBridgeLauncher() async {
  final executableName = Platform.isWindows ? 'app-bridge.cmd' : 'app-bridge';
  final candidates = appBridgeLauncherCandidates(
    executableName: executableName,
    currentDirectory: Directory.current.path,
    resolvedExecutable: Platform.resolvedExecutable,
    explicit: Platform.environment['OPENCLAUDE_APP_BRIDGE'],
  );

  for (final candidate in candidates) {
    if (await File(candidate).exists()) return candidate;
  }
  return null;
}

@visibleForTesting
List<String> appBridgeLauncherCandidates({
  required String executableName,
  required String currentDirectory,
  required String resolvedExecutable,
  String? explicit,
}) {
  final executableDirectory = File(resolvedExecutable).parent;
  final contentsDirectory = executableDirectory.parent;
  return [
    if (explicit != null && explicit.trim().isNotEmpty) explicit.trim(),
    _join([
      contentsDirectory.path,
      'Resources',
      'openclaude-app',
      'bin',
      executableName,
    ]),
    _join([currentDirectory, 'bin', executableName]),
    _join([currentDirectory, 'dist', 'openclaude-app', 'bin', executableName]),
    ..._ancestorCandidates(executableDirectory, executableName),
  ];
}

Iterable<String> _ancestorCandidates(
  Directory start,
  String executableName,
) sync* {
  var directory = start;
  for (var depth = 0; depth < 8; depth++) {
    yield _join([directory.path, 'bin', executableName]);
    final parent = directory.parent;
    if (parent.path == directory.path) return;
    directory = parent;
  }
}

String _join(List<String> parts) {
  return parts.where((part) => part.isNotEmpty).join(Platform.pathSeparator);
}
