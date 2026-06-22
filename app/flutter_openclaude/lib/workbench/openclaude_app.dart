import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge/bridge_client.dart';
import '../bridge/bridge_transport.dart';
import 'app_branding.dart';
import 'bridge_process_launcher.dart';
import 'chat_attachment_picker.dart';
import 'project_directory_picker.dart';
import 'workbench_controller.dart';
import 'workbench_models.dart';
import 'workbench_persistence.dart';
import 'workbench_shell.dart';
import 'workbench_theme.dart';

typedef BridgeClientFactory = BridgeClient Function(String bridgeUrl);

class OpenClaudeApp extends StatefulWidget {
  const OpenClaudeApp({
    super.key,
    this.createBridgeClient,
    this.bridgeProcessLauncher,
    this.persistenceStore,
    this.autoStartBridge = false,
  });

  final BridgeClientFactory? createBridgeClient;
  final BridgeProcessLauncher? bridgeProcessLauncher;
  final WorkbenchPersistenceStore? persistenceStore;
  final bool autoStartBridge;

  @override
  State<OpenClaudeApp> createState() => _OpenClaudeAppState();
}

class _OpenClaudeAppState extends State<OpenClaudeApp> {
  late final WorkbenchController _controller;

  @override
  void initState() {
    super.initState();
    final initialState = createInitialWorkbenchState();
    final createBridgeClient =
        widget.createBridgeClient ??
        (bridgeUrl) => BridgeClient(WebSocketBridgeTransport(bridgeUrl));
    _controller = WorkbenchController(
      initialState: initialState,
      bridgeClient: widget.autoStartBridge
          ? null
          : createBridgeClient(initialState.bridgeUrl),
      createBridgeClient: createBridgeClient,
      bridgeProcessLauncher:
          widget.bridgeProcessLauncher ?? createDefaultBridgeProcessLauncher(),
      projectDirectoryPicker: createDefaultProjectDirectoryPicker(),
      persistenceStore:
          widget.persistenceStore ?? createDefaultWorkbenchPersistenceStore(),
    );
    unawaited(_restoreStateAndMaybeStartBridge());
  }

  Future<void> _restoreStateAndMaybeStartBridge() async {
    await _controller.restorePersistedState();
    if (!mounted || !widget.autoStartBridge) return;
    if (_controller.state.connectionStatus == ConnectionStatus.connected) {
      return;
    }
    unawaited(_controller.startLocalBridge());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appDisplayName,
      debugShowCheckedModeBanner: false,
      theme: buildWorkbenchTheme(),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return WorkbenchShell(
            state: _controller.state,
            onDestinationChanged: _controller.selectDestination,
            onSessionSelected: _controller.selectSession,
            onSessionSearchChanged: _controller.updateSessionSearchQuery,
            onNewSession: _controller.newSession,
            onSessionDeleted: _controller.deleteSession,
            onProjectDirectorySelected: () =>
                unawaited(_controller.chooseProjectDirectory()),
            onSendMessage: _controller.sendMessage,
            onSendRequest: (request) => _controller.sendMessage(
              request.text,
              attachments: request.attachments,
            ),
            onThinkingModeChanged: (enabled) => _controller.updatePersonal(
              _controller.state.personal.copyWith(
                thinkingModeEnabled: enabled,
              ),
            ),
            onPickAttachments: pickChatAttachments,
            onStop: _controller.stopStreaming,
            onMessageSelected: _controller.selectMessage,
            onToolSelected: _controller.selectTool,
            onLearningCandidateAccepted: _controller.acceptLearningCandidate,
            onLearningCandidateDismissed: _controller.dismissLearningCandidate,
            onProviderChanged: _controller.updateProvider,
            onApiKeySubmitted: _controller.submitApiKey,
            onTestConnection: _controller.testProviderConnection,
            onPersonalChanged: _controller.updatePersonal,
            onKnowledgeIndexRequested: _controller.indexKnowledgePath,
            onRetrievalEvaluationRequested: _controller.runRetrievalEvaluation,
            onMemoryFactsRefresh: _controller.refreshMemoryFacts,
            onMemoryFactDeleted: _controller.deleteMemoryFact,
            onMemoryFactDisabledChanged: _controller.setMemoryFactDisabled,
            onExtensionsRefresh: _controller.refreshExtensionsInventory,
            onSkillImported: _controller.importSkill,
            onSkillEnabledChanged: _controller.setSkillEnabled,
            onSkillsRefresh: _controller.refreshSkills,
            onMcpServerSaved: _controller.saveMcpServer,
            onMcpServerTested: _controller.testMcpServer,
            onMcpServerEnabledChanged: _controller.setMcpServerEnabled,
            onMcpServerDeleted: _controller.deleteMcpServer,
            onBridgeReconnect: () => _controller.reconnectBridge(),
            onBridgeStart: () => unawaited(_controller.startLocalBridge()),
            onBridgeSwitchPort: () => unawaited(
              _controller.startLocalBridge(
                strategy: BridgeReconnectStrategy.switchPort,
              ),
            ),
            onSetupAssistantDismissed: _controller.dismissSetupAssistant,
            onDiagnosticsReportCopied: () =>
                unawaited(_controller.copyDiagnosticsReport()),
            onMemoryFactEdited: (request) {
              _controller.updateMemoryFact(
                request.source,
                request.id,
                title: request.title,
                content: request.content,
              );
            },
            onPermissionDecision: (request, decision) {
              _controller.respondToPermission(
                requestId: request.requestId,
                toolUseId: request.toolUseId,
                decision: decision,
              );
            },
          );
        },
      ),
    );
  }
}
