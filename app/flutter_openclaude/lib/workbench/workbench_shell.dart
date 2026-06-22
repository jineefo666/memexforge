import 'package:flutter/material.dart';

import 'activity_rail.dart';
import 'conversation_workspace.dart';
import 'diagnostics_panel.dart';
import 'extensions_panel.dart';
import 'inspector_panel.dart';
import 'knowledge_base_panel.dart';
import 'permission_dialog.dart';
import 'personal_settings_panel.dart';
import 'provider_settings_panel.dart';
import 'session_sidebar.dart';
import 'setup_assistant_panel.dart';
import 'tools_panel.dart';
import 'workbench_models.dart';

typedef PermissionDecisionHandler =
    void Function(PermissionRequest request, String decision);
typedef McpServerEnabledChangedHandler =
    void Function(String serverId, bool enabled);
typedef SkillEnabledChangedHandler =
    void Function(String skillId, bool enabled);

class WorkbenchShell extends StatefulWidget {
  const WorkbenchShell({
    super.key,
    required this.state,
    this.onDestinationChanged,
    this.onSessionSelected,
    this.onSessionSearchChanged,
    this.onNewSession,
    this.onSessionDeleted,
    this.onProjectDirectorySelected,
    this.onSendMessage,
    this.onSendRequest,
    this.onThinkingModeChanged,
    this.onPickAttachments,
    this.onStop,
    this.onMessageSelected,
    this.onToolSelected,
    this.onLearningCandidateAccepted,
    this.onLearningCandidateDismissed,
    this.onProviderChanged,
    this.onApiKeySubmitted,
    this.onTestConnection,
    this.onPersonalChanged,
    this.onKnowledgeIndexRequested,
    this.onRetrievalEvaluationRequested,
    this.onMemoryFactsRefresh,
    this.onMemoryFactDeleted,
    this.onMemoryFactDisabledChanged,
    this.onMemoryFactEdited,
    this.onExtensionsRefresh,
    this.onSkillImported,
    this.onSkillEnabledChanged,
    this.onSkillsRefresh,
    this.onMcpServerSaved,
    this.onMcpServerTested,
    this.onMcpServerEnabledChanged,
    this.onMcpServerDeleted,
    this.onBridgeReconnect,
    this.onBridgeStart,
    this.onBridgeSwitchPort,
    this.onSetupAssistantDismissed,
    this.onDiagnosticsReportCopied,
    this.onPermissionDecision,
  });

  final WorkbenchState state;
  final ValueChanged<WorkbenchDestination>? onDestinationChanged;
  final ValueChanged<String>? onSessionSelected;
  final ValueChanged<String>? onSessionSearchChanged;
  final VoidCallback? onNewSession;
  final ValueChanged<String>? onSessionDeleted;
  final VoidCallback? onProjectDirectorySelected;
  final ValueChanged<String>? onSendMessage;
  final ChatSendRequestHandler? onSendRequest;
  final ValueChanged<bool>? onThinkingModeChanged;
  final ChatAttachmentPicker? onPickAttachments;
  final VoidCallback? onStop;
  final ValueChanged<String>? onMessageSelected;
  final ValueChanged<String>? onToolSelected;
  final ValueChanged<String>? onLearningCandidateAccepted;
  final ValueChanged<String>? onLearningCandidateDismissed;
  final ValueChanged<ProviderSettings>? onProviderChanged;
  final ValueChanged<String>? onApiKeySubmitted;
  final ValueChanged<ProviderConnectionRequest>? onTestConnection;
  final ValueChanged<PersonalSettings>? onPersonalChanged;
  final ValueChanged<KnowledgeIndexRequest>? onKnowledgeIndexRequested;
  final VoidCallback? onRetrievalEvaluationRequested;
  final VoidCallback? onMemoryFactsRefresh;
  final MemoryFactDeletedHandler? onMemoryFactDeleted;
  final MemoryFactDisabledChangedHandler? onMemoryFactDisabledChanged;
  final ValueChanged<MemoryFactEditRequest>? onMemoryFactEdited;
  final VoidCallback? onExtensionsRefresh;
  final ValueChanged<String>? onSkillImported;
  final SkillEnabledChangedHandler? onSkillEnabledChanged;
  final VoidCallback? onSkillsRefresh;
  final ValueChanged<McpServerDraft>? onMcpServerSaved;
  final ValueChanged<McpServerDraft>? onMcpServerTested;
  final McpServerEnabledChangedHandler? onMcpServerEnabledChanged;
  final ValueChanged<String>? onMcpServerDeleted;
  final VoidCallback? onBridgeReconnect;
  final VoidCallback? onBridgeStart;
  final VoidCallback? onBridgeSwitchPort;
  final VoidCallback? onSetupAssistantDismissed;
  final VoidCallback? onDiagnosticsReportCopied;
  final PermissionDecisionHandler? onPermissionDecision;

