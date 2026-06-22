import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openclaude/bridge/bridge_client.dart';
import 'package:flutter_openclaude/bridge/bridge_transport.dart';
import 'package:flutter_openclaude/main.dart';
import 'package:flutter_openclaude/workbench/bridge_process_launcher.dart';
import 'package:flutter_openclaude/workbench/workbench_persistence.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBridgeTransport implements BridgeTransport {
  final incoming = StreamController<String>();

  @override
  Stream<String> get messages => incoming.stream;

  @override
  void send(String message) {}

  @override
  Future<void> close() async => incoming.close();
}

final class FakeBridgeProcessLauncher implements BridgeProcessLauncher {
  final bridgeUrls = <String>[];
  final strategies = <BridgeReconnectStrategy>[];

  @override
  bool get canStart => true;

  @override
  Future<BridgeProcessStartResult> start({
    String? preferredBridgeUrl,
    BridgeReconnectStrategy strategy = BridgeReconnectStrategy.samePort,
    bool agentEvalTraceEnabled = false,
  }) async {
    bridgeUrls.add(preferredBridgeUrl ?? '');
    strategies.add(strategy);
    final bridgeUrl = strategy == BridgeReconnectStrategy.switchPort
        ? 'ws://127.0.0.1:58555'
        : 'ws://127.0.0.1:58432';
    return BridgeProcessStartResult(
      started: true,
      message: 'app-bridge started',
      pid: 42,
      bridgeUrl: bridgeUrl,
    );
  }
}

final class MemoryWorkbenchPersistenceStore
    implements WorkbenchPersistenceStore {
  @override
  Future<Map<String, dynamic>?> load() async => null;

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {}
}

void main() {
  testWidgets('app opens into Agent Workbench shell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      OpenClaudeApp(
        createBridgeClient: (_) => BridgeClient(FakeBridgeTransport()),
      ),
    );

    expect(find.text('MemexForge'), findsWidgets);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('Provider'), findsWidgets);
    expect(
      find.text('You have pushed the button this many times:'),
      findsNothing,
    );
  });

  testWidgets('desktop app can auto-start the local bridge', (tester) async {
    final launcher = FakeBridgeProcessLauncher();
    final createdUrls = <String>[];

    await tester.pumpWidget(
      OpenClaudeApp(
        createBridgeClient: (url) {
          createdUrls.add(url);
          return BridgeClient(FakeBridgeTransport());
        },
        bridgeProcessLauncher: launcher,
        persistenceStore: MemoryWorkbenchPersistenceStore(),
        autoStartBridge: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(launcher.bridgeUrls, ['ws://127.0.0.1:58432']);
    expect(launcher.strategies, [BridgeReconnectStrategy.switchPort]);
    expect(createdUrls, ['ws://127.0.0.1:58555']);
  });
}
