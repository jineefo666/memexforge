import 'package:flutter_openclaude/workbench/workbench_models.dart';
import 'package:flutter_openclaude/workbench/workbench_persistence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial state has professional default app state', () {
    final state = createInitialWorkbenchState();

    expect(state.connectionStatus, ConnectionStatus.disconnected);
    expect(state.destination, WorkbenchDestination.chat);
    expect(state.sessions, isNotEmpty);
    expect(state.activeSessionId, state.sessions.first.id);
    expect(state.provider.providerName, isNotEmpty);
    expect(state.provider.modelName, 'gpt-5.5');
    expect(state.provider.baseUrl, 'https://api.openai.com/v1');
    expect(state.personal.displayName, isNotEmpty);
    expect(state.personal.thinkingModeEnabled, isTrue);
    expect(state.sessions.single.title, 'New chat');
    expect(
      state.personal.defaultWorkingDirectory,
      isNot(contains('/IdeaProjects/openclaude')),
    );
    expect(
      state.sessions.single.subtitle,
      state.personal.defaultWorkingDirectory,
    );
    expect(state.messages, isEmpty);
    expect(state.toolRuns, isEmpty);
  });

  test('copyWith updates only selected fields', () {
    final state = createInitialWorkbenchState();
    final updated = state.copyWith(
      connectionStatus: ConnectionStatus.connected,
      destination: WorkbenchDestination.providers,
    );

    expect(updated.connectionStatus, ConnectionStatus.connected);
    expect(updated.destination, WorkbenchDestination.providers);
    expect(updated.sessions, state.sessions);
    expect(updated.provider, state.provider);
    expect(updated.personal, state.personal);
  });

  test('session search filters sessions by title and subtitle', () {
    final state = createInitialWorkbenchState().copyWith(
      sessionSearchQuery: 'api',
      sessions: const [
        SessionSummary(
          id: 'session-1',
          title: 'API key setup',
          subtitle: '/workspace/openclaude',
          status: SessionStatus.idle,
          updatedLabel: 'Now',
        ),
        SessionSummary(
          id: 'session-2',
          title: 'Context retrieval',
          subtitle: '/workspace/docs',
          status: SessionStatus.idle,
          updatedLabel: 'Earlier',
        ),
      ],
    );

    expect(state.filteredSessions, hasLength(1));
    expect(state.filteredSessions.single.id, 'session-1');
  });

  test('settings copyWith keeps unchanged values', () {
    final state = createInitialWorkbenchState();

    final provider = state.provider.copyWith(modelName: 'gpt-5.5-pro');
    final personal = state.personal.copyWith(displayName: 'Jinee');

    expect(provider.modelName, 'gpt-5.5-pro');
    expect(provider.providerName, state.provider.providerName);
    expect(personal.displayName, 'Jinee');
    expect(
      personal.defaultWorkingDirectory,
      state.personal.defaultWorkingDirectory,
    );
  });

  test('persisted personal settings preserve thinking mode', () {
    final state = createInitialWorkbenchState().copyWith(
      personal: createInitialWorkbenchState().personal.copyWith(
        thinkingModeEnabled: false,
      ),
    );

    final snapshot = encodePersistedWorkbenchState(
      state: state,
      apiKeysByRoute: const {},
    );
    final restored = decodePersistedWorkbenchState(
      snapshot: snapshot,
      fallback: createInitialWorkbenchState(),
    );

    expect(restored.personal.thinkingModeEnabled, isFalse);
  });

  test('persisted messages preserve attachment metadata', () {
    final state = createInitialWorkbenchState().copyWith(
      messages: const [
        ChatMessage(
          id: 'message-1',
          role: MessageRole.user,
          content: 'Use this file',
          timestampLabel: 'Now',
          attachments: [
            ChatAttachment(
              id: 'attachment-1',
              name: 'notes.txt',
              mimeType: 'text/plain',
              sizeBytes: 24,
              kind: ChatAttachmentKind.text,
              path: '/tmp/notes.txt',
              content: 'Saved notes',
            ),
          ],
        ),
      ],
    );

    final snapshot = encodePersistedWorkbenchState(
      state: state,
      apiKeysByRoute: const {},
    );
    final restored = decodePersistedWorkbenchState(
      snapshot: snapshot,
      fallback: createInitialWorkbenchState(),
    );

    final attachment = restored.messages.single.attachments.single;
    expect(attachment.name, 'notes.txt');
    expect(attachment.kind, ChatAttachmentKind.text);
    expect(attachment.content, 'Saved notes');
  });

  test('debug output does not expose MCP secret values', () {
    final state = createInitialWorkbenchState().copyWith(
      extensions: const ExtensionsState(
        skillsStatus: ExtensionInventoryStatus.loaded,
        skills: [],
        mcpStatus: ExtensionInventoryStatus.loaded,
        mcpServers: [
          McpServerSummary(
            id: 'remote',
            name: 'remote',
            transport: 'streamable_http',
            scope: 'project',
            enabled: true,
            status: 'failed',
            toolCount: 0,
            resourceCount: 0,
            skillCount: 0,
            headers: {'Authorization': '********'},
            env: {'API_TOKEN': '********'},
            lastError: 'Authorization=Bearer ******** failed',
          ),
        ],
        mcpTestResults: {
          'remote': McpConnectionTestResult(
            serverId: 'remote',
            status: 'failed',
            message: 'Authorization=Bearer ******** failed',
            durationMs: 1,
            checkedAt: '2026-06-20T00:00:00.000Z',
          ),
        },
      ),
    );

    expect(state.toString(), isNot(contains('remote-secret-token')));
    expect(state.toString(), isNot(contains('api-secret-value')));
  });
}