  @override
  State<WorkbenchShell> createState() => _WorkbenchShellState();
}

class _WorkbenchShellState extends State<WorkbenchShell> {
  String? _activePermissionDialogId;

  @override
  void initState() {
    super.initState();
    _queuePermissionDialog();
  }

  @override
  void didUpdateWidget(covariant WorkbenchShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _queuePermissionDialog();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSidebar = constraints.maxWidth >= 760;
          final showInspector = constraints.maxWidth >= 1100;
          return Row(
            children: [
              ActivityRail(
                destination: widget.state.destination,
                onDestinationChanged: widget.onDestinationChanged,
              ),
              if (showSidebar)
                SessionSidebar(
                  state: widget.state,
                  onSessionSelected: widget.onSessionSelected,
                  onSearchChanged: widget.onSessionSearchChanged,
                  onNewSession: widget.onNewSession,
                  onSessionDeleted: widget.onSessionDeleted,
                  onProjectDirectorySelected: widget.onProjectDirectorySelected,
                ),
              Expanded(child: _buildWorkspaceColumn()),
              if (showInspector) InspectorPanel(state: widget.state),
            ],
          );
        },
      ),
    );
  }

  void _queuePermissionDialog() {
    if (_activePermissionDialogId != null ||
        widget.state.permissionRequests.isEmpty) {
      return;
    }

    final request = widget.state.permissionRequests.first;
    _activePermissionDialogId = request.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPermissionDialog(request.id);
    });
  }

  Future<void> _showPermissionDialog(String requestId) async {
    if (!mounted) return;

    final request = _pendingPermissionById(requestId);
    if (request == null) {
      _activePermissionDialogId = null;
      _queuePermissionDialog();
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PermissionDialog(
        request: request,
        onDecision: (decision) {
          widget.onPermissionDecision?.call(request, decision);
        },
      ),
    );

    if (!mounted) return;
    _activePermissionDialogId = null;
    _queuePermissionDialog();
  }

  PermissionRequest? _pendingPermissionById(String id) {
    for (final request in widget.state.permissionRequests) {
      if (request.id == id) return request;
    }
    return null;
  }

  Widget _buildWorkspaceColumn() {
    return Column(
      children: [
        if (widget.state.shouldShowSetupAssistant)
          SetupAssistantPanel(
            state: widget.state,
            onStartBridge: widget.onBridgeStart,
            onReconnectBridge: widget.onBridgeReconnect,
            onOpenProviderSettings: () {
              widget.onDestinationChanged?.call(WorkbenchDestination.providers);
            },
            onOpenDiagnostics: () {
              widget.onDestinationChanged?.call(
                WorkbenchDestination.diagnostics,
              );
            },
            onDismiss: widget.onSetupAssistantDismissed,
          ),
        Expanded(
          child: _MainWorkspace(
            state: widget.state,
            onSendMessage: widget.onSendMessage,
            onSendRequest: widget.onSendRequest,
            onThinkingModeChanged: widget.onThinkingModeChanged,
            onPickAttachments: widget.onPickAttachments,
            onStop: widget.onStop,
            onProjectDirectorySelected: widget.onProjectDirectorySelected,
            onMessageSelected: widget.onMessageSelected,
            onToolSelected: widget.onToolSelected,
            onLearningCandidateAccepted: widget.onLearningCandidateAccepted,
            onLearningCandidateDismissed: widget.onLearningCandidateDismissed,
            onProviderChanged: widget.onProviderChanged,
            onApiKeySubmitted: widget.onApiKeySubmitted,
            onTestConnection: widget.onTestConnection,
            onPersonalChanged: widget.onPersonalChanged,
            onKnowledgeIndexRequested: widget.onKnowledgeIndexRequested,
            onRetrievalEvaluationRequested:
                widget.onRetrievalEvaluationRequested,
            onMemoryFactsRefresh: widget.onMemoryFactsRefresh,
            onMemoryFactDeleted: widget.onMemoryFactDeleted,
            onMemoryFactDisabledChanged: widget.onMemoryFactDisabledChanged,
            onMemoryFactEdited: widget.onMemoryFactEdited,
            onExtensionsRefresh: widget.onExtensionsRefresh,
            onSkillImported: widget.onSkillImported,
            onSkillEnabledChanged: widget.onSkillEnabledChanged,
            onSkillsRefresh: widget.onSkillsRefresh,
            onMcpServerSaved: widget.onMcpServerSaved,
            onMcpServerTested: widget.onMcpServerTested,
            onMcpServerEnabledChanged: widget.onMcpServerEnabledChanged,
            onMcpServerDeleted: widget.onMcpServerDeleted,
            onBridgeReconnect: widget.onBridgeReconnect,
            onBridgeStart: widget.onBridgeStart,
            onBridgeSwitchPort: widget.onBridgeSwitchPort,
            onDiagnosticsReportCopied: widget.onDiagnosticsReportCopied,
          ),
        ),
      ],
    );
  }
}

