import 'dart:async';
import 'dart:convert';

import 'package:flutter_openclaude/bridge/bridge_client.dart';
import 'package:flutter_openclaude/bridge/bridge_transport.dart';
import 'package:flutter_openclaude/workbench/bridge_process_launcher.dart';
import 'package:flutter_openclaude/workbench/workbench_controller.dart';
import 'package:flutter_openclaude/workbench/workbench_models.dart';
import 'package:flutter_openclaude/workbench/workbench_persistence.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBridgeTransport implements BridgeTransport {
  final sent = <String>[];
  final incoming = StreamController<String>();

  @override
  Stream<String> get messages => incoming.stream;

  @override
  void send(String message) => sent.add(message);

  @override
  Future<void> close() async => incoming.close();
}

final class MemoryWorkbenchPersistenceStore
    implements WorkbenchPersistenceStore {
  MemoryWorkbenchPersistenceStore([this.snapshot]);

  Map<String, dynamic>? snapshot;
  var saveCount = 0;

  @override
  Future<Map<String, dynamic>?> load() async => snapshot;

  @override
  Future<void> save(Map<String, dynamic> nextSnapshot) async {
    saveCount += 1;
    snapshot = Map<String, dynamic>.from(nextSnapshot);
  }
}

Future<void> flushBridgeMessages() async {
  for (var i = 0; i < 4; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class FakeBridgeProcessLauncher implements BridgeProcessLauncher {
  FakeBridgeProcessLauncher({this.canStart = true});

  final bridgeUrls = <String>[];
  final strategies = <BridgeReconnectStrategy>[];
  final agentEvalTraceEnabledValues = <bool>[];
  final Completer<BridgeProcessStartResult> _startCompleter = Completer();

  @override
  final bool canStart;

  @override
  Future<BridgeProcessStartResult> start({
    String? preferredBridgeUrl,
    BridgeReconnectStrategy strategy = BridgeReconnectStrategy.samePort,
    bool agentEvalTraceEnabled = false,
  }) {
    bridgeUrls.add(preferredBridgeUrl ?? '');
    strategies.add(strategy);
    agentEvalTraceEnabledValues.add(agentEvalTraceEnabled);
    return _startCompleter.future;
  }

  void complete(BridgeProcessStartResult result) {
    _startCompleter.complete(result);
  }
}

final class FakeDelayedScheduler {
  final delays = <Duration>[];
  final callbacks = <void Function()>[];

  Timer call(Duration delay, void Function() callback) {
    delays.add(delay);
    callbacks.add(callback);
    return Timer(const Duration(days: 1), () {});
  }
}

final class FakeProjectDirectoryPicker {
  FakeProjectDirectoryPicker(this.path);

  String? path;
  var pickCount = 0;

  Future<String?> pickDirectory() async {
    pickCount += 1;
    return path;
  }
}

void main() {
  test('sendMessage without a bridge reports a connection error', () {
    final controller = WorkbenchController(
      initialState: createInitialWorkbenchState(),
    );

    controller.sendMessage('Create the UI');

    expect(controller.state.messages.last.content, 'Create the UI');
    expect(controller.state.isStreaming, isFalse);
    expect(controller.state.connectionStatus, ConnectionStatus.error);
    expect(controller.state.errorMessage, contains('app bridge'));

    controller.dispose();
  });

  test('sendMessage appends user message and sends bridge start', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.sendMessage('Create the UI');

    expect(controller.state.messages.last.content, 'Create the UI');
    expect(controller.state.isStreaming, isTrue);
    expect(transport.sent.single, contains('"type":"start"'));

    controller.dispose();
  });

  test('sendMessage forwards full recent transcript context mode', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
        personal: createInitialWorkbenchState().personal.copyWith(
          fullRecentTranscriptContext: true,
        ),
      ),
    );

    controller.sendMessage('Continue with the earlier game');

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['contextTranscriptMode'], 'full_recent');

    controller.dispose();
  });

  test('sendMessage adds attachment context to the bridge prompt', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.sendMessage(
      'Summarize this',
      attachments: const [
        ChatAttachment(
          id: 'attachment-1',
          name: 'notes.txt',
          mimeType: 'text/plain',
          sizeBytes: 12,
          kind: ChatAttachmentKind.text,
          content: 'Alpha notes',
        ),
      ],
    );

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(controller.state.messages.last.content, 'Summarize this');
    expect(controller.state.messages.last.attachments.single.name, 'notes.txt');
    expect(controller.state.inspector.kind, InspectorKind.context);
    expect(controller.state.retrievedContextItems, hasLength(1));
    expect(controller.state.retrievedContextItems.single.source, 'attachment');
    expect(controller.state.retrievedContextItems.single.title, 'notes.txt');
    expect(
      controller.state.retrievedContextItems.single.content,
      contains('Alpha notes'),
    );
    expect(sent['prompt'], contains('<attachments>'));
    expect(sent['prompt'], contains('notes.txt'));
    expect(sent['prompt'], contains('Alpha notes'));

    controller.dispose();
  });

  test('sendMessage expands enabled slash skill commands for the bridge', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
        extensions: const ExtensionsState(
          skillsStatus: ExtensionInventoryStatus.loaded,
          skills: [
            SkillSummary(
              id: 'debug',
              name: 'debug',
              description: 'Debug a failing workflow.',
              source: 'local',
              status: 'enabled',
            ),
          ],
          mcpStatus: ExtensionInventoryStatus.idle,
          mcpServers: [],
        ),
      ),
    );

    controller.sendMessage('/debug fix the permission flow');

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(
      controller.state.messages.last.content,
      '/debug fix the permission flow',
    );
    expect(sent['prompt'], contains('Use the "debug" skill'));
    expect(sent['prompt'], contains('Debug a failing workflow.'));
    expect(sent['prompt'], contains('fix the permission flow'));

    controller.dispose();
  });

  test('bridge turn timeline messages are stored for diagnostics', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.sendMessage('Check latency');
    transport.incoming.add(
      '{"type":"turn_timeline","requestId":"ui-request-1","stage":"sdk_first_message","status":"completed","at":"2026-06-21T00:00:00.000Z","durationMs":842,"detail":"First SDK message: system."}',
    );
    await flushBridgeMessages();

    expect(controller.state.turnTimeline, hasLength(1));
    expect(controller.state.turnTimeline.single.stage, 'sdk_first_message');
    expect(controller.state.turnTimeline.single.durationMs, 842);
    expect(controller.state.diagnosticLogs.first.title, contains('Timeline'));

    controller.dispose();
  });

  test('assistant result messages store token usage from the SDK', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.sendMessage('Count this turn');
    transport.incoming.add(
      jsonEncode({
        'type': 'sdk_message',
        'requestId': 'ui-request-1',
        'sessionId': 'sdk-session-1',
        'message': {
          'type': 'result',
          'result': 'Done',
          'usage': {
            'input_tokens': 1234,
            'output_tokens': 56,
            'cache_read_input_tokens': 78,
            'cache_creation_input_tokens': 90,
          },
        },
      }),
    );
    await flushBridgeMessages();

    final assistantMessage = controller.state.messages.last;
    expect(assistantMessage.role, MessageRole.assistant);
    expect(assistantMessage.tokenUsage?.inputTokens, 1234);
    expect(assistantMessage.tokenUsage?.outputTokens, 56);
    expect(assistantMessage.tokenUsage?.cacheReadInputTokens, 78);
    expect(assistantMessage.tokenUsage?.cacheCreationInputTokens, 90);

    controller.dispose();
  });

  test(
    'sdk stream events update the assistant message before result',
    () async {
      final transport = FakeBridgeTransport();
      final controller = WorkbenchController(
        bridgeClient: BridgeClient(transport),
        initialState: createInitialWorkbenchState().copyWith(
          connectionStatus: ConnectionStatus.connected,
        ),
      );

      controller.sendMessage('Stream this turn');
      transport.incoming.add(
        jsonEncode({
          'type': 'sdk_message',
          'requestId': 'ui-request-1',
          'sessionId': 'sdk-session-1',
          'message': {
            'type': 'stream_event',
            'event': {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': 'Hel'},
            },
          },
        }),
      );
      await flushBridgeMessages();

      expect(controller.state.messages, hasLength(2));
      expect(controller.state.messages.last.role, MessageRole.assistant);
      expect(controller.state.messages.last.content, 'Hel');
      expect(controller.state.isStreaming, isTrue);

      transport.incoming.add(
        jsonEncode({
          'type': 'sdk_message',
          'requestId': 'ui-request-1',
          'sessionId': 'sdk-session-1',
          'message': {
            'type': 'stream_event',
            'event': {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': 'lo'},
            },
          },
        }),
      );
      await flushBridgeMessages();

      expect(controller.state.messages.last.content, 'Hello');

      transport.incoming.add(
        jsonEncode({
          'type': 'sdk_message',
          'requestId': 'ui-request-1',
          'sessionId': 'sdk-session-1',
          'message': {
            'type': 'result',
            'result': 'Hello',
            'usage': {'input_tokens': 10, 'output_tokens': 2},
          },
        }),
      );
      await flushBridgeMessages();

      final assistantMessages = controller.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .toList();
      expect(assistantMessages, hasLength(1));
      expect(assistantMessages.single.content, 'Hello');
      expect(assistantMessages.single.tokenUsage?.inputTokens, 10);
      expect(assistantMessages.single.tokenUsage?.outputTokens, 2);
      expect(controller.state.isStreaming, isFalse);

      controller.dispose();
    },
  );

  test('sdk text deltas notify listeners for live UI updates', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    controller.sendMessage('Stream this turn');
    notifications = 0;

    transport.incoming.add(
      jsonEncode({
        'type': 'sdk_message',
        'requestId': 'ui-request-1',
        'sessionId': 'sdk-session-1',
        'message': {
          'type': 'stream_event',
          'event': {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'Hel'},
          },
        },
      }),
    );
    await flushBridgeMessages();

    expect(controller.state.messages.last.content, 'Hel');
    expect(notifications, greaterThan(0));

    controller.dispose();
  });

  test(
    'sdk result without stream deltas records a streaming diagnostic',
    () async {
      final transport = FakeBridgeTransport();
      final controller = WorkbenchController(
        bridgeClient: BridgeClient(transport),
        initialState: createInitialWorkbenchState().copyWith(
          connectionStatus: ConnectionStatus.connected,
        ),
      );

      controller.sendMessage('Stream this turn');
      transport.incoming.add(
        jsonEncode({
          'type': 'sdk_message',
          'requestId': 'ui-request-1',
          'sessionId': 'sdk-session-1',
          'message': {'type': 'result', 'result': 'Done all at once'},
        }),
      );
      await flushBridgeMessages();

      expect(controller.state.messages.last.content, 'Done all at once');
      expect(
        controller.state.diagnosticLogs.first.severity,
        DiagnosticSeverity.warning,
      );
      expect(
        controller.state.diagnosticLogs.first.title,
        'No SDK stream events',
      );

      controller.dispose();
    },
  );

  test(
    'thinking-only stream events record a visible streaming diagnostic',
    () async {
      final transport = FakeBridgeTransport();
      final controller = WorkbenchController(
        bridgeClient: BridgeClient(transport),
        initialState: createInitialWorkbenchState().copyWith(
          connectionStatus: ConnectionStatus.connected,
        ),
      );

      controller.sendMessage('Stream reasoning first');
      transport.incoming.add(
        jsonEncode({
          'type': 'sdk_message',
          'requestId': 'ui-request-1',
          'sessionId': 'sdk-session-1',
          'message': {
            'type': 'stream_event',
            'event': {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'thinking_delta', 'thinking': 'Thinking'},
            },
          },
        }),
      );
      await flushBridgeMessages();
      transport.incoming.add(
        jsonEncode({
          'type': 'sdk_message',
          'requestId': 'ui-request-1',
          'sessionId': 'sdk-session-1',
          'message': {'type': 'result', 'result': 'Final answer'},
        }),
      );
      await flushBridgeMessages();

      expect(controller.state.messages.last.content, 'Final answer');
      expect(
        controller.state.diagnosticLogs.first.title,
        'Only thinking deltas streamed',
      );

      controller.dispose();
    },
  );

  test('sendMessage sends prior conversation as retrieval transcript', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
        messages: const [
          ChatMessage(
            id: 'message-1',
            role: MessageRole.user,
            content: '方向是 Agent Workbench 产品化。',
            timestampLabel: 'Earlier',
          ),
          ChatMessage(
            id: 'message-2',
            role: MessageRole.assistant,
            content: '我会按这个方向继续。',
            timestampLabel: 'Earlier',
          ),
        ],
      ),
    );

    controller.sendMessage('上句话是什么');

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'start');
    expect(sent['prompt'], contains('Current workspace directory:'));
    expect(sent['prompt'], contains('上句话是什么'));
    expect(sent['transcript'], [
      {
        'id': 'message-1',
        'role': 'user',
        'content': '方向是 Agent Workbench 产品化。',
      },
      {'id': 'message-2', 'role': 'assistant', 'content': '我会按这个方向继续。'},
    ]);

    controller.dispose();
  });

  test('sendMessage with a disconnected bridge client does not stream', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    controller.sendMessage('Create the UI');

    expect(controller.state.messages.last.content, 'Create the UI');
    expect(controller.state.isStreaming, isFalse);
    expect(controller.state.connectionStatus, ConnectionStatus.error);
    expect(
      controller.state.errorMessage,
      contains('app bridge is not connected'),
    );
    expect(transport.sent, isEmpty);

    controller.dispose();
  });

  test(
    'chooseProjectDirectory opens a different directory as a project session',
    () async {
      final picker = FakeProjectDirectoryPicker('/workspace/mobile-app');
      final store = MemoryWorkbenchPersistenceStore();
      final controller = WorkbenchController(
        initialState: createInitialWorkbenchState().copyWith(
          messages: const [
            ChatMessage(
              id: 'message-1',
              role: MessageRole.user,
              content: 'existing chat',
              timestampLabel: 'Now',
            ),
          ],
        ),
        persistenceStore: store,
        projectDirectoryPicker: picker.pickDirectory,
      );
      final originalSessionId = controller.state.activeSessionId;

      await controller.chooseProjectDirectory();

      expect(picker.pickCount, 1);
      expect(
        controller.state.personal.defaultWorkingDirectory,
        '/workspace/mobile-app',
      );
      expect(controller.state.activeSessionId, isNot(originalSessionId));
      expect(controller.state.activeSession?.title, 'mobile-app');
      expect(controller.state.activeSession?.subtitle, '/workspace/mobile-app');
      expect(controller.state.messages, isEmpty);
      expect(store.saveCount, 1);
      expect(controller.state.diagnosticLogs.first.title, 'Project opened');

      controller.dispose();
    },
  );

  test('chooseProjectDirectory reports unavailable picker results', () async {
    final controller = WorkbenchController(
      initialState: createInitialWorkbenchState(),
      projectDirectoryPicker: () async => null,
    );

    await controller.chooseProjectDirectory();

    expect(controller.state.activeSession?.subtitle, isNotEmpty);
    expect(controller.state.errorMessage, contains('No project directory'));
    expect(
      controller.state.diagnosticLogs.first.title,
      'Project directory not selected',
    );

    controller.dispose();
  });

  test(
    'chooseProjectDirectory keeps the active session for the same project',
    () async {
      final controller = WorkbenchController(
        initialState: createInitialWorkbenchState().copyWith(
          personal: const PersonalSettings(
            displayName: 'Developer',
            defaultWorkingDirectory: '/workspace/mobile-app',
            themePreference: ThemePreference.system,
            fontScale: 1,
            autoConnectBridge: true,
            agentEvalTraceEnabled: false,
          ),
          sessions: const [
            SessionSummary(
              id: 'session-project',
              title: 'mobile-app',
              subtitle: '/workspace/mobile-app',
              status: SessionStatus.idle,
              updatedLabel: 'Now',
              sdkSessionId: 'sdk-openclaude',
            ),
          ],
          activeSessionId: 'session-project',
          messages: const [
            ChatMessage(
              id: 'message-existing',
              role: MessageRole.user,
              content: '继续刚才的俄罗斯方块实现',
              timestampLabel: 'Now',
            ),
          ],
        ),
        projectDirectoryPicker: () async => '/workspace/mobile-app',
      );

      await controller.chooseProjectDirectory();

      expect(controller.state.sessions, hasLength(1));
      expect(controller.state.activeSessionId, 'session-project');
      expect(controller.state.activeSession?.subtitle, '/workspace/mobile-app');
      expect(controller.state.activeSession?.sdkSessionId, 'sdk-openclaude');
      expect(controller.state.messages.single.content, '继续刚才的俄罗斯方块实现');

      controller.dispose();
    },
  );

  test(
    'chooseProjectDirectory keeps existing messages for the selected project',
    () async {
      final controller = WorkbenchController(
        initialState: createInitialWorkbenchState().copyWith(
          personal: const PersonalSettings(
            displayName: 'Developer',
            defaultWorkingDirectory: '/workspace/testclaude',
            themePreference: ThemePreference.system,
            fontScale: 1,
            autoConnectBridge: true,
            agentEvalTraceEnabled: false,
          ),
          sessions: const [
            SessionSummary(
              id: 'session-project',
              title: 'testclaude',
              subtitle: '/workspace/testclaude',
              status: SessionStatus.idle,
              updatedLabel: 'Now',
              sdkSessionId: 'sdk-openclaude',
            ),
          ],
          activeSessionId: 'session-project',
          messages: const [
            ChatMessage(
              id: 'message-old',
              role: MessageRole.assistant,
              content: 'Current directory is /workspace/openclaude.',
              timestampLabel: 'Now',
            ),
          ],
        ),
        projectDirectoryPicker: () async => '/workspace/testclaude',
      );

      await controller.chooseProjectDirectory();

      expect(controller.state.activeSession?.subtitle, '/workspace/testclaude');
      expect(controller.state.activeSession?.sdkSessionId, 'sdk-openclaude');
      expect(controller.state.messages.single.content, contains('openclaude'));

      controller.dispose();
    },
  );

  test(
    'stale sdk messages from a previous request cannot rebind an opened project',
    () async {
      final transport = FakeBridgeTransport();
      final controller = WorkbenchController(
        bridgeClient: BridgeClient(transport),
        initialState: createInitialWorkbenchState().copyWith(
          connectionStatus: ConnectionStatus.connected,
          personal: const PersonalSettings(
            displayName: 'Developer',
            defaultWorkingDirectory: '/workspace/openclaude',
            themePreference: ThemePreference.system,
            fontScale: 1,
            autoConnectBridge: true,
            agentEvalTraceEnabled: false,
          ),
          sessions: const [
            SessionSummary(
              id: 'session-openclaude',
              title: 'openclaude',
              subtitle: '/workspace/openclaude',
              status: SessionStatus.idle,
              updatedLabel: 'Now',
            ),
          ],
          activeSessionId: 'session-openclaude',
        ),
        projectDirectoryPicker: () async => '/workspace/testclaude',
      );

      controller.sendMessage('old project prompt');
      await controller.chooseProjectDirectory();

      transport.incoming.add(
        '{"type":"sdk_message","requestId":"ui-request-1","sessionId":"sdk-openclaude","message":{"type":"result","result":"old response"}}',
      );
      await flushBridgeMessages();

      expect(controller.state.activeSession?.subtitle, '/workspace/testclaude');
      expect(controller.state.activeSession?.sdkSessionId, isNull);
      expect(controller.state.messages, isEmpty);

      controller.sendMessage('current project prompt');
      final start = jsonDecode(transport.sent.last) as Map<String, dynamic>;
      expect(start['cwd'], '/workspace/testclaude');
      expect(start.containsKey('sessionId'), isFalse);

      controller.dispose();
    },
  );

  test(
    'changing the default working directory clears stale sdk session binding',
    () {
      final transport = FakeBridgeTransport();
      final controller = WorkbenchController(
        bridgeClient: BridgeClient(transport),
        initialState: createInitialWorkbenchState().copyWith(
          connectionStatus: ConnectionStatus.connected,
          personal: const PersonalSettings(
            displayName: 'Developer',
            defaultWorkingDirectory: '/workspace/openclaude',
            themePreference: ThemePreference.system,
            fontScale: 1,
            autoConnectBridge: true,
            agentEvalTraceEnabled: false,
          ),
          sessions: const [
            SessionSummary(
              id: 'session-project',
              title: 'openclaude',
              subtitle: '/workspace/openclaude',
              status: SessionStatus.idle,
              updatedLabel: 'Now',
              sdkSessionId: 'sdk-openclaude',
            ),
          ],
          activeSessionId: 'session-project',
        ),
      );

      controller.updatePersonal(
        const PersonalSettings(
          displayName: 'Developer',
          defaultWorkingDirectory: '/workspace/testclaude',
          themePreference: ThemePreference.system,
          fontScale: 1,
          autoConnectBridge: true,
          agentEvalTraceEnabled: false,
        ),
      );
      controller.sendMessage('当前目录是什么');

      final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
      expect(controller.state.activeSession?.subtitle, '/workspace/testclaude');
      expect(controller.state.activeSession?.sdkSessionId, isNull);
      expect(sent['cwd'], '/workspace/testclaude');
      expect(sent.containsKey('sessionId'), isFalse);

      controller.dispose();
    },
  );

  test('new sessions inherit the active project directory', () async {
    final controller = WorkbenchController(
      initialState: createInitialWorkbenchState(),
      projectDirectoryPicker: () async => '/workspace/mobile-app',
    );

    await controller.chooseProjectDirectory();
    controller.newSession();

    expect(controller.state.activeSession?.subtitle, '/workspace/mobile-app');

    controller.dispose();
  });

  test('updating agent eval trace sends runtime bridge toggle', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.updatePersonal(
      controller.state.personal.copyWith(agentEvalTraceEnabled: true),
    );

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'agent_eval_trace_set_enabled');
    expect(sent['enabled'], true);

    controller.dispose();
  });

  test(
    'chooseProjectDirectory avoids duplicate session ids after deletion',
    () async {
      final controller = WorkbenchController(
        initialState: createInitialWorkbenchState().copyWith(
          sessions: const [
            SessionSummary(
              id: 'session-1',
              title: 'One',
              subtitle: '/workspace/one',
              status: SessionStatus.idle,
              updatedLabel: 'Now',
            ),
            SessionSummary(
              id: 'session-3',
              title: 'Three',
              subtitle: '/workspace/three',
              status: SessionStatus.idle,
              updatedLabel: 'Earlier',
            ),
          ],
          activeSessionId: 'session-1',
        ),
        projectDirectoryPicker: () async => '/workspace/four',
      );

      await controller.chooseProjectDirectory();

      expect(controller.state.sessions.map((session) => session.id).toSet(), {
        'session-1',
        'session-3',
        'session-4',
      });

      controller.dispose();
    },
  );

  test(
    'deleteSession removes an inactive session without changing chat state',
    () {
      final controller = WorkbenchController(
        initialState: createInitialWorkbenchState().copyWith(
          sessions: const [
            SessionSummary(
              id: 'session-active',
              title: 'Active',
              subtitle: '/workspace/active',
              status: SessionStatus.idle,
              updatedLabel: 'Now',
            ),
            SessionSummary(
              id: 'session-old',
              title: 'Old',
              subtitle: '/workspace/old',
              status: SessionStatus.idle,
              updatedLabel: 'Earlier',
            ),
          ],
          activeSessionId: 'session-active',
          messages: const [
            ChatMessage(
              id: 'message-1',
              role: MessageRole.user,
              content: 'keep me',
              timestampLabel: 'Now',
            ),
          ],
        ),
      );

      controller.deleteSession('session-old');

      expect(controller.state.sessions.map((session) => session.id), [
        'session-active',
      ]);
      expect(controller.state.activeSessionId, 'session-active');
      expect(controller.state.messages.single.content, 'keep me');

      controller.dispose();
    },
  );

  test(
    'deleteSession selects the next session and clears active chat state',
    () {
      final controller = WorkbenchController(
        initialState: createInitialWorkbenchState().copyWith(
          sessions: const [
            SessionSummary(
              id: 'session-active',
              title: 'Active',
              subtitle: '/workspace/active',
              status: SessionStatus.idle,
              updatedLabel: 'Now',
            ),
            SessionSummary(
              id: 'session-next',
              title: 'Next',
              subtitle: '/workspace/next',
              status: SessionStatus.idle,
              updatedLabel: 'Earlier',
              sdkSessionId: 'sdk-next',
            ),
          ],
          activeSessionId: 'session-active',
          messages: const [
            ChatMessage(
              id: 'message-1',
              role: MessageRole.user,
              content: 'old active chat',
              timestampLabel: 'Now',
            ),
          ],
          toolRuns: const [
            ToolRun(
              id: 'tool-1',
              name: 'Bash',
              command: 'pwd',
              status: ToolRunStatus.running,
              summary: 'Executing',
              details: '{}',
              elapsedLabel: 'Now',
            ),
          ],
        ),
      );

      controller.deleteSession('session-active');

      expect(controller.state.sessions.map((session) => session.id), [
        'session-next',
      ]);
      expect(controller.state.activeSessionId, 'session-next');
      expect(controller.state.activeSession?.sdkSessionId, isNull);
      expect(controller.state.messages, isEmpty);
      expect(controller.state.toolRuns, isEmpty);
      expect(controller.state.destination, WorkbenchDestination.chat);

      controller.dispose();
    },
  );

  test(
    'deleteSession leaves a fresh session when deleting the last session',
    () {
      final controller = WorkbenchController(
        initialState: createInitialWorkbenchState().copyWith(
          sessions: const [
            SessionSummary(
              id: 'session-only',
              title: 'Only',
              subtitle: '/workspace/project',
              status: SessionStatus.idle,
              updatedLabel: 'Now',
            ),
          ],
          activeSessionId: 'session-only',
          messages: const [
            ChatMessage(
              id: 'message-1',
              role: MessageRole.user,
              content: 'remove me',
              timestampLabel: 'Now',
            ),
          ],
        ),
      );

      controller.deleteSession('session-only');

      expect(controller.state.sessions, hasLength(1));
      expect(controller.state.activeSession?.title, 'New chat');
      expect(controller.state.activeSession?.subtitle, '/workspace/project');
      expect(controller.state.messages, isEmpty);

      controller.dispose();
    },
  );

  test(
    'sendMessage sends the current session workspace as bridge cwd',
    () async {
      final transport = FakeBridgeTransport();
      final controller = WorkbenchController(
        bridgeClient: BridgeClient(transport),
        initialState: createInitialWorkbenchState().copyWith(
          connectionStatus: ConnectionStatus.connected,
        ),
        projectDirectoryPicker: () async => '/workspace/mobile-app',
      );

      await controller.chooseProjectDirectory();
      controller.sendMessage('Build a hydration app');

      final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
      expect(sent['type'], 'start');
      expect(sent['cwd'], '/workspace/mobile-app');

      controller.dispose();
    },
  );

  test(
    'sendMessage includes opened project workspace in bridge prompt',
    () async {
      final transport = FakeBridgeTransport();
      final controller = WorkbenchController(
        bridgeClient: BridgeClient(transport),
        initialState: createInitialWorkbenchState().copyWith(
          connectionStatus: ConnectionStatus.connected,
          personal: const PersonalSettings(
            displayName: 'Developer',
            defaultWorkingDirectory: '/workspace/testclaude',
            themePreference: ThemePreference.system,
            fontScale: 1,
            autoConnectBridge: true,
            agentEvalTraceEnabled: false,
          ),
        ),
        projectDirectoryPicker: () async => '/workspace/test1',
      );

      await controller.chooseProjectDirectory();
      controller.sendMessage('当前目录是什么');

      final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
      expect(sent['cwd'], '/workspace/test1');
      expect(sent.containsKey('sessionId'), isFalse);
      expect(sent['prompt'], contains('/workspace/test1'));
      expect(sent['prompt'], isNot(contains('/workspace/testclaude')));

      controller.dispose();
    },
  );

  test(
    'reconnectBridge rebuilds the bridge client from the internal endpoint',
    () async {
      final createdUrls = <String>[];
      final transports = <FakeBridgeTransport>[];
      final initialState = createInitialWorkbenchState().copyWith(
        bridgeUrl: 'ws://127.0.0.1:58435',
        provider: createInitialWorkbenchState().provider.copyWith(
          bridgeUrl: 'ws://127.0.0.1:58435',
        ),
      );
      final controller = WorkbenchController(
        initialState: initialState,
        createBridgeClient: (url) {
          createdUrls.add(url);
          final transport = FakeBridgeTransport();
          transports.add(transport);
          return BridgeClient(transport);
        },
      );

      controller.reconnectBridge();

      expect(createdUrls, ['ws://127.0.0.1:58435']);
      expect(controller.state.connectionStatus, ConnectionStatus.connecting);
      expect(controller.state.bridgeUrl, 'ws://127.0.0.1:58435');
      expect(controller.state.provider.bridgeUrl, 'ws://127.0.0.1:58435');
      expect(
        controller.state.diagnosticLogs.first.severity,
        DiagnosticSeverity.info,
      );
      expect(
        controller.state.diagnosticLogs.first.title,
        'Bridge reconnect started',
      );

      transports.single.incoming.add('{"type":"hello","protocolVersion":1}');
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.connectionStatus, ConnectionStatus.connected);
      expect(controller.state.diagnosticLogs.first.title, 'Bridge connected');

      controller.dispose();
    },
  );

  test('bridge hello loads skills for chat slash commands', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    transport.incoming.add('{"type":"hello","protocolVersion":1}');
    await flushBridgeMessages();

    expect(controller.state.connectionStatus, ConnectionStatus.connected);
    expect(
      controller.state.extensions.skillsStatus,
      ExtensionInventoryStatus.loading,
    );
    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'skills_list');
    expect(sent['includeDisabled'], true);

    controller.dispose();
  });

  test('bridge transport errors are logged with secrets redacted', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    transport.incoming.addError(
      'failed with OPENAI_API_KEY=sk-secret-value and Bearer provider-token',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.connectionStatus, ConnectionStatus.error);
    expect(
      controller.state.diagnosticLogs.first.severity,
      DiagnosticSeverity.error,
    );
    expect(controller.state.diagnosticLogs.first.detail, contains('********'));
    expect(
      controller.state.diagnosticLogs.first.detail,
      isNot(contains('sk-secret-value')),
    );
    expect(
      controller.state.diagnosticLogs.first.detail,
      isNot(contains('provider-token')),
    );

    controller.dispose();
  });

  test('bridge transport errors schedule an automatic reconnect', () async {
    final initialTransport = FakeBridgeTransport();
    final scheduler = FakeDelayedScheduler();
    final createdUrls = <String>[];
    final createdTransports = <FakeBridgeTransport>[];
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(initialTransport),
      createBridgeClient: (url) {
        createdUrls.add(url);
        final transport = FakeBridgeTransport();
        createdTransports.add(transport);
        return BridgeClient(transport);
      },
      scheduleDelayedTask: scheduler.call,
      initialState: createInitialWorkbenchState(),
    );

    initialTransport.incoming.addError('connection failed');
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.connectionStatus, ConnectionStatus.error);
    expect(scheduler.delays, [const Duration(seconds: 1)]);

    scheduler.callbacks.single();

    expect(createdUrls, ['ws://127.0.0.1:58432']);
    expect(controller.state.connectionStatus, ConnectionStatus.connecting);

    createdTransports.single.incoming.add(
      '{"type":"hello","protocolVersion":1}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.connectionStatus, ConnectionStatus.connected);

    controller.dispose();
  });

  test('sendMessage reconnects and sends after bridge hello', () async {
    final createdUrls = <String>[];
    final createdTransports = <FakeBridgeTransport>[];
    final controller = WorkbenchController(
      createBridgeClient: (url) {
        createdUrls.add(url);
        final transport = FakeBridgeTransport();
        createdTransports.add(transport);
        return BridgeClient(transport);
      },
      initialState: createInitialWorkbenchState(),
    );

    controller.sendMessage('Create a hydration app');

    expect(controller.state.messages.last.content, 'Create a hydration app');
    expect(controller.state.connectionStatus, ConnectionStatus.connecting);
    expect(controller.state.isStreaming, isTrue);
    expect(createdUrls, ['ws://127.0.0.1:58432']);
    expect(createdTransports.single.sent, isEmpty);

    createdTransports.single.incoming.add(
      '{"type":"hello","protocolVersion":1}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.connectionStatus, ConnectionStatus.connected);
    final sent =
        jsonDecode(createdTransports.single.sent.single)
            as Map<String, dynamic>;
    expect(sent['type'], 'start');
    expect(sent['prompt'], contains('Current workspace directory:'));
    expect(sent['prompt'], contains('Create a hydration app'));

    controller.dispose();
  });

  test('startLocalBridge launches desktop bridge and reconnects', () async {
    final createdUrls = <String>[];
    final launcher = FakeBridgeProcessLauncher();
    final controller = WorkbenchController(
      initialState: createInitialWorkbenchState(),
      bridgeProcessLauncher: launcher,
      createBridgeClient: (url) {
        createdUrls.add(url);
        return BridgeClient(FakeBridgeTransport());
      },
    );

    final startFuture = controller.startLocalBridge();

    expect(controller.state.bridgeLaunchStatus, BridgeLaunchStatus.starting);
    expect(launcher.bridgeUrls, ['ws://127.0.0.1:58432']);
    expect(launcher.strategies, [BridgeReconnectStrategy.switchPort]);
    expect(launcher.agentEvalTraceEnabledValues, [false]);
    expect(
      controller.state.diagnosticLogs.first.title,
      'Bridge launch started',
    );

    launcher.complete(
      const BridgeProcessStartResult(
        started: true,
        message: 'app-bridge started',
        pid: 1234,
        bridgeUrl: 'ws://127.0.0.1:58555',
      ),
    );
    await startFuture;

    expect(controller.state.bridgeLaunchStatus, BridgeLaunchStatus.started);
    expect(createdUrls, ['ws://127.0.0.1:58555']);
    expect(controller.state.connectionStatus, ConnectionStatus.connecting);
    expect(
      controller.state.diagnosticLogs.map((entry) => entry.title),
      containsAll(['Bridge launched', 'Bridge reconnect started']),
    );

    controller.dispose();
  });

  test('startLocalBridge passes enabled agent eval trace setting', () async {
    final launcher = FakeBridgeProcessLauncher();
    final controller = WorkbenchController(
      initialState: createInitialWorkbenchState().copyWith(
        personal: createInitialWorkbenchState().personal.copyWith(
          agentEvalTraceEnabled: true,
        ),
      ),
      bridgeProcessLauncher: launcher,
      createBridgeClient: (_) => BridgeClient(FakeBridgeTransport()),
    );

    final startFuture = controller.startLocalBridge();

    expect(launcher.agentEvalTraceEnabledValues, [true]);

    launcher.complete(
      const BridgeProcessStartResult(
        started: true,
        message: 'app-bridge started',
        bridgeUrl: 'ws://127.0.0.1:58555',
      ),
    );
    await startFuture;

    controller.dispose();
  });

  test(
    'startLocalBridge reconnects to a launcher-selected bridge port',
    () async {
      final createdUrls = <String>[];
      final launcher = FakeBridgeProcessLauncher();
      final controller = WorkbenchController(
        initialState: createInitialWorkbenchState(),
        bridgeProcessLauncher: launcher,
        createBridgeClient: (url) {
          createdUrls.add(url);
          return BridgeClient(FakeBridgeTransport());
        },
      );

      final startFuture = controller.startLocalBridge(
        strategy: BridgeReconnectStrategy.switchPort,
      );

      expect(launcher.strategies, [BridgeReconnectStrategy.switchPort]);

      launcher.complete(
        const BridgeProcessStartResult(
          started: true,
          message: 'app-bridge started',
          pid: 1234,
          bridgeUrl: 'ws://127.0.0.1:58555',
        ),
      );
      await startFuture;

      expect(controller.state.bridgeUrl, 'ws://127.0.0.1:58555');
      expect(controller.state.provider.bridgeUrl, 'ws://127.0.0.1:58555');
      expect(createdUrls, ['ws://127.0.0.1:58555']);

      controller.dispose();
    },
  );

  test(
    'startLocalBridge reports unsupported launchers without reconnecting',
    () async {
      final createdUrls = <String>[];
      final launcher = FakeBridgeProcessLauncher(canStart: false);
      final controller = WorkbenchController(
        initialState: createInitialWorkbenchState(),
        bridgeProcessLauncher: launcher,
        createBridgeClient: (url) {
          createdUrls.add(url);
          return BridgeClient(FakeBridgeTransport());
        },
      );

      await controller.startLocalBridge();

      expect(
        controller.state.bridgeLaunchStatus,
        BridgeLaunchStatus.unsupported,
      );
      expect(launcher.bridgeUrls, isEmpty);
      expect(createdUrls, isEmpty);
      expect(
        controller.state.diagnosticLogs.first.title,
        'Bridge launch unavailable',
      );

      controller.dispose();
    },
  );

  test('copyDiagnosticsReport copies a redacted diagnostics summary', () async {
    String? copiedText;
    final controller = WorkbenchController(
      copyText: (text) async {
        copiedText = text;
      },
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.error,
        provider: createInitialWorkbenchState().provider.copyWith(
          apiKeyConfigured: true,
        ),
        diagnosticLogs: const [
          DiagnosticLogEntry(
            id: 'diagnostic-1',
            severity: DiagnosticSeverity.error,
            title: 'Provider failed',
            detail: 'OPENAI_API_KEY=sk-secret-value failed',
            timestampLabel: 'Now',
          ),
        ],
      ),
    );

    final report = controller.diagnosticsReport();

    expect(report, contains('MemexForge Diagnostics Report'));
    expect(report, contains('Bridge endpoint: managed internally'));
    expect(report, isNot(contains('Bridge URL:')));
    expect(report, contains('API key: configured'));
    expect(report, contains('Provider failed'));
    expect(report, contains('********'));
    expect(report, isNot(contains('sk-secret-value')));

    await controller.copyDiagnosticsReport();

    expect(copiedText, report);
    expect(
      controller.state.diagnosticsReportCopyStatus,
      DiagnosticsReportCopyStatus.copied,
    );
    expect(
      controller.state.diagnosticLogs.first.title,
      'Diagnostics report copied',
    );

    controller.dispose();
  });

  test('first user message becomes the active session title', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    controller.sendMessage('Build provider settings flow');

    expect(controller.state.messages, hasLength(1));
    expect(
      controller.state.messages.single.content,
      'Build provider settings flow',
    );
    expect(
      controller.state.activeSession?.title,
      'Build provider settings flow',
    );

    controller.dispose();
  });

  test(
    'first turn starts fresh and later turns resume the SDK session',
    () async {
      final transport = FakeBridgeTransport();
      final controller = WorkbenchController(
        bridgeClient: BridgeClient(transport),
        initialState: createInitialWorkbenchState().copyWith(
          connectionStatus: ConnectionStatus.connected,
        ),
      );

      controller.sendMessage('first prompt');
      final firstStart =
          jsonDecode(transport.sent.single) as Map<String, dynamic>;
      expect(firstStart.containsKey('sessionId'), isFalse);

      transport.incoming.add(
        '{"type":"sdk_message","requestId":"ui-request-1","sessionId":"sdk-session-1","message":{"type":"result","result":"first response"}}',
      );
      await flushBridgeMessages();

      controller.sendMessage('second prompt');
      final secondStart =
          jsonDecode(transport.sent.last) as Map<String, dynamic>;
      expect(secondStart['sessionId'], 'sdk-session-1');

      controller.dispose();
    },
  );

  test('new sessions do not inherit the previous SDK session context', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.sendMessage('first prompt');
    transport.incoming.add(
      '{"type":"sdk_message","requestId":"ui-request-1","sessionId":"sdk-session-1","message":{"type":"result","result":"first response"}}',
    );
    await flushBridgeMessages();
    controller.newSession();
    controller.sendMessage('fresh prompt');

    final freshStart = jsonDecode(transport.sent.last) as Map<String, dynamic>;
    expect(freshStart.containsKey('sessionId'), isFalse);
    expect(controller.state.activeSession?.title, 'fresh prompt');

    controller.dispose();
  });

  test(
    'bridge sdk result appends assistant message and stops streaming',
    () async {
      final transport = FakeBridgeTransport();
      final controller = WorkbenchController(
        bridgeClient: BridgeClient(transport),
        initialState: createInitialWorkbenchState().copyWith(
          connectionStatus: ConnectionStatus.connected,
          messages: const [],
        ),
      );

      controller.sendMessage('prompt');
      transport.incoming.add(
        '{"type":"sdk_message","requestId":"ui-request-1","sessionId":"session-1","message":{"type":"result","result":"done"}}',
      );
      await flushBridgeMessages();

      expect(controller.state.messages.last.role, MessageRole.assistant);
      expect(controller.state.messages.last.content, 'done');
      expect(controller.state.isStreaming, isFalse);

      controller.dispose();
    },
  );

  test('assistant result requests learning candidates from transcript', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.sendMessage('I prefer concise answers.');
    transport.incoming.add(
      '{"type":"sdk_message","requestId":"ui-request-1","sessionId":"session-1","message":{"type":"result","result":"Agent Workbench indexes documents into structured context."}}',
    );
    await flushBridgeMessages();

    final learnRequest =
        jsonDecode(transport.sent.last) as Map<String, dynamic>;
    expect(learnRequest['type'], 'context_learn');
    expect(learnRequest['transcript'], [
      {
        'id': 'ui-message-1',
        'role': 'user',
        'content': 'I prefer concise answers.',
      },
      {
        'id': 'ui-message-2',
        'role': 'assistant',
        'content': 'Agent Workbench indexes documents into structured context.',
      },
    ]);

    controller.dispose();
  });

  test('context learn results update learning candidates', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    transport.incoming.add(
      '{"type":"context_learn_result","requestId":"learn-1","result":{"candidates":[{"source":"profile","confidence":0.85,"reason":"Detected an explicit user preference.","evidence":"I prefer concise answers.","fact":{"id":"profile:preference:concise-answers","label":"Preference","content":"User prefers concise answers.","visibility":"workspace","consent":"allowed"}}]}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.learningCandidates, hasLength(1));
    expect(controller.state.learningCandidates.single.source, 'profile');
    expect(
      controller.state.learningCandidates.single.fact['content'],
      'User prefers concise answers.',
    );

    controller.dispose();
  });

  test('accepting a learning candidate sends context fact upsert', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        learningCandidates: const [
          LearningCandidate(
            id: 'profile:preference:concise-answers',
            source: 'profile',
            confidence: 0.85,
            reason: 'Detected an explicit user preference.',
            evidence: 'I prefer concise answers.',
            fact: {
              'id': 'profile:preference:concise-answers',
              'label': 'Preference',
              'content': 'User prefers concise answers.',
              'visibility': 'workspace',
              'consent': 'allowed',
            },
          ),
        ],
      ),
    );

    controller.acceptLearningCandidate('profile:preference:concise-answers');

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'context_fact_upsert');
    expect(sent['cwd'], controller.state.personal.defaultWorkingDirectory);
    expect(sent['source'], 'profile');
    expect(sent['fact']['content'], 'User prefers concise answers.');
    expect(
      controller.state.learningCandidates.single.status,
      LearningCandidateStatus.saving,
    );

    transport.incoming.add(
      '{"type":"context_fact_upsert_result","requestId":"ui-request-1","result":{"source":"profile","id":"profile:preference:concise-answers"}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.state.learningCandidates.single.status,
      LearningCandidateStatus.saved,
    );
    expect(controller.state.memoryFacts, hasLength(1));
    expect(controller.state.memoryFacts.single.source, 'profile');
    expect(controller.state.memoryFacts.single.title, 'Preference');
    expect(
      controller.state.memoryFacts.single.content,
      'User prefers concise answers.',
    );

    controller.dispose();
  });

  test('query errors stop streaming without disconnecting the bridge', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.sendMessage('test');
    transport.incoming.add(
      '{"type":"error","requestId":"req-1","code":"QUERY_FAILED","message":"Provider rejected the request"}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.connectionStatus, ConnectionStatus.connected);
    expect(controller.state.isStreaming, isFalse);
    expect(controller.state.errorMessage, 'Provider rejected the request');

    controller.dispose();
  });

  test('bridge errors are redacted before entering UI state', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.sendMessage('test');
    transport.incoming.add(
      '{"type":"error","requestId":"req-1","code":"QUERY_FAILED","message":"Provider rejected OPENAI_API_KEY=sk-secret-value and Bearer provider-token"}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.errorMessage, isNot(contains('sk-secret-value')));
    expect(controller.state.errorMessage, isNot(contains('provider-token')));
    expect(controller.state.errorMessage, contains('********'));

    controller.dispose();
  });

  test('quota bridge errors use app provider settings guidance', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.sendMessage('test');
    transport.incoming.add(
      '{"type":"error","requestId":"req-1","code":"QUERY_FAILED","message":"API Error: API quota exhausted or not enabled.\\n\\nFix:\\n- Enable billing for your provider\\n- Or switch provider via /provider"}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.errorMessage, contains('API quota exhausted'));
    expect(controller.state.errorMessage, contains('Provider settings'));
    expect(controller.state.errorMessage, isNot(contains('/provider')));

    controller.dispose();
  });

  test('extension runtime updates active chat extensions', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    transport.incoming.add(
      '{"type":"extension_runtime","requestId":"req-1","runtime":{"mcpServers":["filesystem"],"skills":["debug"],"warnings":["MCP server github failed to connect."]}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.activeExtensions.mcpServers, ['filesystem']);
    expect(controller.state.activeExtensions.skills, ['debug']);
    expect(controller.state.activeExtensions.totalCount, 2);
    expect(
      controller.state.activeExtensions.warnings.single,
      contains('github'),
    );
    expect(
      controller.state.diagnosticLogs.first.severity,
      DiagnosticSeverity.warning,
    );
    expect(
      controller.state.diagnosticLogs.first.title,
      'Extension runtime warning',
    );
    expect(controller.state.diagnosticLogs.first.detail, contains('github'));

    controller.dispose();
  });

  test('permission decision sends allow response', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    controller.respondToPermission(
      requestId: 'req-1',
      toolUseId: 'tool-1',
      decision: 'allow',
    );

    expect(transport.sent.single, contains('"permission_response"'));
    expect(transport.sent.single, contains('"allow"'));

    controller.dispose();
  });

  test('permission request sdk messages create pending approvals', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.sendMessage('run git status');
    transport.incoming.add(
      jsonEncode({
        'type': 'sdk_message',
        'requestId': 'ui-request-1',
        'sessionId': 'sdk-session-1',
        'message': {
          'type': 'permission_request',
          'request_id': 'permission-request-1',
          'tool_name': 'Bash',
          'tool_use_id': 'tool-use-1',
          'input': {'command': 'git status'},
          'uuid': 'permission-message-uuid',
          'session_id': 'sdk-session-1',
        },
      }),
    );
    await flushBridgeMessages();

    expect(controller.state.permissionRequests, hasLength(1));
    final request = controller.state.permissionRequests.single;
    expect(request.requestId, 'ui-request-1');
    expect(request.toolUseId, 'tool-use-1');
    expect(request.title, 'Approve Bash');
    expect(request.action, 'git status');
    expect(request.rawPayload, contains('permission-request-1'));
    expect(controller.state.inspector.kind, InspectorKind.permission);
    expect(controller.state.toolRuns, hasLength(1));
    expect(controller.state.toolRuns.single.id, 'tool-use-1');
    expect(controller.state.toolRuns.single.name, 'Bash');
    expect(controller.state.toolRuns.single.command, 'git status');
    expect(controller.state.toolRuns.single.status, ToolRunStatus.pending);

    controller.dispose();
  });

  test('new permission request replaces stale running tool card', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
        toolRuns: const [
          ToolRun(
            id: 'old-tool',
            name: 'Bash',
            command: 'touch old.txt',
            status: ToolRunStatus.running,
            summary: 'Executing approved command',
            details: '{}',
            elapsedLabel: 'Now',
          ),
        ],
      ),
    );

    controller.sendMessage('run next command');
    transport.incoming.add(
      jsonEncode({
        'type': 'sdk_message',
        'requestId': 'ui-request-1',
        'sessionId': 'sdk-session-1',
        'message': {
          'type': 'permission_request',
          'request_id': 'permission-request-2',
          'tool_name': 'Bash',
          'tool_use_id': 'new-tool',
          'input': {'command': 'touch next.txt'},
          'uuid': 'permission-message-uuid-2',
          'session_id': 'sdk-session-1',
        },
      }),
    );
    await flushBridgeMessages();

    expect(controller.state.permissionRequests, hasLength(1));
    expect(controller.state.permissionRequests.single.toolUseId, 'new-tool');
    expect(controller.state.toolRuns, hasLength(1));
    expect(controller.state.toolRuns.single.id, 'new-tool');
    expect(controller.state.toolRuns.single.status, ToolRunStatus.pending);

    controller.dispose();
  });

  test('permission decision removes the pending approval', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        permissionRequests: const [
          PermissionRequest(
            id: 'req-1:tool-1',
            requestId: 'req-1',
            toolUseId: 'tool-1',
            title: 'Approve Bash',
            action: 'git status',
            riskSummary: 'Review this tool request before allowing it.',
            rawPayload: '{}',
          ),
        ],
      ),
    );

    controller.respondToPermission(
      requestId: 'req-1',
      toolUseId: 'tool-1',
      decision: 'allow',
    );

    expect(controller.state.permissionRequests, isEmpty);
    expect(transport.sent.single, contains('"permission_response"'));
    expect(transport.sent.single, contains('"allow"'));

    controller.dispose();
  });

  test(
    'allow all auto-approves future permission requests in active session',
    () async {
      final transport = FakeBridgeTransport();
      final controller = WorkbenchController(
        bridgeClient: BridgeClient(transport),
        initialState: createInitialWorkbenchState().copyWith(
          connectionStatus: ConnectionStatus.connected,
        ),
      );

      controller.sendMessage('run project commands');
      transport.incoming.add(
        jsonEncode({
          'type': 'sdk_message',
          'requestId': 'ui-request-1',
          'sessionId': 'sdk-session-1',
          'message': {
            'type': 'permission_request',
            'request_id': 'permission-request-1',
            'tool_name': 'Bash',
            'tool_use_id': 'tool-use-1',
            'input': {'command': 'git status'},
            'uuid': 'permission-message-uuid-1',
            'session_id': 'sdk-session-1',
          },
        }),
      );
      await flushBridgeMessages();

      expect(controller.state.permissionRequests, hasLength(1));

      controller.respondToPermission(
        requestId: 'ui-request-1',
        toolUseId: 'tool-use-1',
        decision: 'allow_all',
      );

      transport.incoming.add(
        jsonEncode({
          'type': 'sdk_message',
          'requestId': 'ui-request-1',
          'sessionId': 'sdk-session-1',
          'message': {
            'type': 'permission_request',
            'request_id': 'permission-request-2',
            'tool_name': 'Bash',
            'tool_use_id': 'tool-use-2',
            'input': {'command': 'pwd'},
            'uuid': 'permission-message-uuid-2',
            'session_id': 'sdk-session-1',
          },
        }),
      );
      await flushBridgeMessages();

      final permissionResponses = transport.sent
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['type'] == 'permission_response')
          .toList();
      expect(controller.state.permissionRequests, isEmpty);
      expect(permissionResponses, hasLength(2));
      expect(
        (permissionResponses.first['decision']
            as Map<String, dynamic>)['behavior'],
        'allow_all',
      );
      expect(
        (permissionResponses.last['decision']
            as Map<String, dynamic>)['behavior'],
        'allow',
      );

      controller.dispose();
    },
  );

  test('allowing a permission marks the matching tool run as running', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        permissionRequests: const [
          PermissionRequest(
            id: 'req-1:tool-1',
            requestId: 'req-1',
            toolUseId: 'tool-1',
            title: 'Approve Bash',
            action: 'git status',
            riskSummary: 'Review this tool request before allowing it.',
            rawPayload: '{}',
          ),
        ],
        toolRuns: const [
          ToolRun(
            id: 'tool-1',
            name: 'Bash',
            command: 'git status',
            status: ToolRunStatus.pending,
            summary: 'Waiting for permission approval',
            details: '{}',
            elapsedLabel: 'Now',
          ),
        ],
      ),
    );

    controller.respondToPermission(
      requestId: 'req-1',
      toolUseId: 'tool-1',
      decision: 'allow',
    );

    expect(controller.state.permissionRequests, isEmpty);
    expect(controller.state.toolRuns.single.status, ToolRunStatus.running);
    expect(
      controller.state.toolRuns.single.summary,
      'Executing approved command',
    );

    controller.dispose();
  });

  test('denying a permission marks the matching tool run as failed', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        permissionRequests: const [
          PermissionRequest(
            id: 'req-1:tool-1',
            requestId: 'req-1',
            toolUseId: 'tool-1',
            title: 'Approve Bash',
            action: 'git status',
            riskSummary: 'Review this tool request before allowing it.',
            rawPayload: '{}',
          ),
        ],
        toolRuns: const [
          ToolRun(
            id: 'tool-1',
            name: 'Bash',
            command: 'git status',
            status: ToolRunStatus.pending,
            summary: 'Waiting for permission approval',
            details: '{}',
            elapsedLabel: 'Now',
          ),
        ],
      ),
    );

    controller.respondToPermission(
      requestId: 'req-1',
      toolUseId: 'tool-1',
      decision: 'deny',
    );

    expect(controller.state.permissionRequests, isEmpty);
    expect(controller.state.toolRuns.single.status, ToolRunStatus.error);
    expect(controller.state.toolRuns.single.summary, 'Permission denied');

    controller.dispose();
  });

  test('assistant result clears running tool cards', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
        toolRuns: const [
          ToolRun(
            id: 'tool-1',
            name: 'Bash',
            command: 'git status',
            status: ToolRunStatus.running,
            summary: 'Executing approved command',
            details: '{}',
            elapsedLabel: 'Now',
          ),
        ],
      ),
    );

    controller.sendMessage('finish tool');
    transport.incoming.add(
      '{"type":"sdk_message","requestId":"ui-request-1","sessionId":"session-1","message":{"type":"result","result":"done"}}',
    );
    await flushBridgeMessages();

    expect(controller.state.toolRuns, isEmpty);

    controller.dispose();
  });

  test('context retrieval response updates inspector context items', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    transport.incoming.add(
      '{"type":"context_retrieval","requestId":"ctx-1","result":{"items":[{"source":"transcript","title":"Transcript message 1","content":"Provider API key setup was discussed.","score":1}],"attachment":null}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.inspector.kind, InspectorKind.context);
    expect(controller.state.retrievedContextItems, hasLength(1));
    expect(
      controller.state.retrievedContextItems.single.content,
      'Provider API key setup was discussed.',
    );

    controller.dispose();
  });

  test('context retrieval response keeps attachment context visible', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        retrievedContextItems: const [
          RetrievedContextItem(
            source: 'attachment',
            title: 'notes.txt',
            content: 'Text attachment\nPreview:\nAlpha notes',
            score: 1,
          ),
        ],
      ),
    );

    transport.incoming.add(
      '{"type":"context_retrieval","requestId":"ctx-1","result":{"items":[{"source":"transcript","title":"Transcript message 1","content":"Provider API key setup was discussed.","score":1}],"attachment":null}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.retrievedContextItems, hasLength(2));
    expect(controller.state.retrievedContextItems.first.source, 'attachment');
    expect(controller.state.retrievedContextItems.last.source, 'transcript');

    controller.dispose();
  });

  test('retrieval evaluation request updates report metrics', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        retrievedContextItems: const [
          RetrievedContextItem(
            source: 'document',
            title: 'Provider settings',
            content: 'Provider API key setup is documented here.',
            score: 0.9,
          ),
        ],
      ),
    );

    controller.runRetrievalEvaluation();

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'context_eval');
    expect(sent['cwd'], controller.state.personal.defaultWorkingDirectory);
    expect(sent['k'], 5);
    expect(sent['cases'], isNotEmpty);
    expect(
      controller.state.retrievalEvaluation.status,
      RetrievalEvaluationStatus.running,
    );

    transport.incoming.add(
      '{"type":"context_eval_result","requestId":"ui-request-1","result":{"k":5,"hitRate":1,"precisionAtK":0.2,"mrr":1,"sourceCounts":{"document":1},"sourceShare":{"document":1},"cases":[{"name":"Provider settings","query":"Provider settings","retrievedIds":["document:Provider settings"],"relevantIds":["document:Provider settings"],"hit":true,"precisionAtK":0.2,"firstRelevantRank":1,"reciprocalRank":1,"sourceCounts":{"document":1}}]}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.state.retrievalEvaluation.status,
      RetrievalEvaluationStatus.completed,
    );
    expect(controller.state.retrievalEvaluation.report?.hitRate, 1);
    expect(controller.state.retrievalEvaluation.report?.mrr, 1);
    expect(
      controller.state.retrievalEvaluation.report?.cases.single.hit,
      isTrue,
    );

    controller.dispose();
  });

  test(
    'submitApiKey marks provider key as configured without storing the key',
    () {
      final controller = WorkbenchController(
        initialState: createInitialWorkbenchState(),
      );

      controller.submitApiKey('sk-secret-value');

      expect(controller.state.provider.apiKeyConfigured, isTrue);
      expect(controller.state.toString(), isNot(contains('sk-secret-value')));

      controller.dispose();
    },
  );

  test('testProviderConnection associates api key with current route', () {
    final controller = WorkbenchController(
      initialState: createInitialWorkbenchState(),
    );

    controller.testProviderConnection(
      const ProviderConnectionRequest(
        providerName: 'OpenAI Compatible',
        modelName: 'deepseek-v4-flash',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-secret-value',
      ),
    );

    expect(controller.state.provider.apiKeyConfigured, isTrue);
    expect(controller.state.provider.modelName, 'deepseek-v4-flash');
    expect(controller.state.provider.baseUrl, 'https://api.deepseek.com/v1');

    final request = controller.connectionRequestForCurrentProvider();
    expect(request?.apiKey, 'sk-secret-value');
    expect(
      request?.routeKey,
      'OpenAI Compatible::deepseek-v4-flash::https://api.deepseek.com/v1',
    );
    expect(controller.state.toString(), isNot(contains('sk-secret-value')));

    controller.dispose();
  });

  test(
    'restores persisted sessions provider api keys and personal settings',
    () async {
      final store = MemoryWorkbenchPersistenceStore({
        'version': 1,
        'activeSessionId': 'session-api',
        'sessions': [
          {
            'id': 'session-api',
            'title': 'API setup',
            'subtitle': '/workspace/openclaude',
            'status': 'idle',
            'updatedLabel': 'Yesterday',
            'sdkSessionId': 'sdk-session-api',
          },
        ],
        'messages': [
          {
            'id': 'message-1',
            'role': 'user',
            'content': 'Use DeepSeek',
            'timestampLabel': 'Yesterday',
          },
        ],
        'provider': {
          'providerName': 'OpenAI Compatible',
          'modelName': 'deepseek-v4-flash',
          'baseUrl': 'https://api.deepseek.com/v1',
          'bridgeUrl': 'ws://127.0.0.1:58434',
          'apiKeyConfigured': true,
        },
        'apiKeysByRoute': {
          'OpenAI Compatible::deepseek-v4-flash::https://api.deepseek.com/v1':
              'sk-persisted',
        },
        'personal': {
          'displayName': 'Jinee',
          'defaultWorkingDirectory': '/workspace/openclaude',
          'themePreference': 'dark',
          'fontScale': 1.1,
          'autoConnectBridge': false,
        },
        'setupAssistantDismissed': true,
      });
      final controller = WorkbenchController(
        persistenceStore: store,
        initialState: createInitialWorkbenchState(),
      );

      await controller.restorePersistedState();

      expect(controller.state.activeSessionId, 'session-api');
      expect(controller.state.sessions.single.title, 'API setup');
      expect(controller.state.sessions.single.sdkSessionId, isNull);
      expect(controller.state.messages, isEmpty);
      expect(controller.state.provider.modelName, 'deepseek-v4-flash');
      expect(controller.state.personal.displayName, 'Jinee');
      expect(controller.state.personal.themePreference, ThemePreference.dark);
      expect(controller.state.setupAssistantDismissed, isTrue);
      expect(
        controller.connectionRequestForCurrentProvider()?.apiKey,
        'sk-persisted',
      );

      controller.dispose();
    },
  );

  test('restores persisted messages only for the active session', () async {
    final store = MemoryWorkbenchPersistenceStore({
      'version': 1,
      'activeSessionId': 'session-api',
      'messagesSessionId': 'session-api',
      'sessions': [
        {
          'id': 'session-api',
          'title': 'API setup',
          'subtitle': '/workspace/openclaude',
          'status': 'idle',
          'updatedLabel': 'Yesterday',
          'sdkSessionId': 'sdk-session-api',
        },
      ],
      'messages': [
        {
          'id': 'message-1',
          'role': 'assistant',
          'content': 'Use DeepSeek',
          'timestampLabel': 'Yesterday',
          'tokenUsage': {
            'inputTokens': 2000,
            'outputTokens': 300,
            'cacheReadInputTokens': 40,
            'cacheCreationInputTokens': 50,
          },
        },
      ],
    });
    final controller = WorkbenchController(
      persistenceStore: store,
      initialState: createInitialWorkbenchState(),
    );

    await controller.restorePersistedState();

    expect(controller.state.sessions.single.sdkSessionId, isNull);
    expect(controller.state.messages.single.content, 'Use DeepSeek');
    expect(controller.state.messages.single.tokenUsage?.inputTokens, 2000);
    expect(controller.state.messages.single.tokenUsage?.outputTokens, 300);
    expect(
      controller.state.messages.single.tokenUsage?.cacheReadInputTokens,
      40,
    );
    expect(
      controller.state.messages.single.tokenUsage?.cacheCreationInputTokens,
      50,
    );

    controller.dispose();
  });

  test(
    'restores persisted local bridge urls without forcing the default port',
    () async {
      final store = MemoryWorkbenchPersistenceStore({
        'version': 1,
        'activeSessionId': 'session-api',
        'bridgeUrl': 'ws://127.0.0.1:58439',
        'sessions': [
          {
            'id': 'session-api',
            'title': 'API setup',
            'subtitle': '/workspace/openclaude',
            'status': 'idle',
            'updatedLabel': 'Yesterday',
          },
        ],
        'provider': {
          'providerName': 'OpenAI Compatible',
          'modelName': 'deepseek-v4-flash',
          'baseUrl': 'https://api.deepseek.com/v1',
          'bridgeUrl': 'ws://127.0.0.1:58439',
          'apiKeyConfigured': true,
        },
        'personal': {
          'displayName': 'Jinee',
          'defaultWorkingDirectory': '/workspace/openclaude',
          'themePreference': 'dark',
          'fontScale': 1.1,
          'autoConnectBridge': false,
        },
      });
      final controller = WorkbenchController(
        persistenceStore: store,
        initialState: createInitialWorkbenchState(),
      );

      await controller.restorePersistedState();

      expect(controller.state.bridgeUrl, 'ws://127.0.0.1:58439');
      expect(controller.state.provider.bridgeUrl, 'ws://127.0.0.1:58439');

      controller.dispose();
    },
  );

  test('dismissSetupAssistant persists first-run setup preference', () async {
    final store = MemoryWorkbenchPersistenceStore();
    final controller = WorkbenchController(
      persistenceStore: store,
      initialState: createInitialWorkbenchState(),
    );

    controller.dismissSetupAssistant();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.setupAssistantDismissed, isTrue);
    expect(store.snapshot?['setupAssistantDismissed'], isTrue);

    controller.dispose();
  });

  test(
    'saves sessions provider api keys and personal settings locally',
    () async {
      final store = MemoryWorkbenchPersistenceStore();
      final controller = WorkbenchController(
        persistenceStore: store,
        initialState: createInitialWorkbenchState(),
      );

      controller.testProviderConnection(
        const ProviderConnectionRequest(
          providerName: 'OpenAI Compatible',
          modelName: 'deepseek-v4-flash',
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: 'sk-secret-value',
        ),
      );
      controller.updatePersonal(
        controller.state.personal.copyWith(displayName: 'Jinee'),
      );
      controller.sendMessage('Remember this session');
      await Future<void>.delayed(Duration.zero);

      expect(store.saveCount, greaterThanOrEqualTo(3));
      expect(store.snapshot?['provider']['modelName'], 'deepseek-v4-flash');
      expect(store.snapshot?['provider']['bridgeUrl'], 'ws://127.0.0.1:58432');
      expect(store.snapshot?['personal']['displayName'], 'Jinee');
      expect(store.snapshot?['sessions'][0]['title'], 'Remember this session');
      expect(
        store.snapshot?['messagesSessionId'],
        controller.state.activeSessionId,
      );
      expect(
        (store.snapshot?['sessions'][0] as Map<String, dynamic>).containsKey(
          'sdkSessionId',
        ),
        isFalse,
      );
      expect(
        store.snapshot?['messages'][0]['content'],
        'Remember this session',
      );
      expect(
        store
            .snapshot?['apiKeysByRoute']['OpenAI Compatible::deepseek-v4-flash::https://api.deepseek.com/v1'],
        'sk-secret-value',
      );
      expect(store.snapshot.toString(), contains('sk-secret-value'));
      expect(controller.state.toString(), isNot(contains('sk-secret-value')));

      controller.dispose();
    },
  );

  test(
    'persists messages per session across restart and session switching',
    () async {
      final store = MemoryWorkbenchPersistenceStore();
      final controller = WorkbenchController(
        persistenceStore: store,
        initialState: createInitialWorkbenchState(),
      );

      final firstSessionId = controller.state.activeSessionId;
      controller.sendMessage('First session prompt');
      controller.newSession();
      final secondSessionId = controller.state.activeSessionId;
      controller.sendMessage('Second session prompt');
      await Future<void>.delayed(Duration.zero);

      final restoredController = WorkbenchController(
        persistenceStore: store,
        initialState: createInitialWorkbenchState(),
      );
      await restoredController.restorePersistedState();

      expect(restoredController.state.activeSessionId, secondSessionId);
      expect(restoredController.state.sessions.map((session) => session.id), [
        secondSessionId,
        firstSessionId,
      ]);
      expect(
        restoredController.state.messages.single.content,
        'Second session prompt',
      );

      restoredController.selectSession(firstSessionId);

      expect(
        restoredController.state.messages.single.content,
        'First session prompt',
      );

      controller.dispose();
      restoredController.dispose();
    },
  );

  test('sendMessage sends configured provider credentials to bridge', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
      ),
    );

    controller.testProviderConnection(
      const ProviderConnectionRequest(
        providerName: 'OpenAI Compatible',
        modelName: 'deepseek-v4-flash',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-secret-value',
      ),
    );
    controller.sendMessage('Use the configured model');

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'start');
    expect(sent['model'], 'deepseek-v4-flash');
    expect(sent['provider'], {
      'providerName': 'OpenAI Compatible',
      'modelName': 'deepseek-v4-flash',
      'baseUrl': 'https://api.deepseek.com/v1',
      'apiKey': 'sk-secret-value',
    });

    controller.dispose();
  });

  test('sendMessage sends disabled thinking mode when think mode is off', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        connectionStatus: ConnectionStatus.connected,
        personal: createInitialWorkbenchState().personal.copyWith(
          thinkingModeEnabled: false,
        ),
      ),
    );

    controller.sendMessage('Answer without extra reasoning');

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'start');
    expect(sent['thinkingMode'], 'disabled');

    controller.dispose();
  });

  test('indexKnowledgePath sends bridge context index request', () {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    controller.indexKnowledgePath(
      const KnowledgeIndexRequest(
        target: KnowledgeIndexTarget.directory,
        path: 'docs',
      ),
    );

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'context_index');
    expect(sent['cwd'], controller.state.personal.defaultWorkingDirectory);
    expect(sent['target'], 'directory');
    expect(sent['path'], 'docs');
    expect(
      controller.state.knowledgeIndex.status,
      KnowledgeIndexStatus.indexing,
    );
    expect(controller.state.knowledgeIndex.path, 'docs');

    controller.dispose();
  });

  test('context index result updates knowledge index state', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    controller.indexKnowledgePath(
      const KnowledgeIndexRequest(
        target: KnowledgeIndexTarget.directory,
        path: 'docs',
      ),
    );
    transport.incoming.add(
      '{"type":"context_index_result","requestId":"ui-request-1","result":{"target":"directory","path":"docs","indexedNodes":2,"sourcePaths":["docs/provider-guide.md"]}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.state.knowledgeIndex.status,
      KnowledgeIndexStatus.completed,
    );
    expect(controller.state.knowledgeIndex.indexedNodes, 2);
    expect(controller.state.knowledgeIndex.sourcePaths, [
      'docs/provider-guide.md',
    ]);
    expect(controller.state.errorMessage, isNull);

    controller.dispose();
  });

  test('context index errors keep the bridge connected', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    controller.indexKnowledgePath(
      const KnowledgeIndexRequest(
        target: KnowledgeIndexTarget.file,
        path: 'docs/data.json',
      ),
    );
    transport.incoming.add(
      '{"type":"context_index_error","requestId":"ui-request-1","code":"CONTEXT_INDEX_FAILED","message":"Unsupported structured document file"}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.connectionStatus, ConnectionStatus.connected);
    expect(controller.state.knowledgeIndex.status, KnowledgeIndexStatus.failed);
    expect(
      controller.state.knowledgeIndex.errorMessage,
      contains('Unsupported'),
    );

    controller.dispose();
  });

  test('refreshMemoryFacts loads structured memory facts from bridge', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    controller.refreshMemoryFacts();

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'context_facts_list');
    expect(sent['cwd'], controller.state.personal.defaultWorkingDirectory);
    expect(sent['sources'], ['profile', 'habit', 'graph']);

    transport.incoming.add(
      '{"type":"context_facts_list_result","requestId":"ui-request-1","result":{"facts":[{"source":"profile","disabled":false,"fact":{"id":"profile-tone","label":"Preferred tone","content":"User prefers concise answers.","visibility":"workspace","consent":"allowed"}}]}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.memoryFacts, hasLength(1));
    expect(controller.state.memoryFacts.single.source, 'profile');
    expect(controller.state.memoryFacts.single.title, 'Preferred tone');
    expect(controller.state.memoryFacts.single.disabled, isFalse);

    controller.dispose();
  });

  test('selecting extensions loads skills and MCP inventory', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    controller.selectDestination(WorkbenchDestination.extensions);

    expect(controller.state.destination, WorkbenchDestination.extensions);
    expect(
      controller.state.extensions.skillsStatus,
      ExtensionInventoryStatus.loading,
    );
    expect(
      controller.state.extensions.mcpStatus,
      ExtensionInventoryStatus.loading,
    );
    expect(transport.sent.map((message) => jsonDecode(message)['type']), [
      'skills_list',
      'mcp_servers_list',
    ]);

    transport.incoming.add(
      '{"type":"skills_snapshot","requestId":"ui-request-1","skills":[{"id":"debug","name":"debug","description":"Debug a failing workflow.","source":"bundled","status":"enabled"}]}',
    );
    transport.incoming.add(
      '{"type":"mcp_servers_snapshot","requestId":"ui-request-2","servers":[{"id":"filesystem","name":"filesystem","transport":"stdio","scope":"project","enabled":true,"status":"unknown","toolCount":0,"resourceCount":0,"skillCount":0}]}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.state.extensions.skillsStatus,
      ExtensionInventoryStatus.loaded,
    );
    expect(controller.state.extensions.skills.single.name, 'debug');
    expect(
      controller.state.extensions.mcpStatus,
      ExtensionInventoryStatus.loaded,
    );
    expect(controller.state.extensions.mcpServers.single.name, 'filesystem');

    controller.dispose();
  });

  test('skill import enable and refresh send bridge requests', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    controller.importSkill('/tmp/skills/debug');

    var sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'skill_import');
    expect(sent['path'], '/tmp/skills/debug');

    transport.incoming.add(
      '{"type":"skill_imported","requestId":"ui-request-1","skill":{"id":"debug","name":"debug","description":"Debug a failing workflow.","source":"local","status":"enabled","path":"/tmp/skills/debug"}}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.extensions.skills.single.name, 'debug');
    expect(controller.state.extensions.skills.single.status, 'enabled');

    controller.setSkillEnabled('debug', false);
    sent = jsonDecode(transport.sent.last) as Map<String, dynamic>;
    expect(sent['type'], 'skill_set_enabled');
    expect(sent['skillId'], 'debug');
    expect(sent['enabled'], isFalse);

    transport.incoming.add(
      '{"type":"skill_updated","requestId":"ui-request-2","skill":{"id":"debug","name":"debug","description":"Debug a failing workflow.","source":"local","status":"disabled","path":"/tmp/skills/debug"}}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.extensions.skills.single.status, 'disabled');

    controller.refreshSkills();
    sent = jsonDecode(transport.sent.last) as Map<String, dynamic>;
    expect(sent['type'], 'skill_refresh');

    controller.dispose();
  });

  test('MCP server save enable and delete send bridge requests', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    controller.saveMcpServer(
      const McpServerDraft(
        name: 'Filesystem Server',
        transport: 'stdio',
        scope: 'project',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-filesystem'],
        env: {'FILESYSTEM_TOKEN': 'secret'},
        enabled: true,
      ),
    );

    var sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'mcp_server_upsert');
    expect(sent['cwd'], controller.state.personal.defaultWorkingDirectory);
    expect(sent['server']['name'], 'Filesystem Server');
    expect(sent['server']['env'], {'FILESYSTEM_TOKEN': 'secret'});

    transport.incoming.add(
      '{"type":"mcp_server_saved","requestId":"ui-request-1","server":{"id":"filesystem-server","name":"filesystem-server","transport":"stdio","scope":"project","enabled":true,"status":"unknown","toolCount":0,"resourceCount":0,"skillCount":0,"command":"npx","args":["-y","@modelcontextprotocol/server-filesystem"],"env":{"FILESYSTEM_TOKEN":"********"}}}',
    );
    await Future<void>.delayed(Duration.zero);

    sent = jsonDecode(transport.sent.last) as Map<String, dynamic>;
    expect(sent['type'], 'mcp_servers_list');
    expect(sent['cwd'], controller.state.personal.defaultWorkingDirectory);

    transport.incoming.add(
      '{"type":"mcp_servers_snapshot","requestId":"ui-request-2","servers":[{"id":"filesystem-server","name":"filesystem-server","transport":"stdio","scope":"project","enabled":true,"status":"unknown","toolCount":0,"resourceCount":0,"skillCount":0,"command":"npx","args":["-y","@modelcontextprotocol/server-filesystem"],"env":{"FILESYSTEM_TOKEN":"********"}}]}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.extensions.mcpServers.single.command, 'npx');
    expect(controller.state.extensions.mcpServers.single.env, {
      'FILESYSTEM_TOKEN': '********',
    });

    controller.setMcpServerEnabled('filesystem-server', false);
    sent = jsonDecode(transport.sent.last) as Map<String, dynamic>;
    expect(sent['type'], 'mcp_server_set_enabled');
    expect(sent['serverId'], 'filesystem-server');
    expect(sent['enabled'], isFalse);

    controller.deleteMcpServer('filesystem-server');
    sent = jsonDecode(transport.sent.last) as Map<String, dynamic>;
    expect(sent['type'], 'mcp_server_delete');
    expect(sent['serverId'], 'filesystem-server');

    controller.dispose();
  });

  test(
    'MCP server connection test sends bridge request and caches result',
    () async {
      final transport = FakeBridgeTransport();
      final controller = WorkbenchController(
        bridgeClient: BridgeClient(transport),
        initialState: createInitialWorkbenchState().copyWith(
          extensions: const ExtensionsState(
            skillsStatus: ExtensionInventoryStatus.loaded,
            skills: [],
            mcpStatus: ExtensionInventoryStatus.loaded,
            mcpServers: [
              McpServerSummary(
                id: 'filesystem',
                name: 'filesystem',
                transport: 'stdio',
                scope: 'project',
                enabled: true,
                status: 'unknown',
                toolCount: 0,
                resourceCount: 0,
                skillCount: 0,
                command: 'npx',
                args: ['-y', '@modelcontextprotocol/server-filesystem'],
              ),
            ],
          ),
        ),
      );

      controller.testMcpServer(
        const McpServerDraft(
          id: 'filesystem',
          name: 'filesystem',
          transport: 'stdio',
          scope: 'project',
          command: 'npx',
          args: ['-y', '@modelcontextprotocol/server-filesystem'],
          enabled: true,
        ),
      );

      final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
      expect(sent['type'], 'mcp_server_test');
      expect(sent['cwd'], controller.state.personal.defaultWorkingDirectory);
      expect(sent['server']['id'], 'filesystem');
      expect(
        controller.state.extensions.mcpTestResults['filesystem']?.status,
        'testing',
      );

      transport.incoming.add(
        '{"type":"mcp_server_test_result","requestId":"ui-request-1","result":{"serverId":"filesystem","status":"connected","message":"Connected","durationMs":42,"checkedAt":"2026-06-20T00:00:00.000Z","capabilities":{"serverId":"filesystem","tools":[{"name":"read_file","description":"Read a file."}],"resources":[{"name":"file://workspace"}],"prompts":[{"name":"summarize"}],"skills":[]}}}',
      );
      await Future<void>.delayed(Duration.zero);

      final result = controller.state.extensions.mcpTestResults['filesystem'];
      expect(result?.status, 'connected');
      expect(result?.tools.single.name, 'read_file');
      final server = controller.state.extensions.mcpServers.single;
      expect(server.status, 'connected');
      expect(server.toolCount, 1);
      expect(server.resourceCount, 1);

      controller.dispose();
    },
  );

  test('MCP connection test result messages are redacted in UI state', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState(),
    );

    transport.incoming.add(
      '{"type":"mcp_server_test_result","requestId":"ui-request-1","result":{"serverId":"remote","status":"failed","message":"Authorization=Bearer remote-secret-token and apiKey=api-secret-value failed","durationMs":42,"checkedAt":"2026-06-20T00:00:00.000Z","capabilities":{"serverId":"remote","tools":[],"resources":[],"prompts":[],"skills":[]}}}',
    );
    await Future<void>.delayed(Duration.zero);

    final result = controller.state.extensions.mcpTestResults['remote'];
    expect(result?.message, isNot(contains('remote-secret-token')));
    expect(result?.message, isNot(contains('api-secret-value')));
    expect(result?.message, contains('********'));

    controller.dispose();
  });

  test('memory fact edit, disable, and delete send bridge requests', () async {
    final transport = FakeBridgeTransport();
    final controller = WorkbenchController(
      bridgeClient: BridgeClient(transport),
      initialState: createInitialWorkbenchState().copyWith(
        memoryFacts: const [
          MemoryFact(
            source: 'profile',
            id: 'profile-tone',
            title: 'Preferred tone',
            content: 'User prefers concise answers.',
            disabled: false,
            fact: {
              'id': 'profile-tone',
              'label': 'Preferred tone',
              'content': 'User prefers concise answers.',
              'visibility': 'workspace',
              'consent': 'allowed',
            },
          ),
        ],
      ),
    );

    controller.updateMemoryFact(
      'profile',
      'profile-tone',
      title: 'Preferred answer style',
      content: 'User prefers direct answers.',
    );
    var sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'context_fact_upsert');
    expect(sent['source'], 'profile');
    expect(sent['fact']['label'], 'Preferred answer style');
    expect(sent['fact']['content'], 'User prefers direct answers.');

    controller.setMemoryFactDisabled('profile', 'profile-tone', true);
    sent = jsonDecode(transport.sent.last) as Map<String, dynamic>;
    expect(sent['type'], 'context_fact_upsert');
    expect(sent['fact']['metadata']['disabled'], isTrue);

    controller.deleteMemoryFact('profile', 'profile-tone');
    sent = jsonDecode(transport.sent.last) as Map<String, dynamic>;
    expect(sent['type'], 'context_fact_delete');
    expect(sent['source'], 'profile');
    expect(sent['id'], 'profile-tone');

    transport.incoming.add(
      '{"type":"context_fact_delete_result","requestId":"ui-request-3","result":{"source":"profile","id":"profile-tone"}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.memoryFacts, isEmpty);

    controller.dispose();
  });
}
