import 'package:flutter/material.dart';
import 'package:flutter_openclaude/workbench/workbench_models.dart';
import 'package:flutter_openclaude/workbench/workbench_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop shell renders four persistent regions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: WorkbenchShell(state: createInitialWorkbenchState())),
    );

    expect(find.byKey(const ValueKey('activity-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-sidebar')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('inspector-panel')), findsOneWidget);
  });

  testWidgets('mac default window keeps session sidebar visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: WorkbenchShell(state: createInitialWorkbenchState())),
    );

    expect(find.byKey(const ValueKey('activity-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-sidebar')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('inspector-panel')), findsNothing);
  });

  testWidgets('session sidebar shows sessions and supports session selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? selectedSessionId;
    final state = createInitialWorkbenchState();

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onSessionSelected: (id) => selectedSessionId = id,
        ),
      ),
    );

    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Search sessions'), findsOneWidget);
    expect(find.byTooltip('New session'), findsOneWidget);
    final sessionTitleInSidebar = find.descendant(
      of: find.byKey(const ValueKey('session-sidebar')),
      matching: find.text(state.sessions.first.title),
    );
    expect(sessionTitleInSidebar, findsOneWidget);
    expect(find.text(state.provider.modelName), findsOneWidget);

    await tester.tap(sessionTitleInSidebar);
    expect(selectedSessionId, state.sessions.first.id);
  });

  testWidgets('session sidebar exposes delete action for each session', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? deletedSessionId;
    final state = createInitialWorkbenchState();

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onSessionDeleted: (id) => deletedSessionId = id,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Delete session'));

    expect(deletedSessionId, state.sessions.first.id);
  });

  testWidgets('session sidebar exposes project directory picker action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var pickedProject = false;

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: createInitialWorkbenchState(),
          onProjectDirectorySelected: () => pickedProject = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-project-button')));

    expect(pickedProject, isTrue);
  });

  testWidgets('session sidebar search filters visible sessions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? searchQuery;
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

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onSessionSearchChanged: (value) => searchQuery = value,
        ),
      ),
    );

    final sidebar = find.byKey(const ValueKey('session-sidebar'));
    expect(
      find.descendant(of: sidebar, matching: find.text('API key setup')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('Context retrieval')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('session-search')),
      'docs',
    );
    expect(searchQuery, 'docs');
  });

  testWidgets('narrow layout keeps chat usable and exposes project picker', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var pickedProject = false;

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: createInitialWorkbenchState(),
          onProjectDirectorySelected: () => pickedProject = true,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('activity-rail')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('composer-input')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-open-project-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('chat-open-project-button')));
    expect(pickedProject, isTrue);
  });

  testWidgets('chat header summarizes active extension warnings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = createInitialWorkbenchState().copyWith(
      activeExtensions: const ActiveExtensionsState(
        mcpServers: ['filesystem'],
        skills: ['debug'],
        warnings: ['MCP server github failed to connect.'],
      ),
    );

    await tester.pumpWidget(MaterialApp(home: WorkbenchShell(state: state)));

    expect(find.text('Extensions 2'), findsOneWidget);
    expect(find.text('1 issue'), findsOneWidget);
    expect(find.textContaining('github failed'), findsNothing);
  });

  testWidgets('setup assistant guides incomplete first-run configuration', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    WorkbenchDestination? destination;
    var reconnectRequested = false;
    var startBridgeRequested = false;
    var dismissed = false;
    final state = createInitialWorkbenchState().copyWith(
      connectionStatus: ConnectionStatus.disconnected,
      provider: createInitialWorkbenchState().provider.copyWith(
        apiKeyConfigured: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onDestinationChanged: (value) => destination = value,
          onBridgeReconnect: () => reconnectRequested = true,
          onBridgeStart: () => startBridgeRequested = true,
          onSetupAssistantDismissed: () => dismissed = true,
        ),
      ),
    );

    final assistant = find.byKey(const ValueKey('setup-assistant-panel'));
    expect(assistant, findsOneWidget);
    expect(find.text('Setup assistant'), findsOneWidget);
    expect(find.text('Bridge disconnected'), findsOneWidget);
    expect(find.text('API key missing'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('setup-start-bridge-button')));
    await tester.pump();
    expect(startBridgeRequested, isTrue);

    await tester.tap(find.byKey(const ValueKey('setup-reconnect-button')));
    await tester.pump();
    expect(reconnectRequested, isTrue);

    await tester.tap(find.byKey(const ValueKey('setup-provider-button')));
    await tester.pump();
    expect(destination, WorkbenchDestination.providers);

    await tester.tap(find.byKey(const ValueKey('setup-diagnostics-button')));
    await tester.pump();
    expect(destination, WorkbenchDestination.diagnostics);

    await tester.tap(find.byKey(const ValueKey('setup-dismiss-button')));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets('setup assistant stays hidden after dismissal', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = createInitialWorkbenchState().copyWith(
      setupAssistantDismissed: true,
      connectionStatus: ConnectionStatus.disconnected,
    );

    await tester.pumpWidget(MaterialApp(home: WorkbenchShell(state: state)));

    expect(find.byKey(const ValueKey('setup-assistant-panel')), findsNothing);
  });

  testWidgets(
    'diagnostics workspace renders setup status and reconnect action',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var reconnectRequested = false;
      var startBridgeRequested = false;
      var switchPortRequested = false;
      var reportCopied = false;
      final initialState = createInitialWorkbenchState();
      final state = initialState.copyWith(
        destination: WorkbenchDestination.diagnostics,
        connectionStatus: ConnectionStatus.error,
        bridgeLaunchStatus: BridgeLaunchStatus.failed,
        diagnosticsReportCopyStatus: DiagnosticsReportCopyStatus.copied,
        provider: initialState.provider.copyWith(apiKeyConfigured: true),
        personal: initialState.personal.copyWith(
          defaultWorkingDirectory: '/workspace/openclaude',
        ),
        sessions: const [
          SessionSummary(
            id: 'session-testclaude',
            title: 'testclaude',
            subtitle: '/workspace/testclaude',
            status: SessionStatus.idle,
            updatedLabel: 'Now',
          ),
        ],
        activeSessionId: 'session-testclaude',
        turnTimeline: const [
          TurnTimelineEntry(
            id: 'timeline-1',
            requestId: 'ui-request-1',
            stage: 'sdk_first_message',
            status: 'completed',
            timestamp: '2026-06-21T00:00:00.000Z',
            durationMs: 842,
            detail: 'First SDK message: system.',
          ),
        ],
        diagnosticLogs: const [
          DiagnosticLogEntry(
            id: 'diagnostic-1',
            severity: DiagnosticSeverity.error,
            title: 'Bridge connection failed',
            detail: 'Connection refused',
            timestampLabel: 'Now',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WorkbenchShell(
            state: state,
            onBridgeReconnect: () => reconnectRequested = true,
            onBridgeStart: () => startBridgeRequested = true,
            onBridgeSwitchPort: () => switchPortRequested = true,
            onDiagnosticsReportCopied: () => reportCopied = true,
          ),
        ),
      );

      final panel = find.byKey(const ValueKey('diagnostics-panel'));
      expect(panel, findsOneWidget);
      expect(find.byTooltip('Diagnostics'), findsOneWidget);
      expect(find.text('Setup checklist'), findsOneWidget);
      expect(find.text('Bridge'), findsOneWidget);
      expect(find.text('Launcher'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Report copied'), findsOneWidget);
      expect(find.text(initialState.bridgeUrl), findsNothing);
      expect(find.text('Managed internally'), findsOneWidget);
      expect(
        find.descendant(
          of: panel,
          matching: find.text('/workspace/testclaude'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.text('/workspace/openclaude'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('diagnostics-reconnect-button')),
      );
      await tester.pump();

      expect(reconnectRequested, isTrue);

      await tester.tap(find.byKey(const ValueKey('diagnostics-start-button')));
      await tester.pump();

      expect(startBridgeRequested, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('diagnostics-switch-port-button')),
      );
      await tester.pump();

      expect(switchPortRequested, isTrue);

      await tester.tap(find.byKey(const ValueKey('diagnostics-copy-button')));
      await tester.pump();

      expect(reportCopied, isTrue);

      await tester.drag(
        find.byKey(const ValueKey('diagnostics-scroll')),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();
      expect(find.text('Turn timeline'), findsOneWidget);
      expect(find.text('First SDK message'), findsOneWidget);
      expect(find.text('842 ms'), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('diagnostics-scroll')),
        const Offset(0, -360),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bridge connection failed'), findsOneWidget);
      expect(find.text('Connection refused'), findsOneWidget);
    },
  );

  testWidgets('pending permission requests open an approval dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    PermissionRequest? approvedRequest;
    String? approvedDecision;
    final state = createInitialWorkbenchState().copyWith(
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
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onPermissionDecision: (request, decision) {
            approvedRequest = request;
            approvedDecision = decision;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Approve Bash'), findsOneWidget);
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();

    expect(approvedRequest?.toolUseId, 'tool-1');
    expect(approvedDecision, 'allow');
  });

  testWidgets('pending permission opens even when a stale tool is running', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    PermissionRequest? approvedRequest;
    String? approvedDecision;
    final state = createInitialWorkbenchState().copyWith(
      permissionRequests: const [
        PermissionRequest(
          id: 'req-2:tool-2',
          requestId: 'req-2',
          toolUseId: 'tool-2',
          title: 'Approve Bash',
          action: 'touch next.txt',
          riskSummary: 'Review this tool request before allowing it.',
          rawPayload: '{}',
        ),
      ],
      toolRuns: const [
        ToolRun(
          id: 'tool-1',
          name: 'Bash',
          command: 'touch text.txt',
          status: ToolRunStatus.running,
          summary: 'Executing approved command',
          details: '{}',
          elapsedLabel: 'Now',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onPermissionDecision: (request, decision) {
            approvedRequest = request;
            approvedDecision = decision;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Approve Bash'), findsOneWidget);
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();

    expect(approvedRequest?.toolUseId, 'tool-2');
    expect(approvedDecision, 'allow');
  });

  testWidgets('context workspace renders knowledge indexing controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    KnowledgeIndexRequest? request;
    final state = createInitialWorkbenchState().copyWith(
      destination: WorkbenchDestination.context,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onKnowledgeIndexRequested: (value) => request = value,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('knowledge-panel')), findsOneWidget);
    expect(find.text('Knowledge'), findsOneWidget);
    expect(find.byKey(const ValueKey('knowledge-path-input')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('knowledge-path-input')),
      'docs',
    );
    await tester.tap(find.byKey(const ValueKey('knowledge-index-button')));
    await tester.pump();

    expect(request?.target, KnowledgeIndexTarget.directory);
    expect(request?.path, 'docs');
  });

  testWidgets('context workspace manages memory facts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var refreshed = false;
    ({String source, String id})? deleted;
    ({String source, String id, bool disabled})? disabled;
    MemoryFactEditRequest? edited;
    final state = createInitialWorkbenchState().copyWith(
      destination: WorkbenchDestination.context,
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
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onMemoryFactsRefresh: () => refreshed = true,
          onMemoryFactDeleted: (source, id) =>
              deleted = (source: source, id: id),
          onMemoryFactDisabledChanged: (source, id, value) =>
              disabled = (source: source, id: id, disabled: value),
          onMemoryFactEdited: (request) => edited = request,
        ),
      ),
    );

    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Preferred tone'), findsOneWidget);
    expect(find.text('User prefers concise answers.'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh memory'));
    await tester.pump();
    expect(refreshed, isTrue);

    await tester.tap(find.byTooltip('Disable memory'));
    await tester.pump();
    expect(disabled, (source: 'profile', id: 'profile-tone', disabled: true));

    await tester.tap(find.byTooltip('Edit memory'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('memory-edit-title-input')),
      'Preferred answer style',
    );
    await tester.enterText(
      find.byKey(const ValueKey('memory-edit-content-input')),
      'User prefers direct answers.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(edited?.source, 'profile');
    expect(edited?.id, 'profile-tone');
    expect(edited?.title, 'Preferred answer style');
    expect(edited?.content, 'User prefers direct answers.');

    await tester.tap(find.byTooltip('Delete memory'));
    await tester.pump();
    expect(deleted, (source: 'profile', id: 'profile-tone'));
  });

  testWidgets('context workspace renders retrieval evaluation metrics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var requested = false;
    final state = createInitialWorkbenchState().copyWith(
      destination: WorkbenchDestination.context,
      retrievalEvaluation: const RetrievalEvaluationState(
        status: RetrievalEvaluationStatus.completed,
        report: RetrievalEvaluationReport(
          k: 5,
          hitRate: 1,
          precisionAtK: 0.2,
          mrr: 1,
          sourceShare: {'document': 1},
          cases: [
            RetrievalEvaluationCaseResult(
              name: 'Provider settings',
              query: 'Provider settings',
              hit: true,
              precisionAtK: 0.2,
              firstRelevantRank: 1,
              reciprocalRank: 1,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onRetrievalEvaluationRequested: () => requested = true,
        ),
      ),
    );

    final panel = find.byKey(const ValueKey('retrieval-evaluation-panel'));
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('Hit Rate')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('100%')),
      findsWidgets,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Provider settings')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('retrieval-evaluation-run-button')),
    );
    await tester.pump();
    expect(requested, isTrue);
  });

  testWidgets('tools workspace renders tool runs and selects details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? selectedToolId;
    final state = createInitialWorkbenchState().copyWith(
      destination: WorkbenchDestination.tools,
      toolRuns: const [
        ToolRun(
          id: 'tool-1',
          name: 'Bash',
          command: 'git status',
          status: ToolRunStatus.pending,
          summary: 'Waiting for approval',
          details: '{"command":"git status"}',
          elapsedLabel: 'Now',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onToolSelected: (id) => selectedToolId = id,
        ),
      ),
    );

    final toolsPanel = find.byKey(const ValueKey('tools-panel'));
    expect(toolsPanel, findsOneWidget);
    expect(
      find.descendant(of: toolsPanel, matching: find.text('Bash')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: toolsPanel,
        matching: find.textContaining('git status'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: toolsPanel, matching: find.text('Bash')),
    );
    expect(selectedToolId, 'tool-1');
  });

  testWidgets('extensions workspace renders skills and MCP inventory', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = createInitialWorkbenchState().copyWith(
      destination: WorkbenchDestination.extensions,
      extensions: const ExtensionsState(
        skillsStatus: ExtensionInventoryStatus.loaded,
        skills: [
          SkillSummary(
            id: 'debug',
            name: 'debug',
            description: 'Debug a failing workflow.',
            source: 'bundled',
            status: 'enabled',
          ),
        ],
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
          ),
        ],
      ),
    );

    await tester.pumpWidget(MaterialApp(home: WorkbenchShell(state: state)));

    final panel = find.byKey(const ValueKey('extensions-panel'));
    expect(panel, findsOneWidget);
    expect(find.byTooltip('Extensions'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('MCP'), findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('debug')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.text('Debug a failing workflow.'),
      ),
      findsWidgets,
    );

    await tester.tap(find.text('MCP'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: panel, matching: find.text('filesystem')),
      findsWidgets,
    );
    expect(
      find.descendant(of: panel, matching: find.text('project · stdio')),
      findsWidgets,
    );
  });

  testWidgets('extensions marketplace searches and marks installed items', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = createInitialWorkbenchState().copyWith(
      destination: WorkbenchDestination.extensions,
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
        mcpStatus: ExtensionInventoryStatus.loaded,
        mcpServers: [
          McpServerSummary(
            id: 'filesystem',
            name: 'filesystem',
            transport: 'stdio',
            scope: 'project',
            enabled: true,
            status: 'connected',
            toolCount: 3,
            resourceCount: 0,
            skillCount: 0,
          ),
        ],
      ),
    );

    await tester.pumpWidget(MaterialApp(home: WorkbenchShell(state: state)));

    await tester.tap(find.text('Marketplace'));
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('marketplace-panel'));
    expect(panel, findsOneWidget);
    expect(find.text('debug'), findsWidgets);
    expect(find.text('Installed'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('marketplace-search-input')),
      'mcp',
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: panel, matching: find.text('filesystem')),
      findsWidgets,
    );
    expect(
      find.descendant(of: panel, matching: find.text('MCP')),
      findsWidgets,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Enabled')),
      findsWidgets,
    );
  });

  testWidgets('extensions marketplace runs curated local actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? importedPath;
    McpServerDraft? savedTemplate;
    final state = createInitialWorkbenchState().copyWith(
      destination: WorkbenchDestination.extensions,
      extensions: const ExtensionsState(
        skillsStatus: ExtensionInventoryStatus.loaded,
        skills: [],
        mcpStatus: ExtensionInventoryStatus.loaded,
        mcpServers: [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onSkillImported: (path) => importedPath = path,
          onMcpServerSaved: (draft) => savedTemplate = draft,
        ),
      ),
    );

    await tester.tap(find.text('Marketplace'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('marketplace-action-curated-workspace-memory')),
    );
    await tester.pump();
    expect(importedPath, 'skills/workspace-memory');

    await tester.tap(
      find.byKey(const ValueKey('marketplace-action-curated-filesystem-mcp')),
    );
    await tester.pump();
    expect(savedTemplate?.name, 'filesystem-mcp');
    expect(savedTemplate?.transport, 'stdio');
    expect(savedTemplate?.command, 'npx');
  });

  testWidgets('Skills workspace imports refreshes and toggles skills', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? importedPath;
    ({String skillId, bool enabled})? enabledChange;
    var refreshed = false;
    final state = createInitialWorkbenchState().copyWith(
      destination: WorkbenchDestination.extensions,
      extensions: const ExtensionsState(
        skillsStatus: ExtensionInventoryStatus.loaded,
        skills: [
          SkillSummary(
            id: 'debug',
            name: 'debug',
            description: 'Debug a failing workflow.',
            source: 'local',
            status: 'enabled',
            path: '/tmp/skills/debug',
          ),
        ],
        mcpStatus: ExtensionInventoryStatus.loaded,
        mcpServers: [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onSkillImported: (path) => importedPath = path,
          onSkillEnabledChanged: (skillId, enabled) =>
              enabledChange = (skillId: skillId, enabled: enabled),
          onSkillsRefresh: () => refreshed = true,
        ),
      ),
    );

    expect(find.text('debug'), findsWidgets);
    expect(find.text('Debug a failing workflow.'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('skill-import-button')));
    await tester.pump();
    expect(find.text('Enter a skill directory path first.'), findsOneWidget);
    expect(importedPath, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('skill-import-path-input')),
      '/tmp/skills/debug',
    );
    await tester.tap(find.byKey(const ValueKey('skill-import-button')));
    await tester.pump();
    expect(importedPath, '/tmp/skills/debug');

    await tester.tap(find.byTooltip('Disable skill'));
    await tester.pump();
    expect(enabledChange, (skillId: 'debug', enabled: false));

    await tester.tap(find.byTooltip('Refresh skills'));
    await tester.pump();
    expect(refreshed, isTrue);
  });

  testWidgets('MCP workspace edits server settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    McpServerDraft? saved;
    McpServerDraft? tested;
    ({String serverId, bool enabled})? enabledChange;
    String? deletedServerId;
    final state = createInitialWorkbenchState().copyWith(
      destination: WorkbenchDestination.extensions,
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
            env: {'FILESYSTEM_TOKEN': '********'},
          ),
        ],
        mcpTestResults: {
          'filesystem': McpConnectionTestResult(
            serverId: 'filesystem',
            status: 'connected',
            message: 'Connected',
            durationMs: 42,
            checkedAt: '2026-06-20T00:00:00.000Z',
            tools: [McpCapabilityItem(name: 'read_file')],
            resources: [McpCapabilityItem(name: 'file://workspace')],
            prompts: [McpCapabilityItem(name: 'summarize')],
            skills: [],
          ),
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorkbenchShell(
          state: state,
          onMcpServerSaved: (request) => saved = request,
          onMcpServerTested: (request) => tested = request,
          onMcpServerEnabledChanged: (serverId, enabled) =>
              enabledChange = (serverId: serverId, enabled: enabled),
          onMcpServerDeleted: (serverId) => deletedServerId = serverId,
        ),
      ),
    );

    await tester.tap(find.text('MCP'));
    await tester.pumpAndSettle();

    expect(find.text('filesystem'), findsWidgets);
    expect(find.text('npx'), findsOneWidget);
    expect(find.text('read_file'), findsOneWidget);

    await tester.tap(find.byTooltip('Test MCP server'));
    await tester.pump();
    expect(tested?.id, 'filesystem');
    expect(tested?.command, 'npx');

    await tester.tap(find.byTooltip('Disable MCP server'));
    await tester.pump();
    expect(enabledChange, (serverId: 'filesystem', enabled: false));

    await tester.tap(find.byTooltip('Delete MCP server'));
    await tester.pump();
    expect(deletedServerId, 'filesystem');

    await tester.drag(
      find.byKey(const ValueKey('mcp-server-detail-scroll')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(find.text('FILESYSTEM_TOKEN=********'), findsOneWidget);

    await tester.tap(find.byTooltip('Add MCP server'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mcp-server-name-input')),
      'Filesystem Server',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mcp-server-command-input')),
      'npx',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mcp-server-args-input')),
      '-y @modelcontextprotocol/server-filesystem',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mcp-server-env-input')),
      'FILESYSTEM_TOKEN=secret',
    );
    await tester.tap(find.byKey(const ValueKey('mcp-server-save-button')));
    await tester.pumpAndSettle();

    expect(saved?.name, 'Filesystem Server');
    expect(saved?.command, 'npx');
    expect(saved?.args, ['-y', '@modelcontextprotocol/server-filesystem']);
    expect(saved?.env, {'FILESYSTEM_TOKEN': 'secret'});
  });
}