class _MainWorkspace extends StatelessWidget {
  const _MainWorkspace({
    required this.state,
    this.onSendMessage,
    this.onSendRequest,
    this.onThinkingModeChanged,
    this.onPickAttachments,
    this.onStop,
    this.onProjectDirectorySelected,
    this.onMessageSelected,
    this.onToolSelected,
    this.onLearningCandidateAccepted,
    this.onLearningCandidateDismissed,
    this.onProviderChanged,
    this.onApiKeySubmitted,
    this.onTestConnection,
    this.onPersonalChanged,
    this.onKnowledgeIndexRequested,
    this.onRetrievalEvaluationRequested,
    this.onMemoryFactsRefresh,
    this.onMemoryFactDeleted,
    this.onMemoryFactDisabledChanged,
    this.onMemoryFactEdited,
    this.onExtensionsRefresh,
    this.onSkillImported,
    this.onSkillEnabledChanged,
    this.onSkillsRefresh,
    this.onMcpServerSaved,
    this.onMcpServerTested,
    this.onMcpServerEnabledChanged,
    this.onMcpServerDeleted,
    this.onBridgeReconnect,
    this.onBridgeStart,
    this.onBridgeSwitchPort,
    this.onDiagnosticsReportCopied,
  });

  final WorkbenchState state;
  final ValueChanged<String>? onSendMessage;
  final ChatSendRequestHandler? onSendRequest;
  final ValueChanged<bool>? onThinkingModeChanged;
  final ChatAttachmentPicker? onPickAttachments;
  final VoidCallback? onStop;
  final VoidCallback? onProjectDirectorySelected;
  final ValueChanged<String>? onMessageSelected;
  final ValueChanged<String>? onToolSelected;
  final ValueChanged<String>? onLearningCandidateAccepted;
  final ValueChanged<String>? onLearningCandidateDismissed;
  final ValueChanged<ProviderSettings>? onProviderChanged;
  final ValueChanged<String>? onApiKeySubmitted;
  final ValueChanged<ProviderConnectionRequest>? onTestConnection;
  final ValueChanged<PersonalSettings>? onPersonalChanged;
  final ValueChanged<KnowledgeIndexRequest>? onKnowledgeIndexRequested;
  final VoidCallback? onRetrievalEvaluationRequested;
  final VoidCallback? onMemoryFactsRefresh;
  final MemoryFactDeletedHandler? onMemoryFactDeleted;
  final MemoryFactDisabledChangedHandler? onMemoryFactDisabledChanged;
  final ValueChanged<MemoryFactEditRequest>? onMemoryFactEdited;
  final VoidCallback? onExtensionsRefresh;
  final ValueChanged<String>? onSkillImported;
  final SkillEnabledChangedHandler? onSkillEnabledChanged;
  final VoidCallback? onSkillsRefresh;
  final ValueChanged<McpServerDraft>? onMcpServerSaved;
  final ValueChanged<McpServerDraft>? onMcpServerTested;
  final McpServerEnabledChangedHandler? onMcpServerEnabledChanged;
  final ValueChanged<String>? onMcpServerDeleted;
  final VoidCallback? onBridgeReconnect;
  final VoidCallback? onBridgeStart;
  final VoidCallback? onBridgeSwitchPort;
  final VoidCallback? onDiagnosticsReportCopied;

  @override
  Widget build(BuildContext context) {
    return switch (state.destination) {
      WorkbenchDestination.providers => ProviderSettingsPanel(
        settings: state.provider,
        onChanged: onProviderChanged,
        onApiKeySubmitted: onApiKeySubmitted,
        onTestConnection: onTestConnection,
      ),
      WorkbenchDestination.settings => PersonalSettingsPanel(
        settings: state.personal,
        onChanged: onPersonalChanged,
      ),
      WorkbenchDestination.context => KnowledgeBasePanel(
        state: state,
        onIndexRequested: onKnowledgeIndexRequested,
        onRetrievalEvaluationRequested: onRetrievalEvaluationRequested,
        onMemoryFactsRefresh: onMemoryFactsRefresh,
        onMemoryFactDeleted: onMemoryFactDeleted,
        onMemoryFactDisabledChanged: onMemoryFactDisabledChanged,
        onMemoryFactEdited: onMemoryFactEdited,
      ),
      WorkbenchDestination.tools => ToolsPanel(
        state: state,
        onToolSelected: onToolSelected,
      ),
      WorkbenchDestination.extensions => ExtensionsPanel(
        state: state,
        onRefresh: onExtensionsRefresh,
        onSkillImported: onSkillImported,
        onSkillEnabledChanged: onSkillEnabledChanged,
        onSkillsRefresh: onSkillsRefresh,
        onMcpServerSaved: onMcpServerSaved,
        onMcpServerTested: onMcpServerTested,
        onMcpServerEnabledChanged: onMcpServerEnabledChanged,
        onMcpServerDeleted: onMcpServerDeleted,
      ),
      WorkbenchDestination.diagnostics => DiagnosticsPanel(
        state: state,
        onBridgeReconnect: onBridgeReconnect,
        onBridgeStart: onBridgeStart,
        onBridgeSwitchPort: onBridgeSwitchPort,
        onCopyReport: onDiagnosticsReportCopied,
      ),
      WorkbenchDestination.chat => ConversationWorkspace(
        state: state,
        onSendMessage: onSendMessage,
        onSendRequest: onSendRequest,
        onThinkingModeChanged: onThinkingModeChanged,
        onPickAttachments: onPickAttachments,
        onStop: onStop,
        onProjectDirectorySelected: onProjectDirectorySelected,
        onMessageSelected: onMessageSelected,
        onToolSelected: onToolSelected,
        onLearningCandidateAccepted: onLearningCandidateAccepted,
        onLearningCandidateDismissed: onLearningCandidateDismissed,
      ),
    };
  }
}
