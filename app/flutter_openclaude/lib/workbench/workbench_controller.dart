import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bridge/bridge_client.dart';
import '../bridge/bridge_protocol.dart';
import 'app_branding.dart';
import 'bridge_process_launcher.dart';
import 'project_directory_picker.dart';
import 'workbench_models.dart';
import 'workbench_persistence.dart';

const _redactedSecret = '********';
const _maxAttachmentPromptCharacters = 12000;
const _permissionDecisionAllow = 'allow';
const _permissionDecisionAllowAll = 'allow_all';

typedef WorkbenchBridgeClientFactory = BridgeClient Function(String bridgeUrl);
typedef ClipboardTextWriter = Future<void> Function(String text);
typedef DelayedTaskScheduler =
    Timer Function(Duration delay, void Function() callback);

final class _PendingBridgeStart {
  const _PendingBridgeStart({
    required this.requestId,
    required this.prompt,
    required this.transcript,
  });

  final String requestId;
  final String prompt;
  final List<BridgeTranscriptMessage> transcript;
}

final class _SlashSkillPrompt {
  const _SlashSkillPrompt(this.name, this.request);

  final String name;
  final String request;
}

class WorkbenchController extends ChangeNotifier {
  WorkbenchController({
    BridgeClient? bridgeClient,
    WorkbenchBridgeClientFactory? createBridgeClient,
    BridgeProcessLauncher? bridgeProcessLauncher,
    ClipboardTextWriter? copyText,
    DelayedTaskScheduler? scheduleDelayedTask,
    ProjectDirectoryPicker? projectDirectoryPicker,
    WorkbenchState? initialState,
    WorkbenchPersistenceStore? persistenceStore,
  }) : _bridgeClient = bridgeClient,
       _createBridgeClient = createBridgeClient,
       _bridgeProcessLauncher = bridgeProcessLauncher,
       _copyText = copyText ?? _copyTextToClipboard,
       _scheduleDelayedTask = scheduleDelayedTask ?? Timer.new,
       _projectDirectoryPicker = projectDirectoryPicker,
       _persistenceStore = persistenceStore,
       _state = initialState ?? createInitialWorkbenchState() {
    _rememberActiveMessages();
    final bridgeClient = _bridgeClient;
    if (bridgeClient != null) {
      _bridgeSubscription = _listenToBridgeClient(bridgeClient);
    }
  }

  BridgeClient? _bridgeClient;
  final WorkbenchBridgeClientFactory? _createBridgeClient;
  final BridgeProcessLauncher? _bridgeProcessLauncher;
  final ClipboardTextWriter _copyText;
  final DelayedTaskScheduler _scheduleDelayedTask;
  final ProjectDirectoryPicker? _projectDirectoryPicker;
  final WorkbenchPersistenceStore? _persistenceStore;
  StreamSubscription<BridgeServerMessage>? _bridgeSubscription;
  Timer? _bridgeReconnectTimer;
  var _disposed = false;
  _PendingBridgeStart? _pendingBridgeStart;
  WorkbenchState _state;
  final _apiKeysByRoute = <String, String>{};
  final _messagesBySessionId = <String, List<ChatMessage>>{};
  final _allowAllToolPermissionSessionIds = <String>{};
  int _messageCounter = 0;
  int _requestCounter = 0;
  int _diagnosticCounter = 0;
  int _timelineCounter = 0;
  String? _activeRequestId;
  int _activeStreamEventCount = 0;
  int _activeStreamTextDeltaCount = 0;
  int _activeStreamThinkingDeltaCount = 0;
  String? _activeKnowledgeIndexRequestId;
  String? _activeContextLearnRequestId;
  String? _activeMemoryFactsRequestId;
  String? _activeRetrievalEvaluationRequestId;
  String? _activeSkillsListRequestId;
  String? _activeMcpServersListRequestId;
  String? _streamingAssistantMessageId;
  String _streamingAssistantText = '';
  final _learningUpsertRequestIds = <String, String>{};

  WorkbenchState get state => _state;

  String get _activeWorkingDirectory {
    final sessionDirectory = _state.activeSession?.subtitle.trim();
    if (sessionDirectory != null && sessionDirectory.isNotEmpty) {
      return sessionDirectory;
    }
    return _state.personal.defaultWorkingDirectory;
  }

  bool get _shouldAutoAllowToolPermissionsForActiveSession {
    return _allowAllToolPermissionSessionIds.contains(_state.activeSessionId);
  }

  StreamSubscription<BridgeServerMessage> _listenToBridgeClient(
    BridgeClient bridgeClient,
  ) {
    return bridgeClient.messages.listen(
      _handleBridgeMessage,
      onError: _handleBridgeError,
      onDone: _handleBridgeDone,
    );
  }

  Future<void> restorePersistedState() async {
    final store = _persistenceStore;
    if (store == null) return;
    try {
      final snapshot = await store.load();
      if (snapshot == null) return;
      final restored = decodePersistedWorkbenchState(
        snapshot: snapshot,
        fallback: _state,
      );
      _apiKeysByRoute
        ..clear()
        ..addAll(restored.apiKeysByRoute);
      _messagesBySessionId
        ..clear()
        ..addAll(restored.messagesBySessionId);
      _state = _state.copyWith(
        sessions: restored.sessions,
        activeSessionId: restored.activeSessionId,
        messages: restored.messages,
        provider: restored.provider,
        personal: restored.personal,
        bridgeUrl: restored.bridgeUrl,
        setupAssistantDismissed: restored.setupAssistantDismissed,
        clearErrorMessage: true,
      );
      notifyListeners();
      _persistState();
    } catch (error) {
      debugPrint('Failed to restore OpenClaude workbench state: $error');
    }
  }

  void sendMessage(String text, {List<ChatAttachment> attachments = const []}) {
    final prompt = text.trim();
    if (prompt.isEmpty && attachments.isEmpty) return;
    final visiblePrompt = prompt.isEmpty
        ? _attachmentOnlyPrompt(attachments)
        : prompt;

    final requestId = _nextRequestId();
    _activeRequestId = requestId;
    _resetActiveStreamCounters();
    _resetStreamingAssistantDraft();
    final transcript = _bridgeTranscriptForMessages(_state.messages);
    final bridgePrompt = _bridgePromptWithAttachments(
      _bridgePromptWithWorkspaceContext(
        _bridgePromptForSlashSkill(visiblePrompt),
      ),
      attachments,
    );
    final attachmentContextItems = _attachmentContextItems(attachments);
    final nextRetrievedContextItems = attachmentContextItems.isEmpty
        ? _state.retrievedContextItems
        : [
            ...attachmentContextItems,
            for (final item in _state.retrievedContextItems)
              if (item.source != 'attachment') item,
          ];
    final userMessage = ChatMessage(
      id: _nextMessageId(),
      role: MessageRole.user,
      content: visiblePrompt,
      timestampLabel: 'Now',
      attachments: attachments,
    );
    final isFirstMessageInSession = _state.messages.isEmpty;
    final bridgeReady =
        _bridgeClient != null &&
        _state.connectionStatus == ConnectionStatus.connected;
    final canReconnect = !bridgeReady && _createBridgeClient != null;

    _state = _state.copyWith(
      messages: [..._state.messages, userMessage],
      sessions: isFirstMessageInSession
          ? _updateActiveSession(
              (session) => session.copyWith(
                title: _sessionTitleForPrompt(visiblePrompt),
                updatedLabel: 'Now',
              ),
            )
          : _state.sessions,
      activeExtensions: const ActiveExtensionsState(),
      isStreaming: bridgeReady || canReconnect,
      connectionStatus: bridgeReady
          ? ConnectionStatus.connected
          : canReconnect
          ? ConnectionStatus.connecting
          : ConnectionStatus.error,
      errorMessage: bridgeReady || canReconnect
          ? null
          : 'The app bridge is not connected. Start app-bridge and reconnect.',
      clearErrorMessage: bridgeReady || canReconnect,
      retrievedContextItems: nextRetrievedContextItems,
      inspector: attachmentContextItems.isEmpty
          ? null
          : const InspectorSelection(kind: InspectorKind.context),
    );
    notifyListeners();
    _persistState();

    if (bridgeReady) {
      _sendPromptToBridge(
        requestId: requestId,
        prompt: bridgePrompt,
        transcript: transcript,
      );
      return;
    }
    if (canReconnect) {
      _pendingBridgeStart = _PendingBridgeStart(
        requestId: requestId,
        prompt: bridgePrompt,
        transcript: transcript,
      );
      reconnectBridge();
      return;
    }
  }

  String _attachmentOnlyPrompt(List<ChatAttachment> attachments) {
    return attachments.length == 1
        ? 'Review the attached file.'
        : 'Review the attached files.';
  }

  List<RetrievedContextItem> _attachmentContextItems(
    List<ChatAttachment> attachments,
  ) {
    if (attachments.isEmpty) return const [];
    return [
      for (final attachment in attachments)
        RetrievedContextItem(
          source: 'attachment',
          title: attachment.name,
          content: _attachmentContextContent(attachment),
          score: 1,
        ),
    ];
  }

  String _attachmentContextContent(ChatAttachment attachment) {
    final lines = <String>[
      '${_attachmentKindLabel(attachment.kind)} attachment',
      'Size: ${_formatAttachmentSize(attachment.sizeBytes)}',
    ];
    final mimeType = attachment.mimeType.trim();
    if (mimeType.isNotEmpty) {
      lines.add('MIME: $mimeType');
    }
    final path = attachment.path?.trim();
    if (path != null && path.isNotEmpty) {
      lines.add('Path: $path');
    }
    final content = attachment.content?.trim();
    if (content != null && content.isNotEmpty) {
      final preview = content.length <= 320
          ? content
          : '${content.substring(0, 320)}...';
      lines
        ..add('Preview:')
        ..add(preview);
    }
    return lines.join('\n');
  }

  String _attachmentKindLabel(ChatAttachmentKind kind) {
    return switch (kind) {
      ChatAttachmentKind.image => 'Image',
      ChatAttachmentKind.text => 'Text',
      ChatAttachmentKind.file => 'File',
    };
  }

  String _formatAttachmentSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kilobytes = bytes / 1024;
    if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} KB';
    final megabytes = kilobytes / 1024;
    return '${megabytes.toStringAsFixed(1)} MB';
  }

  String _bridgePromptWithWorkspaceContext(String prompt) {
    final cwd = _activeWorkingDirectory.trim();
    if (cwd.isEmpty) return prompt;
    return [
      '<openclaude_context>',
      'Current workspace directory: $cwd',
      'Use this as the active project directory for file and shell operations.',
      '</openclaude_context>',
      '',
      prompt,
    ].join('\n');
  }

  String _bridgePromptWithAttachments(
    String prompt,
    List<ChatAttachment> attachments,
  ) {
    if (attachments.isEmpty) return prompt;
    return [
      prompt,
      '',
      '<attachments>',
      for (final attachment in attachments) _attachmentPromptBlock(attachment),
      '</attachments>',
    ].join('\n');
  }

  String _attachmentPromptBlock(ChatAttachment attachment) {
    final content = _attachmentPromptContent(attachment);
    final attributes = [
      'name="${_promptAttribute(attachment.name)}"',
      'kind="${attachment.kind.name}"',
      if (attachment.mimeType.trim().isNotEmpty)
        'mimeType="${_promptAttribute(attachment.mimeType)}"',
      'sizeBytes="${attachment.sizeBytes}"',
      if (attachment.path?.trim().isNotEmpty == true)
        'path="${_promptAttribute(attachment.path!.trim())}"',
    ].join(' ');
    return ['<attachment $attributes>', content, '</attachment>'].join('\n');
  }

  String _attachmentPromptContent(ChatAttachment attachment) {
    final content = attachment.content?.trim();
    if (content != null && content.isNotEmpty) {
      if (content.length <= _maxAttachmentPromptCharacters) return content;
      return '${content.substring(0, _maxAttachmentPromptCharacters)}\n[Attachment preview truncated]';
    }
    final path = attachment.path?.trim();
    return switch (attachment.kind) {
      ChatAttachmentKind.image =>
        path == null || path.isEmpty
            ? 'Image attachment metadata is available, but no local path was provided.'
            : 'Image attachment is available at: $path',
      ChatAttachmentKind.text => 'Text attachment has no readable preview.',
      ChatAttachmentKind.file =>
        path == null || path.isEmpty
            ? 'File attachment metadata is available, but no local path was provided.'
            : 'File attachment is available at: $path',
    };
  }

  String _promptAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  String _bridgePromptForSlashSkill(String prompt) {
    final slash = _parseSlashSkillPrompt(prompt);
    if (slash == null) return prompt;
    final skill = _enabledSkillForSlashName(slash.name);
    if (skill == null) return prompt;
    final request = slash.request.isEmpty
        ? 'Follow the skill instructions for this turn.'
        : slash.request;
    return '''
Use the "${skill.name}" skill for this request.

Skill description:
${skill.description}

User request:
$request
'''
        .trim();
  }

  _SlashSkillPrompt? _parseSlashSkillPrompt(String prompt) {
    if (!prompt.startsWith('/')) return null;
    final separator = prompt.indexOf(RegExp(r'\s'));
    final command = separator == -1
        ? prompt.substring(1)
        : prompt.substring(1, separator);
    if (command.isEmpty) return null;
    final request = separator == -1 ? '' : prompt.substring(separator).trim();
    return _SlashSkillPrompt(command.toLowerCase(), request);
  }

  SkillSummary? _enabledSkillForSlashName(String slashName) {
    for (final skill in _state.extensions.skills) {
      if (skill.status.toLowerCase() != 'enabled') continue;
      final names = {
        _slashNameForSkillValue(skill.name),
        _slashNameForSkillValue(skill.id),
      };
      if (names.contains(slashName)) return skill;
    }
    return null;
  }

  String _slashNameForSkillValue(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), '-').toLowerCase();
  }

  void stopStreaming() {
    _cancelActiveBridgeTurn();
    _state = _state.copyWith(isStreaming: false);
    notifyListeners();
  }

  void _cancelActiveBridgeTurn() {
    final requestId = _activeRequestId;
    if (requestId != null) {
      _bridgeClient?.interrupt(requestId);
    }
    _activeRequestId = null;
    _resetActiveStreamCounters();
    _resetStreamingAssistantDraft();
    _pendingBridgeStart = null;
  }

  void reconnectBridge() {
    final nextBridgeUrl = _state.bridgeUrl.trim();
    if (nextBridgeUrl.isEmpty) return;
    _cancelScheduledBridgeReconnect();

    final createBridgeClient = _createBridgeClient;
    if (createBridgeClient == null) {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:
            'No app bridge client factory is available. Restart the app.',
        diagnosticLogs: _prependDiagnostic(
          DiagnosticSeverity.error,
          'Bridge reconnect unavailable',
          'No app bridge client factory is available. Restart the app.',
        ),
      );
      notifyListeners();
      return;
    }

    final previousBridgeClient = _bridgeClient;
    final previousSubscription = _bridgeSubscription;
    final nextBridgeClient = createBridgeClient(nextBridgeUrl);
    _bridgeClient = nextBridgeClient;
    _bridgeSubscription = _listenToBridgeClient(nextBridgeClient);
    unawaited(previousSubscription?.cancel());
    unawaited(previousBridgeClient?.close());

    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.connecting,
      bridgeUrl: nextBridgeUrl,
      provider: _state.provider.copyWith(bridgeUrl: nextBridgeUrl),
      diagnosticLogs: _prependDiagnostic(
        DiagnosticSeverity.info,
        'Bridge reconnect started',
        'Connecting to $nextBridgeUrl.',
      ),
      clearErrorMessage: true,
    );
    notifyListeners();
    _persistState();
  }

  Future<void> startLocalBridge({
    BridgeReconnectStrategy strategy = BridgeReconnectStrategy.switchPort,
  }) async {
    final launcher = _bridgeProcessLauncher;
    if (launcher == null || !launcher.canStart) {
      _state = _state.copyWith(
        bridgeLaunchStatus: BridgeLaunchStatus.unsupported,
        diagnosticLogs: _prependDiagnostic(
          DiagnosticSeverity.warning,
          'Bridge launch unavailable',
          'Local app-bridge launch is available only in desktop builds. Start app-bridge manually and reconnect.',
        ),
      );
      notifyListeners();
      return;
    }

    _state = _state.copyWith(
      bridgeLaunchStatus: BridgeLaunchStatus.starting,
      diagnosticLogs: _prependDiagnostic(
        DiagnosticSeverity.info,
        'Bridge launch started',
        strategy == BridgeReconnectStrategy.switchPort
            ? 'Starting local app-bridge on an internal fallback port.'
            : 'Starting local app-bridge on the managed internal endpoint.',
      ),
      clearErrorMessage: true,
    );
    notifyListeners();

    try {
      final result = await launcher.start(
        preferredBridgeUrl: _state.bridgeUrl,
        strategy: strategy,
        agentEvalTraceEnabled: _state.personal.agentEvalTraceEnabled,
      );
      if (!result.started) {
        _state = _state.copyWith(
          bridgeLaunchStatus: BridgeLaunchStatus.failed,
          errorMessage: _redactSensitiveText(result.message),
          diagnosticLogs: _prependDiagnostic(
            DiagnosticSeverity.error,
            'Bridge launch failed',
            result.message,
          ),
        );
        notifyListeners();
        return;
      }

      final resultBridgeUrl = result.bridgeUrl?.trim();
      final nextBridgeUrl = resultBridgeUrl == null || resultBridgeUrl.isEmpty
          ? _state.bridgeUrl
          : resultBridgeUrl;
      final pidSuffix = result.pid == null ? '' : ' PID ${result.pid}.';
      _state = _state.copyWith(
        bridgeLaunchStatus: BridgeLaunchStatus.started,
        bridgeUrl: nextBridgeUrl,
        provider: _state.provider.copyWith(bridgeUrl: nextBridgeUrl),
        diagnosticLogs: _prependDiagnostic(
          DiagnosticSeverity.success,
          'Bridge launched',
          '${result.message}$pidSuffix',
        ),
        clearErrorMessage: true,
      );
      notifyListeners();
      reconnectBridge();
    } catch (error) {
      final redactedMessage = _redactSensitiveText('$error');
      _state = _state.copyWith(
        bridgeLaunchStatus: BridgeLaunchStatus.failed,
        errorMessage: redactedMessage,
        diagnosticLogs: _prependDiagnostic(
          DiagnosticSeverity.error,
          'Bridge launch failed',
          redactedMessage,
        ),
      );
      notifyListeners();
    }
  }

  String diagnosticsReport() {
    final lines = <String>[
      '$appDisplayName Diagnostics Report',
      'Bridge endpoint: managed internally',
      'Connection: ${_state.connectionStatus.name}',
      'Launcher: ${_state.bridgeLaunchStatus.name}',
      'Provider: ${_state.provider.providerName}',
      'Model: ${_state.provider.modelName}',
      'API key: ${_state.provider.apiKeyConfigured ? 'configured' : 'missing'}',
      'Workspace: $_activeWorkingDirectory',
      'Setup assistant dismissed: ${_state.setupAssistantDismissed}',
      '',
      'Recent turn timeline:',
      for (final entry in _state.turnTimeline.take(12))
        '- [${entry.status}] ${entry.stageLabel}${entry.durationLabel.isEmpty ? '' : ' (${entry.durationLabel})'}: ${entry.detail ?? ''}',
      '',
      'Recent diagnostics:',
      for (final entry in _state.diagnosticLogs.take(10))
        '- [${entry.severity.name}] ${entry.title}: ${entry.detail}',
    ];
    return _redactSensitiveText(lines.join('\n'));
  }

  Future<void> copyDiagnosticsReport() async {
    try {
      await _copyText(diagnosticsReport());
      _state = _state.copyWith(
        diagnosticsReportCopyStatus: DiagnosticsReportCopyStatus.copied,
        diagnosticLogs: _prependDiagnostic(
          DiagnosticSeverity.success,
          'Diagnostics report copied',
          'A redacted diagnostics report was copied to the clipboard.',
        ),
      );
    } catch (error) {
      final redactedMessage = _redactSensitiveText('$error');
      _state = _state.copyWith(
        diagnosticsReportCopyStatus: DiagnosticsReportCopyStatus.failed,
        diagnosticLogs: _prependDiagnostic(
          DiagnosticSeverity.error,
          'Diagnostics report copy failed',
          redactedMessage,
        ),
      );
    }
    notifyListeners();
  }

  void selectDestination(WorkbenchDestination destination) {
    if (destination == WorkbenchDestination.extensions) {
      _loadExtensionsInventory(destination: destination);
      return;
    }
    _state = _state.copyWith(destination: destination);
    notifyListeners();
  }

  void refreshExtensionsInventory() {
    _loadExtensionsInventory();
  }

  void importSkill(String path) {
    final skillPath = path.trim();
    if (skillPath.isEmpty) return;
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:
            'No app bridge is connected. Start app-bridge and reconnect.',
      );
      notifyListeners();
      return;
    }

    bridgeClient.importSkill(requestId: _nextRequestId(), path: skillPath);
    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  void setSkillEnabled(String skillId, bool enabled) {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:
            'No app bridge is connected. Start app-bridge and reconnect.',
      );
      notifyListeners();
      return;
    }

    bridgeClient.setSkillEnabled(
      requestId: _nextRequestId(),
      skillId: skillId,
      enabled: enabled,
    );
    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  void refreshSkills() {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:
            'No app bridge is connected. Start app-bridge and reconnect.',
      );
      notifyListeners();
      return;
    }

    final requestId = _nextRequestId();
    _activeSkillsListRequestId = requestId;
    _state = _state.copyWith(
      extensions: _state.extensions.copyWith(
        skillsStatus: ExtensionInventoryStatus.loading,
        clearSkillsErrorMessage: true,
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
    bridgeClient.refreshSkills(requestId: requestId);
    notifyListeners();
  }

  void _ensureSkillsInventoryLoaded() {
    if (_state.extensions.skillsStatus != ExtensionInventoryStatus.idle) {
      return;
    }
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) return;

    final requestId = _nextRequestId();
    _activeSkillsListRequestId = requestId;
    _state = _state.copyWith(
      extensions: _state.extensions.copyWith(
        skillsStatus: ExtensionInventoryStatus.loading,
        clearSkillsErrorMessage: true,
      ),
    );
    bridgeClient.listSkills(requestId: requestId, includeDisabled: true);
  }

  void saveMcpServer(McpServerDraft server) {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:
            'No app bridge is connected. Start app-bridge and reconnect.',
      );
      notifyListeners();
      return;
    }

    bridgeClient.saveMcpServer(
      requestId: _nextRequestId(),
      cwd: _activeWorkingDirectory,
      server: BridgeMcpServerDraft(
        id: server.id,
        name: server.name,
        transport: server.transport,
        scope: server.scope,
        command: server.command,
        args: server.args,
        url: server.url,
        headers: server.headers,
        env: server.env,
        enabled: server.enabled,
      ),
    );
    final testResults = {..._state.extensions.mcpTestResults};
    if (server.id != null) {
      testResults.remove(server.id);
    }
    _state = _state.copyWith(
      extensions: _state.extensions.copyWith(mcpTestResults: testResults),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  void setMcpServerEnabled(String serverId, bool enabled) {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:
            'No app bridge is connected. Start app-bridge and reconnect.',
      );
      notifyListeners();
      return;
    }

    bridgeClient.setMcpServerEnabled(
      requestId: _nextRequestId(),
      cwd: _activeWorkingDirectory,
      serverId: serverId,
      enabled: enabled,
    );
    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  void deleteMcpServer(String serverId) {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:
            'No app bridge is connected. Start app-bridge and reconnect.',
      );
      notifyListeners();
      return;
    }

    bridgeClient.deleteMcpServer(
      requestId: _nextRequestId(),
      cwd: _activeWorkingDirectory,
      serverId: serverId,
    );
    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  void testMcpServer(McpServerDraft server) {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:
            'No app bridge is connected. Start app-bridge and reconnect.',
      );
      notifyListeners();
      return;
    }

    final serverId = _mcpServerIdForDraft(server);
    final requestId = _nextRequestId();
    bridgeClient.testMcpServer(
      requestId: requestId,
      cwd: _activeWorkingDirectory,
      server: BridgeMcpServerDraft(
        id: server.id,
        name: server.name,
        transport: server.transport,
        scope: server.scope,
        command: server.command,
        args: server.args,
        url: server.url,
        headers: server.headers,
        env: server.env,
        enabled: server.enabled,
      ),
    );
    _state = _state.copyWith(
      extensions: _state.extensions.copyWith(
        mcpTestResults: {
          ..._state.extensions.mcpTestResults,
          serverId: McpConnectionTestResult(
            serverId: serverId,
            status: 'testing',
            message: 'Testing connection',
            durationMs: 0,
            checkedAt: '',
          ),
        },
        clearMcpErrorMessage: true,
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  void selectSession(String sessionId) {
    if (_state.activeSessionId == sessionId) return;
    _rememberActiveMessages();
    _cancelActiveBridgeTurn();
    _state = _state.copyWith(
      activeSessionId: sessionId,
      messages: _messagesBySessionId[sessionId] ?? const [],
      toolRuns: const [],
      permissionRequests: const [],
      retrievedContextItems: const [],
      learningCandidates: const [],
      activeExtensions: const ActiveExtensionsState(),
      inspector: const InspectorSelection(kind: InspectorKind.context),
      isStreaming: false,
      sessions: [
        for (final session in _state.sessions)
          if (session.id == sessionId)
            session.copyWith(clearSdkSessionId: true)
          else
            session,
      ],
    );
    notifyListeners();
    _persistState();
  }

  void updateSessionSearchQuery(String query) {
    _state = _state.copyWith(sessionSearchQuery: query);
    notifyListeners();
  }

  void dismissSetupAssistant() {
    _state = _state.copyWith(setupAssistantDismissed: true);
    notifyListeners();
    _persistState();
  }

  Future<void> chooseProjectDirectory() async {
    final picker = _projectDirectoryPicker;
    if (picker == null) {
      _state = _state.copyWith(
        diagnosticLogs: _prependDiagnostic(
          DiagnosticSeverity.warning,
          'Project directory picker unavailable',
          'This platform does not expose a directory picker.',
        ),
      );
      notifyListeners();
      return;
    }

    try {
      final directory = await picker();
      if (directory == null) {
        _state = _state.copyWith(
          errorMessage:
              'No project directory selected. On web, enter an absolute path in Settings.',
          diagnosticLogs: _prependDiagnostic(
            DiagnosticSeverity.warning,
            'Project directory not selected',
            'The picker was cancelled or is unavailable in this build.',
          ),
        );
        notifyListeners();
        return;
      }
      bindProjectDirectory(directory);
    } catch (error) {
      final redactedMessage = _redactSensitiveText('$error');
      _state = _state.copyWith(
        diagnosticLogs: _prependDiagnostic(
          DiagnosticSeverity.error,
          'Project directory selection failed',
          redactedMessage,
        ),
      );
      notifyListeners();
    }
  }

  void bindProjectDirectory(String directory) {
    final path = directory.trim();
    if (path.isEmpty) return;

    final isSameProject = _activeWorkingDirectory.trim() == path;
    _rememberActiveMessages();
    if (isSameProject) {
      _state = _state.copyWith(
        personal: _state.personal.copyWith(defaultWorkingDirectory: path),
        sessions: _updateActiveSession(
          (session) => session.copyWith(subtitle: path, updatedLabel: 'Now'),
        ),
        diagnosticLogs: _prependDiagnostic(
          DiagnosticSeverity.success,
          'Project directory selected',
          'Current session workspace is $path.',
        ),
        clearErrorMessage: true,
      );
      notifyListeners();
      _persistState();
      return;
    }

    _cancelActiveBridgeTurn();
    final id = _nextSessionId();
    final session = SessionSummary(
      id: id,
      title: _projectTitleForPath(path),
      subtitle: path,
      status: SessionStatus.idle,
      updatedLabel: 'Now',
    );
    _state = _state.copyWith(
      personal: _state.personal.copyWith(defaultWorkingDirectory: path),
      sessions: [session, ..._state.sessions],
      activeSessionId: id,
      messages: const [],
      toolRuns: const [],
      permissionRequests: const [],
      retrievedContextItems: const [],
      learningCandidates: const [],
      activeExtensions: const ActiveExtensionsState(),
      destination: WorkbenchDestination.chat,
      inspector: const InspectorSelection(kind: InspectorKind.context),
      isStreaming: false,
      diagnosticLogs: _prependDiagnostic(
        DiagnosticSeverity.success,
        'Project opened',
        'Current session workspace is $path.',
      ),
      clearErrorMessage: true,
    );
    _messagesBySessionId[id] = const [];
    notifyListeners();
    _persistState();
  }

  String _projectTitleForPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final lastSeparator = trimmed.lastIndexOf('/');
    final title = lastSeparator >= 0
        ? trimmed.substring(lastSeparator + 1)
        : trimmed;
    return title.isEmpty ? path : title;
  }

  void newSession() {
    _rememberActiveMessages();
    _cancelActiveBridgeTurn();
    final id = _nextSessionId();
    final session = SessionSummary(
      id: id,
      title: 'New chat',
      subtitle: _activeWorkingDirectory,
      status: SessionStatus.idle,
      updatedLabel: 'Now',
    );
    _state = _state.copyWith(
      sessions: [session, ..._state.sessions],
      activeSessionId: id,
      messages: const [],
      toolRuns: const [],
      permissionRequests: const [],
      retrievedContextItems: const [],
      learningCandidates: const [],
      activeExtensions: const ActiveExtensionsState(),
      destination: WorkbenchDestination.chat,
      inspector: const InspectorSelection(kind: InspectorKind.context),
      isStreaming: false,
    );
    _messagesBySessionId[id] = const [];
    notifyListeners();
    _persistState();
  }

  void deleteSession(String sessionId) {
    final index = _state.sessions.indexWhere(
      (session) => session.id == sessionId,
    );
    if (index == -1) return;

    final deletingActiveSession = _state.activeSessionId == sessionId;
    _rememberActiveMessages();
    final deletedWorkingDirectory = deletingActiveSession
        ? _activeWorkingDirectory
        : null;
    final remainingSessions = [
      for (final session in _state.sessions)
        if (session.id != sessionId) session,
    ];

    if (!deletingActiveSession) {
      _messagesBySessionId.remove(sessionId);
      _state = _state.copyWith(sessions: remainingSessions);
      notifyListeners();
      _persistState();
      return;
    }

    _cancelActiveBridgeTurn();
    final nextSession = remainingSessions.isEmpty
        ? SessionSummary(
            id: _nextSessionId(excluding: {sessionId}),
            title: 'New chat',
            subtitle:
                deletedWorkingDirectory ??
                _state.personal.defaultWorkingDirectory,
            status: SessionStatus.idle,
            updatedLabel: 'Now',
          )
        : remainingSessions.first.copyWith(clearSdkSessionId: true);
    final nextSessions = remainingSessions.isEmpty
        ? [nextSession]
        : [nextSession, ...remainingSessions.skip(1)];

    _messagesBySessionId.remove(sessionId);
    final nextMessages = _messagesBySessionId[nextSession.id] ?? const [];
    _state = _state.copyWith(
      sessions: nextSessions,
      activeSessionId: nextSession.id,
      messages: nextMessages,
      toolRuns: const [],
      permissionRequests: const [],
      retrievedContextItems: const [],
      learningCandidates: const [],
      activeExtensions: const ActiveExtensionsState(),
      destination: WorkbenchDestination.chat,
      inspector: const InspectorSelection(kind: InspectorKind.context),
      isStreaming: false,
    );
    _messagesBySessionId[nextSession.id] = nextMessages;
    notifyListeners();
    _persistState();
  }

  String _nextSessionId({Set<String> excluding = const {}}) {
    var index = _state.sessions.length + 1;
    while (_state.sessions.any((session) => session.id == 'session-$index') ||
        excluding.contains('session-$index')) {
      index += 1;
    }
    return 'session-$index';
  }

  void selectMessage(String messageId) {
    _state = _state.copyWith(
      inspector: InspectorSelection(
        kind: InspectorKind.message,
        itemId: messageId,
      ),
    );
    notifyListeners();
    _persistState();
  }

  void selectTool(String toolRunId) {
    _state = _state.copyWith(
      inspector: InspectorSelection(
        kind: InspectorKind.tool,
        itemId: toolRunId,
      ),
    );
    notifyListeners();
    _persistState();
  }

  void indexKnowledgePath(KnowledgeIndexRequest request) {
    final path = request.path.trim();
    if (path.isEmpty) return;

    final requestId = _nextRequestId();
    _activeKnowledgeIndexRequestId = requestId;
    final target = request.target;
    _state = _state.copyWith(
      knowledgeIndex: _state.knowledgeIndex.copyWith(
        target: target,
        path: path,
        status: KnowledgeIndexStatus.indexing,
        indexedNodes: 0,
        sourcePaths: const [],
        clearErrorMessage: true,
      ),
      connectionStatus: _bridgeClient == null
          ? ConnectionStatus.error
          : ConnectionStatus.connected,
      errorMessage: _bridgeClient == null
          ? 'No app bridge is connected. Start app-bridge and reconnect.'
          : null,
      clearErrorMessage: _bridgeClient != null,
    );
    notifyListeners();

    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _activeKnowledgeIndexRequestId = null;
      _state = _state.copyWith(
        knowledgeIndex: _state.knowledgeIndex.copyWith(
          status: KnowledgeIndexStatus.failed,
          errorMessage: 'No app bridge is connected.',
        ),
      );
      notifyListeners();
      return;
    }

    bridgeClient.indexContext(
      requestId: requestId,
      cwd: _activeWorkingDirectory,
      target: _bridgeTargetForKnowledgeTarget(target),
      path: path,
      metadata: const {'source': 'agent-workbench'},
    );
  }

  void refreshMemoryFacts() {
    final requestId = _nextRequestId();
    _activeMemoryFactsRequestId = requestId;
    _state = _state.copyWith(
      connectionStatus: _bridgeClient == null
          ? ConnectionStatus.error
          : ConnectionStatus.connected,
      errorMessage: _bridgeClient == null
          ? 'No app bridge is connected. Start app-bridge and reconnect.'
          : null,
      clearErrorMessage: _bridgeClient != null,
    );
    notifyListeners();

    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _activeMemoryFactsRequestId = null;
      return;
    }

    bridgeClient.listContextFacts(
      requestId: requestId,
      cwd: _activeWorkingDirectory,
      sources: const ['profile', 'habit', 'graph'],
    );
  }

  void runRetrievalEvaluation() {
    final requestId = _nextRequestId();
    _activeRetrievalEvaluationRequestId = requestId;
    _state = _state.copyWith(
      retrievalEvaluation: _state.retrievalEvaluation.copyWith(
        status: RetrievalEvaluationStatus.running,
        clearErrorMessage: true,
      ),
      connectionStatus: _bridgeClient == null
          ? ConnectionStatus.error
          : ConnectionStatus.connected,
      errorMessage: _bridgeClient == null
          ? 'No app bridge is connected. Start app-bridge and reconnect.'
          : null,
      clearErrorMessage: _bridgeClient != null,
    );
    notifyListeners();

    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _activeRetrievalEvaluationRequestId = null;
      _state = _state.copyWith(
        retrievalEvaluation: _state.retrievalEvaluation.copyWith(
          status: RetrievalEvaluationStatus.failed,
          errorMessage: 'No app bridge is connected.',
        ),
      );
      notifyListeners();
      return;
    }

    bridgeClient.evaluateContext(
      requestId: requestId,
      cwd: _activeWorkingDirectory,
      k: 5,
      maxItems: 5,
      sources: const ['hybrid', 'document', 'profile', 'habit', 'graph'],
      cases: _evaluationCasesForState(),
    );
  }

  void updateMemoryFact(
    String source,
    String id, {
    required String title,
    required String content,
  }) {
    final memoryFact = _memoryFactById(source, id);
    if (memoryFact == null) return;
    final fact = _factWithMemoryText(memoryFact, title, content);
    _upsertMemoryFact(
      source: source,
      id: id,
      fact: fact,
      localUpdate: (value) =>
          value.copyWith(title: title, content: content, fact: fact),
    );
  }

  void setMemoryFactDisabled(String source, String id, bool disabled) {
    final memoryFact = _memoryFactById(source, id);
    if (memoryFact == null) return;
    final fact = _factWithDisabledState(memoryFact.fact, disabled);
    _upsertMemoryFact(
      source: source,
      id: id,
      fact: fact,
      localUpdate: (value) => value.copyWith(disabled: disabled, fact: fact),
    );
  }

  void deleteMemoryFact(String source, String id) {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:
            'No app bridge is connected. Start app-bridge and reconnect.',
      );
      notifyListeners();
      return;
    }

    bridgeClient.deleteContextFact(
      requestId: _nextRequestId(),
      cwd: _activeWorkingDirectory,
      source: source,
      id: id,
    );
  }

  void updateProvider(ProviderSettings provider) {
    _state = _state.copyWith(
      provider: provider.copyWith(bridgeUrl: _state.bridgeUrl),
      inspector: const InspectorSelection(kind: InspectorKind.settings),
    );
    notifyListeners();
    _persistState();
  }

  void submitApiKey(String apiKey) {
    if (apiKey.trim().isEmpty) return;
    _state = _state.copyWith(
      provider: _state.provider.copyWith(apiKeyConfigured: true),
      inspector: const InspectorSelection(kind: InspectorKind.settings),
    );
    notifyListeners();
    _persistState();
  }

  void testProviderConnection(ProviderConnectionRequest request) {
    final apiKey = request.apiKey.trim();
    if (apiKey.isEmpty) return;

    _apiKeysByRoute[request.routeKey] = apiKey;
    _state = _state.copyWith(
      provider: _state.provider.copyWith(
        providerName: request.providerName,
        modelName: request.modelName,
        baseUrl: request.baseUrl,
        bridgeUrl: _state.bridgeUrl,
        apiKeyConfigured: true,
      ),
      inspector: const InspectorSelection(kind: InspectorKind.settings),
    );
    notifyListeners();
    _persistState();
  }

  ProviderConnectionRequest? connectionRequestForCurrentProvider() {
    final provider = _state.provider;
    final routeKey =
        '${provider.providerName}::${provider.modelName}::${provider.baseUrl}';
    final apiKey = _apiKeysByRoute[routeKey];
    if (apiKey == null) return null;
    return ProviderConnectionRequest(
      providerName: provider.providerName,
      modelName: provider.modelName,
      baseUrl: provider.baseUrl,
      apiKey: apiKey,
    );
  }

  void updatePersonal(PersonalSettings personal) {
    final previousTraceEnabled = _state.personal.agentEvalTraceEnabled;
    final directory = personal.defaultWorkingDirectory.trim();
    final shouldBindDirectory =
        directory.isNotEmpty &&
        directory != _state.personal.defaultWorkingDirectory.trim();
    if (shouldBindDirectory) {
      _cancelActiveBridgeTurn();
    }
    _state = _state.copyWith(
      personal: shouldBindDirectory
          ? personal.copyWith(defaultWorkingDirectory: directory)
          : personal,
      sessions: shouldBindDirectory
          ? _updateActiveSession(
              (session) => session.copyWith(
                subtitle: directory,
                updatedLabel: 'Now',
                clearSdkSessionId: true,
              ),
            )
          : _state.sessions,
      inspector: const InspectorSelection(kind: InspectorKind.settings),
      messages: shouldBindDirectory ? const [] : null,
      toolRuns: shouldBindDirectory ? const [] : null,
      permissionRequests: shouldBindDirectory ? const [] : null,
      retrievedContextItems: shouldBindDirectory ? const [] : null,
      learningCandidates: shouldBindDirectory ? const [] : null,
      activeExtensions: shouldBindDirectory
          ? const ActiveExtensionsState()
          : null,
      isStreaming: shouldBindDirectory ? false : null,
    );
    notifyListeners();
    _persistState();
    if (previousTraceEnabled != personal.agentEvalTraceEnabled) {
      _syncAgentEvalTraceSetting(force: true);
    }
  }

  void respondToPermission({
    required String requestId,
    required String toolUseId,
    required String decision,
  }) {
    if (decision == _permissionDecisionAllowAll) {
      _allowAllToolPermissionSessionIds.add(_state.activeSessionId);
    }
    final isAllowed = _isAllowedPermissionDecision(decision);
    _bridgeClient?.respondToPermission(
      requestId: requestId,
      toolUseId: toolUseId,
      decision: {'behavior': decision},
    );
    _state = _state.copyWith(
      permissionRequests: [
        for (final request in _state.permissionRequests)
          if (request.requestId != requestId || request.toolUseId != toolUseId)
            request,
      ],
      toolRuns: _updateToolRun(
        toolUseId,
        (run) => run.copyWith(
          status: isAllowed ? ToolRunStatus.running : ToolRunStatus.error,
          summary: isAllowed
              ? 'Executing approved command'
              : 'Permission denied',
        ),
      ),
    );
    notifyListeners();
  }

  void _handleBridgeMessage(BridgeServerMessage message) {
    switch (message) {
      case BridgeHelloMessage():
        _cancelScheduledBridgeReconnect();
        final hasPendingBridgeStart = _pendingBridgeStart != null;
        _state = _state.copyWith(
          connectionStatus: ConnectionStatus.connected,
          diagnosticLogs: _prependDiagnostic(
            DiagnosticSeverity.success,
            'Bridge connected',
            'Connected to ${_state.bridgeUrl}.',
          ),
          clearErrorMessage: true,
        );
        if (!hasPendingBridgeStart) {
          _ensureSkillsInventoryLoaded();
        }
        _syncAgentEvalTraceSetting();
        _sendPendingBridgeStart();
      case BridgeTurnTimelineMessage():
        _handleTurnTimelineMessage(message);
      case BridgeExtensionRuntimeMessage():
        _handleExtensionRuntimeMessage(message);
      case BridgeAgentEvalTraceStatusMessage():
        _handleAgentEvalTraceStatusMessage(message);
      case BridgeSdkMessage():
        _handleSdkMessage(message);
      case BridgeContextRetrievalMessage():
        _handleContextRetrievalMessage(message);
      case BridgeContextEvaluationResultMessage():
        _handleContextEvaluationResultMessage(message);
      case BridgeContextEvaluationErrorMessage():
        _handleContextEvaluationErrorMessage(message);
      case BridgeContextLearnResultMessage():
        _handleContextLearnResultMessage(message);
      case BridgeContextLearnErrorMessage():
        _handleContextLearnErrorMessage(message);
      case BridgeContextIndexProgressMessage():
        _handleContextIndexProgressMessage(message);
      case BridgeContextIndexResultMessage():
        _handleContextIndexResultMessage(message);
      case BridgeContextIndexErrorMessage():
        _handleContextIndexErrorMessage(message);
      case BridgeContextFactUpsertResultMessage():
        _handleContextFactUpsertResultMessage(message);
      case BridgeContextFactUpsertErrorMessage():
        _handleContextFactUpsertErrorMessage(message);
      case BridgeContextFactsListResultMessage():
        _handleContextFactsListResultMessage(message);
      case BridgeContextFactsListErrorMessage():
        _handleContextFactsListErrorMessage(message);
      case BridgeContextFactDeleteResultMessage():
        _handleContextFactDeleteResultMessage(message);
      case BridgeContextFactDeleteErrorMessage():
        _handleContextFactDeleteErrorMessage(message);
      case BridgeSkillsSnapshotMessage():
        _handleSkillsSnapshotMessage(message);
      case BridgeSkillImportedMessage():
        _handleSkillImportedMessage(message);
      case BridgeSkillUpdatedMessage():
        _handleSkillUpdatedMessage(message);
      case BridgeMcpServersSnapshotMessage():
        _handleMcpServersSnapshotMessage(message);
      case BridgeMcpServerCapabilitiesMessage():
        _handleMcpServerCapabilitiesMessage(message);
      case BridgeMcpServerTestResultMessage():
        _handleMcpServerTestResultMessage(message);
      case BridgeMcpServerSavedMessage():
        _handleMcpServerSavedMessage(message);
      case BridgeMcpServerDeletedMessage():
        _handleMcpServerDeletedMessage(message);
      case BridgeErrorMessage():
        _handleBridgeErrorMessage(message);
      case BridgeClosedMessage():
        _activeRequestId = null;
        _resetActiveStreamCounters();
        _resetStreamingAssistantDraft();
        _state = _state.copyWith(
          isStreaming: false,
          connectionStatus: ConnectionStatus.disconnected,
          diagnosticLogs: _prependDiagnostic(
            DiagnosticSeverity.warning,
            'Bridge session closed',
            'The active bridge session was closed.',
          ),
        );
    }
    notifyListeners();
  }

  void _handleTurnTimelineMessage(BridgeTurnTimelineMessage message) {
    final entry = TurnTimelineEntry(
      id: 'timeline-${++_timelineCounter}',
      requestId: message.requestId,
      stage: message.stage,
      status: message.status,
      timestamp: message.at.isEmpty ? 'Now' : message.at,
      durationMs: message.durationMs,
      detail: message.detail == null
          ? null
          : _redactSensitiveText(message.detail!),
      toolName: message.toolName,
      toolUseId: message.toolUseId,
    );
    final nextTimeline = [entry, ..._state.turnTimeline].take(80).toList();
    final shouldLog = entry.status != 'started';
    _state = _state.copyWith(
      turnTimeline: nextTimeline,
      diagnosticLogs: shouldLog
          ? _prependDiagnostic(
              _timelineSeverity(entry),
              'Timeline: ${entry.stageLabel}',
              _timelineLogDetail(entry),
            )
          : _state.diagnosticLogs,
    );
  }

  void _handleExtensionRuntimeMessage(BridgeExtensionRuntimeMessage message) {
    final previousWarnings = _state.activeExtensions.warnings;
    final newWarnings = [
      for (final warning in message.warnings)
        if (!previousWarnings.contains(warning)) warning,
    ];
    _state = _state.copyWith(
      activeExtensions: ActiveExtensionsState(
        mcpServers: message.mcpServers,
        skills: message.skills,
        warnings: message.warnings,
      ),
      connectionStatus: ConnectionStatus.connected,
      diagnosticLogs: newWarnings.isEmpty
          ? _state.diagnosticLogs
          : _prependDiagnostic(
              DiagnosticSeverity.warning,
              'Extension runtime warning',
              newWarnings.join('\n'),
            ),
    );
  }

  void _handleAgentEvalTraceStatusMessage(
    BridgeAgentEvalTraceStatusMessage message,
  ) {
    _state = _state.copyWith(
      diagnosticLogs: _prependDiagnostic(
        message.enabled ? DiagnosticSeverity.success : DiagnosticSeverity.info,
        message.enabled
            ? 'Agent eval trace enabled'
            : 'Agent eval trace disabled',
        message.enabled
            ? 'Trace output: ${message.tracePath}'
            : 'Real-turn trace recording is off.',
      ),
    );
  }

  void _syncAgentEvalTraceSetting({bool force = false}) {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null ||
        _state.connectionStatus != ConnectionStatus.connected) {
      return;
    }
    if (!force && !_state.personal.agentEvalTraceEnabled) return;
    bridgeClient.setAgentEvalTraceEnabled(
      requestId: _nextRequestId(),
      enabled: _state.personal.agentEvalTraceEnabled,
    );
  }

  void acceptLearningCandidate(String candidateId) {
    final candidate = _learningCandidateById(candidateId);
    if (candidate == null ||
        candidate.status == LearningCandidateStatus.saved) {
      return;
    }

    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:
            'No app bridge is connected. Start app-bridge and reconnect.',
      );
      notifyListeners();
      return;
    }

    final requestId = _nextRequestId();
    _learningUpsertRequestIds[requestId] = candidate.id;
    _state = _state.copyWith(
      learningCandidates: _updateLearningCandidate(
        candidate.id,
        (value) => value.copyWith(status: LearningCandidateStatus.saving),
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
    notifyListeners();

    bridgeClient.upsertContextFact(
      requestId: requestId,
      cwd: _activeWorkingDirectory,
      source: candidate.source,
      fact: candidate.fact,
    );
  }

  void dismissLearningCandidate(String candidateId) {
    _state = _state.copyWith(
      learningCandidates: _updateLearningCandidate(
        candidateId,
        (candidate) =>
            candidate.copyWith(status: LearningCandidateStatus.ignored),
      ),
    );
    notifyListeners();
  }

  bool _isRequestScopedBridgeError(String code) {
    return code == 'QUERY_FAILED' ||
        code == 'CONTEXT_RETRIEVAL_FAILED' ||
        code == 'CONTEXT_LEARN_FAILED' ||
        code == 'CONTEXT_EVAL_FAILED' ||
        code == 'CONTEXT_FACT_UPSERT_FAILED' ||
        code == 'CONTEXT_FACTS_LIST_FAILED' ||
        code == 'CONTEXT_FACT_DELETE_FAILED' ||
        code == 'SKILLS_LIST_FAILED' ||
        code == 'SKILL_IMPORT_FAILED' ||
        code == 'SKILL_SET_ENABLED_FAILED' ||
        code == 'SKILL_REFRESH_FAILED' ||
        code == 'MCP_SERVERS_LIST_FAILED' ||
        code == 'MCP_SERVER_CAPABILITIES_FAILED' ||
        code == 'MCP_SERVER_SAVE_FAILED' ||
        code == 'MCP_SERVER_SET_ENABLED_FAILED' ||
        code == 'MCP_SERVER_DELETE_FAILED' ||
        code == 'MCP_SERVER_TEST_FAILED';
  }

  void _handleBridgeError(Object error) {
    _activeRequestId = null;
    _resetActiveStreamCounters();
    _resetStreamingAssistantDraft();
    final redactedMessage = _redactSensitiveText('$error');
    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.error,
      errorMessage: 'App bridge connection failed: $redactedMessage',
      isStreaming: false,
      diagnosticLogs: _prependDiagnostic(
        DiagnosticSeverity.error,
        'Bridge connection failed',
        redactedMessage,
      ),
    );
    _scheduleBridgeReconnect();
    notifyListeners();
  }

  void _handleBridgeDone() {
    _activeRequestId = null;
    _resetActiveStreamCounters();
    _resetStreamingAssistantDraft();
    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.disconnected,
      isStreaming: false,
      diagnosticLogs: _prependDiagnostic(
        DiagnosticSeverity.warning,
        'Bridge disconnected',
        'The app bridge connection closed.',
      ),
    );
    _scheduleBridgeReconnect();
    notifyListeners();
  }

  void _scheduleBridgeReconnect() {
    if (_disposed ||
        _createBridgeClient == null ||
        _bridgeReconnectTimer != null) {
      return;
    }
    _bridgeReconnectTimer = _scheduleDelayedTask(
      const Duration(seconds: 1),
      () {
        _bridgeReconnectTimer = null;
        if (_disposed ||
            _state.connectionStatus == ConnectionStatus.connected) {
          return;
        }
        reconnectBridge();
      },
    );
  }

  void _cancelScheduledBridgeReconnect() {
    _bridgeReconnectTimer?.cancel();
    _bridgeReconnectTimer = null;
  }

  void _sendPendingBridgeStart() {
    final pending = _pendingBridgeStart;
    if (pending == null) return;
    _pendingBridgeStart = null;
    _sendPromptToBridge(
      requestId: pending.requestId,
      prompt: pending.prompt,
      transcript: pending.transcript,
    );
  }

  void _sendPromptToBridge({
    required String requestId,
    required String prompt,
    required List<BridgeTranscriptMessage> transcript,
  }) {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) return;
    final providerRequest = connectionRequestForCurrentProvider();
    bridgeClient.start(
      requestId: requestId,
      cwd: _activeWorkingDirectory,
      prompt: prompt,
      sessionId: _state.activeSession?.sdkSessionId,
      model: _state.provider.modelName,
      contextTranscriptMode: _state.personal.fullRecentTranscriptContext
          ? 'full_recent'
          : 'token_optimized',
      thinkingMode: _state.personal.thinkingModeEnabled
          ? 'enabled'
          : 'disabled',
      transcript: transcript,
      provider: providerRequest == null
          ? null
          : BridgeProviderConfig(
              providerName: providerRequest.providerName,
              modelName: providerRequest.modelName,
              baseUrl: providerRequest.baseUrl,
              apiKey: providerRequest.apiKey,
            ),
    );
  }

  List<BridgeTranscriptMessage> _bridgeTranscriptForMessages(
    List<ChatMessage> messages,
  ) {
    return [
      for (final message in messages)
        BridgeTranscriptMessage(
          id: message.id,
          role: _bridgeRoleForMessageRole(message.role),
          content: message.content,
        ),
    ];
  }

  void _handleBridgeErrorMessage(BridgeErrorMessage message) {
    final redactedMessage = _appFriendlyBridgeErrorMessage(
      _redactSensitiveText(message.message),
    );
    var extensions = _state.extensions;
    if (message.code == 'SKILLS_LIST_FAILED' ||
        message.code == 'SKILL_IMPORT_FAILED' ||
        message.code == 'SKILL_SET_ENABLED_FAILED' ||
        message.code == 'SKILL_REFRESH_FAILED') {
      _activeSkillsListRequestId = null;
      extensions = extensions.copyWith(
        skillsStatus: ExtensionInventoryStatus.failed,
        skillsErrorMessage: redactedMessage,
      );
    } else if (message.code == 'MCP_SERVERS_LIST_FAILED' ||
        message.code == 'MCP_SERVER_CAPABILITIES_FAILED' ||
        message.code == 'MCP_SERVER_SAVE_FAILED' ||
        message.code == 'MCP_SERVER_SET_ENABLED_FAILED' ||
        message.code == 'MCP_SERVER_DELETE_FAILED' ||
        message.code == 'MCP_SERVER_TEST_FAILED') {
      _activeMcpServersListRequestId = null;
      extensions = extensions.copyWith(
        mcpStatus: ExtensionInventoryStatus.failed,
        mcpErrorMessage: redactedMessage,
      );
    }

    _state = _state.copyWith(
      extensions: extensions,
      connectionStatus: _isRequestScopedBridgeError(message.code)
          ? ConnectionStatus.connected
          : ConnectionStatus.error,
      errorMessage: redactedMessage,
      isStreaming: false,
      diagnosticLogs: _prependDiagnostic(
        DiagnosticSeverity.error,
        message.code,
        redactedMessage,
      ),
    );
  }

  String _appFriendlyBridgeErrorMessage(String message) {
    if (!message.contains('/provider')) return message;
    return message.replaceAll(
      'Or switch provider via /provider',
      'Or open Provider settings and switch model or provider',
    );
  }

  void _handleContextRetrievalMessage(BridgeContextRetrievalMessage message) {
    final rawItems = message.result['items'];
    if (rawItems is! List) return;

    final items = <RetrievedContextItem>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final source = item['source'];
      final title = item['title'];
      final content = item['content'];
      final score = item['score'];
      if (source is! String || title is! String || content is! String) {
        continue;
      }
      items.add(
        RetrievedContextItem(
          source: source,
          title: title,
          content: content,
          score: score is num ? score.toDouble() : 0,
        ),
      );
    }

    final existingAttachments = [
      for (final item in _state.retrievedContextItems)
        if (item.source == 'attachment') item,
    ];
    final hasExistingAttachments = existingAttachments.isNotEmpty;

    _state = _state.copyWith(
      retrievedContextItems: [
        ...existingAttachments,
        for (final item in items)
          if (!hasExistingAttachments || item.source != 'attachment') item,
      ],
      inspector: const InspectorSelection(kind: InspectorKind.context),
    );
  }

  void _handleContextEvaluationResultMessage(
    BridgeContextEvaluationResultMessage message,
  ) {
    if (_activeRetrievalEvaluationRequestId != null &&
        _activeRetrievalEvaluationRequestId != message.requestId) {
      return;
    }
    _activeRetrievalEvaluationRequestId = null;
    _state = _state.copyWith(
      retrievalEvaluation: RetrievalEvaluationState(
        status: RetrievalEvaluationStatus.completed,
        report: RetrievalEvaluationReport.fromMap(message.result),
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
  }

  void _handleContextEvaluationErrorMessage(
    BridgeContextEvaluationErrorMessage message,
  ) {
    if (_activeRetrievalEvaluationRequestId != null &&
        _activeRetrievalEvaluationRequestId != message.requestId) {
      return;
    }
    _activeRetrievalEvaluationRequestId = null;
    final redactedMessage = _redactSensitiveText(message.message);
    _state = _state.copyWith(
      retrievalEvaluation: _state.retrievalEvaluation.copyWith(
        status: RetrievalEvaluationStatus.failed,
        errorMessage: redactedMessage,
      ),
      connectionStatus: ConnectionStatus.connected,
      errorMessage: redactedMessage,
    );
  }

  void _handleContextLearnResultMessage(
    BridgeContextLearnResultMessage message,
  ) {
    if (_activeContextLearnRequestId != null &&
        _activeContextLearnRequestId != message.requestId) {
      return;
    }
    _activeContextLearnRequestId = null;
    final candidates = <LearningCandidate>[];
    for (final candidate in message.candidates) {
      final id = candidate.fact['id'];
      if (id is! String || id.isEmpty) continue;
      candidates.add(
        LearningCandidate(
          id: id,
          source: candidate.source,
          confidence: candidate.confidence,
          reason: candidate.reason,
          evidence: candidate.evidence,
          fact: candidate.fact,
        ),
      );
    }
    if (candidates.isEmpty) return;

    _state = _state.copyWith(
      learningCandidates: _mergeLearningCandidates(
        _state.learningCandidates,
        candidates,
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
  }

  void _handleContextLearnErrorMessage(BridgeContextLearnErrorMessage message) {
    if (_activeContextLearnRequestId != null &&
        _activeContextLearnRequestId != message.requestId) {
      return;
    }
    _activeContextLearnRequestId = null;
    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.connected,
      errorMessage: _redactSensitiveText(message.message),
    );
  }

  void _loadExtensionsInventory({WorkbenchDestination? destination}) {
    final skillsRequestId = _nextRequestId();
    final mcpRequestId = _nextRequestId();
    _activeSkillsListRequestId = skillsRequestId;
    _activeMcpServersListRequestId = mcpRequestId;

    _state = _state.copyWith(
      destination: destination ?? _state.destination,
      extensions: _state.extensions.copyWith(
        skillsStatus: ExtensionInventoryStatus.loading,
        clearSkillsErrorMessage: true,
        mcpStatus: ExtensionInventoryStatus.loading,
        clearMcpErrorMessage: true,
      ),
      connectionStatus: _bridgeClient == null
          ? ConnectionStatus.error
          : ConnectionStatus.connected,
      errorMessage: _bridgeClient == null
          ? 'No app bridge is connected. Start app-bridge and reconnect.'
          : null,
      clearErrorMessage: _bridgeClient != null,
    );
    notifyListeners();

    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _activeSkillsListRequestId = null;
      _activeMcpServersListRequestId = null;
      _state = _state.copyWith(
        extensions: _state.extensions.copyWith(
          skillsStatus: ExtensionInventoryStatus.failed,
          skillsErrorMessage: 'No app bridge is connected.',
          mcpStatus: ExtensionInventoryStatus.failed,
          mcpErrorMessage: 'No app bridge is connected.',
        ),
      );
      notifyListeners();
      return;
    }

    bridgeClient.listSkills(requestId: skillsRequestId, includeDisabled: true);
    bridgeClient.listMcpServers(
      requestId: mcpRequestId,
      cwd: _activeWorkingDirectory,
      includeDisabled: true,
    );
  }

  void _handleSkillsSnapshotMessage(BridgeSkillsSnapshotMessage message) {
    if (_activeSkillsListRequestId != null &&
        _activeSkillsListRequestId != message.requestId) {
      return;
    }
    _activeSkillsListRequestId = null;
    _state = _state.copyWith(
      extensions: _state.extensions.copyWith(
        skillsStatus: ExtensionInventoryStatus.loaded,
        skills: [
          for (final skill in message.skills) _skillSummaryFromBridge(skill),
        ],
        clearSkillsErrorMessage: true,
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
  }

  void _handleSkillImportedMessage(BridgeSkillImportedMessage message) {
    _state = _state.copyWith(
      extensions: _state.extensions.copyWith(
        skillsStatus: ExtensionInventoryStatus.loaded,
        skills: _mergeSkillSummary(
          _state.extensions.skills,
          _skillSummaryFromBridge(message.skill),
        ),
        clearSkillsErrorMessage: true,
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
  }

  void _handleSkillUpdatedMessage(BridgeSkillUpdatedMessage message) {
    _state = _state.copyWith(
      extensions: _state.extensions.copyWith(
        skillsStatus: ExtensionInventoryStatus.loaded,
        skills: _mergeSkillSummary(
          _state.extensions.skills,
          _skillSummaryFromBridge(message.skill),
        ),
        clearSkillsErrorMessage: true,
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
  }

  SkillSummary _skillSummaryFromBridge(BridgeSkillSummary skill) {
    return SkillSummary(
      id: skill.id,
      name: skill.name,
      description: skill.description,
      source: skill.source,
      status: skill.status,
      path: skill.path,
      serverId: skill.serverId,
      unavailableReason: skill.unavailableReason,
    );
  }

  List<SkillSummary> _mergeSkillSummary(
    List<SkillSummary> skills,
    SkillSummary next,
  ) {
    final merged = <SkillSummary>[];
    var replaced = false;
    for (final skill in skills) {
      if (skill.id == next.id) {
        if (!replaced) merged.add(next);
        replaced = true;
      } else {
        merged.add(skill);
      }
    }
    if (!replaced) merged.add(next);
    return merged;
  }

  List<McpCapabilityItem> _mcpCapabilityItemsFromBridge(
    List<BridgeMcpCapabilityItem> items,
  ) {
    return [
      for (final item in items)
        McpCapabilityItem(name: item.name, description: item.description),
    ];
  }

  String _mcpServerIdForDraft(McpServerDraft server) {
    final existingId = server.id?.trim();
    if (existingId != null && existingId.isNotEmpty) return existingId;
    final normalized = server.name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'mcp-server' : normalized;
  }

  void _handleMcpServersSnapshotMessage(
    BridgeMcpServersSnapshotMessage message,
  ) {
    if (_activeMcpServersListRequestId != null &&
        _activeMcpServersListRequestId != message.requestId) {
      return;
    }
    _activeMcpServersListRequestId = null;
    _state = _state.copyWith(
      extensions: _state.extensions.copyWith(
        mcpStatus: ExtensionInventoryStatus.loaded,
        mcpServers: [
          for (final server in message.servers)
            McpServerSummary(
              id: server.id,
              name: server.name,
              transport: server.transport,
              scope: server.scope,
              enabled: server.enabled,
              status: server.status,
              toolCount: server.toolCount,
              resourceCount: server.resourceCount,
              skillCount: server.skillCount,
              lastError: server.lastError == null
                  ? null
                  : _redactSensitiveText(server.lastError!),
              command: server.command,
              args: server.args,
              url: server.url,
              headers: server.headers,
              env: server.env,
            ),
        ],
        clearMcpErrorMessage: true,
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
  }

  void _handleMcpServerCapabilitiesMessage(
    BridgeMcpServerCapabilitiesMessage message,
  ) {
    _state = _state.copyWith(connectionStatus: ConnectionStatus.connected);
  }

  void _handleMcpServerTestResultMessage(
    BridgeMcpServerTestResultMessage message,
  ) {
    final redactedMessage = _redactSensitiveText(message.message);
    final result = McpConnectionTestResult(
      serverId: message.serverId,
      status: message.status,
      message: redactedMessage,
      durationMs: message.durationMs,
      checkedAt: message.checkedAt,
      tools: _mcpCapabilityItemsFromBridge(message.tools),
      resources: _mcpCapabilityItemsFromBridge(message.resources),
      prompts: _mcpCapabilityItemsFromBridge(message.prompts),
      skills: [
        for (final skill in message.skills) _skillSummaryFromBridge(skill),
      ],
    );
    _state = _state.copyWith(
      extensions: _state.extensions.copyWith(
        mcpServers: [
          for (final server in _state.extensions.mcpServers)
            if (server.id == message.serverId)
              server.copyWith(
                status: message.status,
                toolCount: message.tools.length,
                resourceCount: message.resources.length,
                skillCount: message.skills.length,
                lastError: message.status == 'connected'
                    ? null
                    : redactedMessage,
              )
            else
              server,
        ],
        mcpTestResults: {
          ..._state.extensions.mcpTestResults,
          message.serverId: result,
        },
        clearMcpErrorMessage: true,
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
  }

  void _handleMcpServerSavedMessage(BridgeMcpServerSavedMessage message) {
    _requestMcpServersList();
  }

  void _handleMcpServerDeletedMessage(BridgeMcpServerDeletedMessage message) {
    _state = _state.copyWith(
      extensions: _state.extensions.copyWith(
        mcpServers: [
          for (final server in _state.extensions.mcpServers)
            if (server.id != message.serverId) server,
        ],
      ),
    );
    _requestMcpServersList();
  }

  void _requestMcpServersList() {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) return;
    final requestId = _nextRequestId();
    _activeMcpServersListRequestId = requestId;
    _state = _state.copyWith(
      extensions: _state.extensions.copyWith(
        mcpStatus: ExtensionInventoryStatus.loading,
        clearMcpErrorMessage: true,
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
    bridgeClient.listMcpServers(
      requestId: requestId,
      cwd: _activeWorkingDirectory,
      includeDisabled: true,
    );
  }

  void _handleContextIndexProgressMessage(
    BridgeContextIndexProgressMessage message,
  ) {
    if (!_isActiveKnowledgeIndexRequest(message.requestId)) return;
    _state = _state.copyWith(
      knowledgeIndex: _state.knowledgeIndex.copyWith(
        target: _knowledgeTargetForBridgeTarget(message.target),
        path: message.path,
        status: KnowledgeIndexStatus.indexing,
        clearErrorMessage: true,
      ),
    );
  }

  void _handleContextIndexResultMessage(
    BridgeContextIndexResultMessage message,
  ) {
    if (!_isActiveKnowledgeIndexRequest(message.requestId)) return;
    _activeKnowledgeIndexRequestId = null;
    _state = _state.copyWith(
      knowledgeIndex: _state.knowledgeIndex.copyWith(
        target: _knowledgeTargetForBridgeTarget(message.target),
        path: message.path,
        status: KnowledgeIndexStatus.completed,
        indexedNodes: message.indexedNodes,
        sourcePaths: message.sourcePaths,
        clearErrorMessage: true,
      ),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
  }

  void _handleContextIndexErrorMessage(BridgeContextIndexErrorMessage message) {
    if (!_isActiveKnowledgeIndexRequest(message.requestId)) return;
    _activeKnowledgeIndexRequestId = null;
    final redactedMessage = _redactSensitiveText(message.message);
    _state = _state.copyWith(
      knowledgeIndex: _state.knowledgeIndex.copyWith(
        status: KnowledgeIndexStatus.failed,
        errorMessage: redactedMessage,
      ),
      connectionStatus: ConnectionStatus.connected,
    );
  }

  bool _isActiveKnowledgeIndexRequest(String requestId) {
    return _activeKnowledgeIndexRequestId == null ||
        _activeKnowledgeIndexRequestId == requestId;
  }

  void _handleSdkMessage(BridgeSdkMessage message) {
    if (message.requestId != _activeRequestId) return;
    _state = _state.copyWith(
      sessions: _updateActiveSession(
        (session) => session.copyWith(sdkSessionId: message.sessionId),
      ),
    );
    final payload = message.message;
    final type = payload['type'];
    if (type == 'permission_request') {
      final request = _permissionRequestFromSdkMessage(message);
      final toolRun = _toolRunFromPermissionRequest(request);
      if (_shouldAutoAllowToolPermissionsForActiveSession) {
        _bridgeClient?.respondToPermission(
          requestId: request.requestId,
          toolUseId: request.toolUseId,
          decision: const {'behavior': _permissionDecisionAllow},
        );
        _state = _state.copyWith(
          permissionRequests: const [],
          toolRuns: [
            toolRun.copyWith(
              status: ToolRunStatus.running,
              summary: 'Executing approved command',
            ),
          ],
        );
        _persistState();
        return;
      }
      if (_state.permissionRequests.every(
        (pending) => pending.id != request.id,
      )) {
        _state = _state.copyWith(
          permissionRequests: [request],
          toolRuns: [toolRun],
          inspector: InspectorSelection(
            kind: InspectorKind.permission,
            itemId: request.id,
          ),
        );
      }
      _persistState();
      return;
    }

    if (type == 'stream_event') {
      _activeStreamEventCount += 1;
      if (_isThinkingDeltaFromSdkStreamEvent(payload)) {
        _activeStreamThinkingDeltaCount += 1;
      }
      final textDelta = _textDeltaFromSdkStreamEvent(payload);
      if (textDelta.isNotEmpty) {
        _activeStreamTextDeltaCount += 1;
        _upsertStreamingAssistantMessage(textDelta);
      }
      return;
    }

    if (type == 'assistant') {
      final content = _assistantTextFromSdkPayload(payload);
      if (content.isNotEmpty) {
        _upsertStreamingAssistantMessage(content, isSnapshot: true);
      }
      return;
    }

    if (type == 'result') {
      final content = payload['result']?.toString() ?? '';
      final diagnosticLogs = _streamingDiagnosticLogsForCompletedTurn();
      _finishStreamingAssistantMessage(
        content: content,
        tokenUsage: _tokenUsageFromSdkPayload(payload['usage']),
        diagnosticLogs: diagnosticLogs,
      );
      _activeRequestId = null;
      _resetActiveStreamCounters();
      _resetStreamingAssistantDraft();
      _persistState();
      _requestContextLearning();
    }
  }

  void _resetActiveStreamCounters() {
    _activeStreamEventCount = 0;
    _activeStreamTextDeltaCount = 0;
    _activeStreamThinkingDeltaCount = 0;
  }

  void _resetStreamingAssistantDraft() {
    _streamingAssistantMessageId = null;
    _streamingAssistantText = '';
  }

  List<DiagnosticLogEntry> _streamingDiagnosticLogsForCompletedTurn() {
    if (_activeStreamTextDeltaCount > 0) return _state.diagnosticLogs;
    if (_activeStreamEventCount == 0) {
      return _prependDiagnostic(
        DiagnosticSeverity.warning,
        'No SDK stream events',
        'This turn completed without SDK stream_event messages before the final result. The provider request likely fell back to non-streaming or the upstream endpoint buffered the response.',
      );
    }
    if (_activeStreamThinkingDeltaCount > 0) {
      return _prependDiagnostic(
        DiagnosticSeverity.warning,
        'Only thinking deltas streamed',
        'SSE is active, but this turn streamed thinking_delta events without text_delta answer tokens before the final result. The selected model may buffer visible answer text until reasoning completes.',
      );
    }
    return _prependDiagnostic(
      DiagnosticSeverity.warning,
      'No streaming text deltas',
      'This turn received SDK stream events but no text_delta answer tokens before the final result. The selected provider or upstream endpoint may be buffering visible response text.',
    );
  }

  bool _isThinkingDeltaFromSdkStreamEvent(Map<String, dynamic> payload) {
    final event = payload['event'];
    if (event is! Map) return false;
    final eventMap = Map<String, dynamic>.from(event);
    if (eventMap['type'] != 'content_block_delta') return false;
    final delta = eventMap['delta'];
    if (delta is! Map) return false;
    final deltaMap = Map<String, dynamic>.from(delta);
    return deltaMap['type'] == 'thinking_delta';
  }

  String _textDeltaFromSdkStreamEvent(Map<String, dynamic> payload) {
    final event = payload['event'];
    if (event is! Map) return '';
    final eventMap = Map<String, dynamic>.from(event);
    if (eventMap['type'] != 'content_block_delta') return '';
    final delta = eventMap['delta'];
    if (delta is! Map) return '';
    final deltaMap = Map<String, dynamic>.from(delta);
    if (deltaMap['type'] != 'text_delta') return '';
    return deltaMap['text']?.toString() ?? '';
  }

  String _assistantTextFromSdkPayload(Map<String, dynamic> payload) {
    final message = payload['message'];
    if (message is! Map) return '';
    final messageMap = Map<String, dynamic>.from(message);
    final content = messageMap['content'];
    if (content is String) return content;
    if (content is! List) return '';
    final textBlocks = <String>[];
    for (final block in content) {
      if (block is! Map) continue;
      final blockMap = Map<String, dynamic>.from(block);
      if (blockMap['type'] != 'text') continue;
      final text = blockMap['text']?.toString();
      if (text == null || text.isEmpty) continue;
      textBlocks.add(text);
    }
    return textBlocks.join();
  }

  void _upsertStreamingAssistantMessage(
    String nextText, {
    bool isSnapshot = false,
  }) {
    if (nextText.isEmpty) return;
    final messageId = _streamingAssistantMessageId ?? _nextMessageId();
    final mergedText = _mergeStreamingAssistantText(
      currentText: _streamingAssistantText,
      nextText: nextText,
      isSnapshot: isSnapshot,
    );
    _streamingAssistantMessageId = messageId;
    _streamingAssistantText = mergedText;
    _state = _state.copyWith(
      messages: _upsertAssistantMessage(
        messageId: messageId,
        content: mergedText,
      ),
    );
  }

  String _mergeStreamingAssistantText({
    required String currentText,
    required String nextText,
    required bool isSnapshot,
  }) {
    if (currentText.isEmpty) return nextText;
    if (isSnapshot) {
      if (nextText.length >= currentText.length ||
          nextText.startsWith(currentText)) {
        return nextText;
      }
      return currentText;
    }
    if (nextText.startsWith(currentText)) return nextText;
    return '$currentText$nextText';
  }

  void _finishStreamingAssistantMessage({
    required String content,
    ChatTokenUsage? tokenUsage,
    List<DiagnosticLogEntry>? diagnosticLogs,
  }) {
    final messageId = _streamingAssistantMessageId;
    if (messageId != null) {
      final nextContent = content.isEmpty ? _streamingAssistantText : content;
      _state = _state.copyWith(
        messages: nextContent.isEmpty
            ? _state.messages
            : _upsertAssistantMessage(
                messageId: messageId,
                content: nextContent,
                tokenUsage: tokenUsage,
              ),
        diagnosticLogs: diagnosticLogs,
        isStreaming: false,
        toolRuns: _clearRunningToolRuns(),
      );
      return;
    }

    if (content.isNotEmpty) {
      final assistantMessage = ChatMessage(
        id: _nextMessageId(),
        role: MessageRole.assistant,
        content: content,
        timestampLabel: 'Now',
        tokenUsage: tokenUsage,
      );
      _state = _state.copyWith(
        messages: [..._state.messages, assistantMessage],
        diagnosticLogs: diagnosticLogs,
        isStreaming: false,
        toolRuns: _clearRunningToolRuns(),
      );
      return;
    }

    _state = _state.copyWith(
      diagnosticLogs: diagnosticLogs,
      isStreaming: false,
      toolRuns: _clearRunningToolRuns(),
    );
  }

  List<ChatMessage> _upsertAssistantMessage({
    required String messageId,
    required String content,
    ChatTokenUsage? tokenUsage,
  }) {
    var replaced = false;
    final messages = [
      for (final message in _state.messages)
        if (message.id == messageId)
          _assistantMessageWith(
            message,
            content: content,
            tokenUsage: tokenUsage,
          )
        else
          message,
    ];
    for (final message in _state.messages) {
      if (message.id == messageId) {
        replaced = true;
        break;
      }
    }
    if (replaced) return messages;
    return [
      ...messages,
      ChatMessage(
        id: messageId,
        role: MessageRole.assistant,
        content: content,
        timestampLabel: 'Now',
        tokenUsage: tokenUsage,
      ),
    ];
  }

  ChatMessage _assistantMessageWith(
    ChatMessage message, {
    required String content,
    ChatTokenUsage? tokenUsage,
  }) {
    return ChatMessage(
      id: message.id,
      role: message.role,
      content: content,
      timestampLabel: message.timestampLabel,
      attachments: message.attachments,
      tokenUsage: tokenUsage ?? message.tokenUsage,
    );
  }

  bool _isAllowedPermissionDecision(String decision) {
    return decision == _permissionDecisionAllow ||
        decision == _permissionDecisionAllowAll;
  }

  ChatTokenUsage? _tokenUsageFromSdkPayload(Object? value) {
    if (value is! Map) return null;
    final usage = Map<String, dynamic>.from(value);
    final inputTokens = _intFromUsage(usage['input_tokens']);
    final outputTokens = _intFromUsage(usage['output_tokens']);
    final cacheReadInputTokens = _intFromUsage(
      usage['cache_read_input_tokens'],
    );
    final cacheCreationInputTokens = _intFromUsage(
      usage['cache_creation_input_tokens'],
    );
    if (inputTokens == null && outputTokens == null) return null;
    return ChatTokenUsage(
      inputTokens: inputTokens ?? 0,
      outputTokens: outputTokens ?? 0,
      cacheReadInputTokens: cacheReadInputTokens ?? 0,
      cacheCreationInputTokens: cacheCreationInputTokens ?? 0,
    );
  }

  int? _intFromUsage(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return null;
  }

  List<ToolRun> _updateToolRun(
    String toolRunId,
    ToolRun Function(ToolRun run) update,
  ) {
    return [
      for (final run in _state.toolRuns)
        if (run.id == toolRunId) update(run) else run,
    ];
  }

  List<ToolRun> _clearRunningToolRuns() {
    return [
      for (final run in _state.toolRuns)
        if (run.status != ToolRunStatus.running) run,
    ];
  }

  void _persistState() {
    final store = _persistenceStore;
    if (store == null) return;
    _rememberActiveMessages();
    unawaited(_savePersistedState(store));
  }

  void _rememberActiveMessages() {
    final sessionId = _state.activeSessionId;
    if (sessionId.isEmpty) return;
    _messagesBySessionId[sessionId] = List.unmodifiable(_state.messages);
  }

  Future<void> _savePersistedState(WorkbenchPersistenceStore store) async {
    try {
      await store.save(
        encodePersistedWorkbenchState(
          state: _state,
          apiKeysByRoute: _apiKeysByRoute,
          messagesBySessionId: _messagesBySessionId,
        ),
      );
    } catch (error) {
      debugPrint('Failed to save OpenClaude workbench state: $error');
    }
  }

  void _requestContextLearning() {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null || _state.messages.isEmpty) return;

    final requestId = _nextRequestId();
    _activeContextLearnRequestId = requestId;
    bridgeClient.learnContext(
      requestId: requestId,
      transcript: [
        for (final message in _state.messages)
          BridgeTranscriptMessage(
            id: message.id,
            role: _bridgeRoleForMessageRole(message.role),
            content: message.content,
          ),
      ],
      maxCandidates: 5,
    );
  }

  String _bridgeRoleForMessageRole(MessageRole role) {
    return switch (role) {
      MessageRole.user => 'user',
      MessageRole.assistant => 'assistant',
      MessageRole.system => 'system',
    };
  }

  void _handleContextFactUpsertResultMessage(
    BridgeContextFactUpsertResultMessage message,
  ) {
    final candidateId = _learningUpsertRequestIds.remove(message.requestId);
    if (candidateId == null) return;
    final candidate = _learningCandidateById(candidateId);
    final memoryFact = candidate == null
        ? null
        : _memoryFactFromBridge(
            BridgeMemoryFact(
              source: candidate.source,
              disabled: false,
              fact: candidate.fact,
            ),
          );
    _state = _state.copyWith(
      learningCandidates: _updateLearningCandidate(
        candidateId,
        (candidate) =>
            candidate.copyWith(status: LearningCandidateStatus.saved),
      ),
      memoryFacts: memoryFact == null
          ? _state.memoryFacts
          : _mergeMemoryFact(_state.memoryFacts, memoryFact),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
  }

  void _handleContextFactUpsertErrorMessage(
    BridgeContextFactUpsertErrorMessage message,
  ) {
    final candidateId = _learningUpsertRequestIds.remove(message.requestId);
    _state = _state.copyWith(
      learningCandidates: candidateId == null
          ? _state.learningCandidates
          : _updateLearningCandidate(
              candidateId,
              (candidate) =>
                  candidate.copyWith(status: LearningCandidateStatus.pending),
            ),
      connectionStatus: ConnectionStatus.connected,
      errorMessage: _redactSensitiveText(message.message),
    );
  }

  void _handleContextFactsListResultMessage(
    BridgeContextFactsListResultMessage message,
  ) {
    if (_activeMemoryFactsRequestId != null &&
        _activeMemoryFactsRequestId != message.requestId) {
      return;
    }
    _activeMemoryFactsRequestId = null;
    final memoryFacts = <MemoryFact>[];
    for (final fact in message.facts) {
      final memoryFact = _memoryFactFromBridge(fact);
      if (memoryFact != null) memoryFacts.add(memoryFact);
    }
    _state = _state.copyWith(
      memoryFacts: memoryFacts,
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
  }

  void _handleContextFactsListErrorMessage(
    BridgeContextFactsListErrorMessage message,
  ) {
    if (_activeMemoryFactsRequestId != null &&
        _activeMemoryFactsRequestId != message.requestId) {
      return;
    }
    _activeMemoryFactsRequestId = null;
    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.connected,
      errorMessage: _redactSensitiveText(message.message),
    );
  }

  void _handleContextFactDeleteResultMessage(
    BridgeContextFactDeleteResultMessage message,
  ) {
    _state = _state.copyWith(
      memoryFacts: [
        for (final fact in _state.memoryFacts)
          if (fact.source != message.source || fact.id != message.id) fact,
      ],
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
  }

  void _handleContextFactDeleteErrorMessage(
    BridgeContextFactDeleteErrorMessage message,
  ) {
    _state = _state.copyWith(
      connectionStatus: ConnectionStatus.connected,
      errorMessage: _redactSensitiveText(message.message),
    );
  }

  PermissionRequest _permissionRequestFromSdkMessage(BridgeSdkMessage message) {
    final payload = message.message;
    final toolName = payload['tool_name']?.toString() ?? 'Tool';
    final toolUseId = payload['tool_use_id']?.toString() ?? '';
    final action = _summarizePermissionAction(toolName, payload['input']);
    return PermissionRequest(
      id: '${message.requestId}:$toolUseId',
      requestId: message.requestId,
      toolUseId: toolUseId,
      title: 'Approve $toolName',
      action: action,
      riskSummary: _permissionPurposeSummary(toolName),
      rawPayload: const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  String _permissionPurposeSummary(String toolName) {
    final normalized = toolName.toLowerCase();
    if (normalized == 'bash') {
      return 'This will run a shell command in the active project workspace. Allow it only if the command matches what you asked $appDisplayName to do.';
    }
    if (normalized.contains('write') || normalized.contains('edit')) {
      return 'This will change files in the active project workspace. Allow it only if the file operation matches your request.';
    }
    return 'This tool can inspect or change project state for the current step. Allow it only if it matches your request.';
  }

  ToolRun _toolRunFromPermissionRequest(PermissionRequest request) {
    return ToolRun(
      id: request.toolUseId.isEmpty ? request.id : request.toolUseId,
      name: request.title.replaceFirst('Approve ', ''),
      command: request.action,
      status: ToolRunStatus.pending,
      summary: 'Waiting for permission approval',
      details: request.rawPayload,
      elapsedLabel: 'Now',
    );
  }

  List<BridgeContextEvaluationCase> _evaluationCasesForState() {
    if (_state.retrievedContextItems.isNotEmpty) {
      return [
        for (final item in _state.retrievedContextItems.take(5))
          BridgeContextEvaluationCase(
            name: item.title,
            query: item.title,
            relevantIds: ['${item.source}:${item.title}'],
          ),
      ];
    }

    return const [
      BridgeContextEvaluationCase(
        name: 'Provider settings',
        query: 'provider api key setup',
        relevantIds: ['document:Provider settings'],
      ),
      BridgeContextEvaluationCase(
        name: 'User profile',
        query: 'preferred response style',
        relevantIds: ['profile:Preferred tone'],
      ),
      BridgeContextEvaluationCase(
        name: 'Tool usage habit',
        query: 'tool approval workflow',
        relevantIds: ['habit:Tool approval habit'],
      ),
    ];
  }

  String _summarizePermissionAction(String toolName, Object? input) {
    if (input is Map) {
      final command = input['command'];
      if (command != null) return command.toString();
      final url = input['url'];
      if (url != null) return url.toString();
      final path = input['path'] ?? input['file_path'];
      if (path != null) return path.toString();
    }
    if (input != null) return input.toString();
    return toolName;
  }

  void _upsertMemoryFact({
    required String source,
    required String id,
    required Map<String, dynamic> fact,
    required MemoryFact Function(MemoryFact fact) localUpdate,
  }) {
    final bridgeClient = _bridgeClient;
    if (bridgeClient == null) {
      _state = _state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:
            'No app bridge is connected. Start app-bridge and reconnect.',
      );
      notifyListeners();
      return;
    }

    _state = _state.copyWith(
      memoryFacts: _updateMemoryFact(source, id, localUpdate),
      connectionStatus: ConnectionStatus.connected,
      clearErrorMessage: true,
    );
    notifyListeners();

    bridgeClient.upsertContextFact(
      requestId: _nextRequestId(),
      cwd: _activeWorkingDirectory,
      source: source,
      fact: fact,
    );
  }

  MemoryFact? _memoryFactById(String source, String id) {
    for (final fact in _state.memoryFacts) {
      if (fact.source == source && fact.id == id) return fact;
    }
    return null;
  }

  List<MemoryFact> _updateMemoryFact(
    String source,
    String id,
    MemoryFact Function(MemoryFact fact) update,
  ) {
    return [
      for (final fact in _state.memoryFacts)
        if (fact.source == source && fact.id == id) update(fact) else fact,
    ];
  }

  List<MemoryFact> _mergeMemoryFact(List<MemoryFact> current, MemoryFact next) {
    var replaced = false;
    final merged = <MemoryFact>[];
    for (final fact in current) {
      if (fact.source == next.source && fact.id == next.id) {
        if (!replaced) merged.add(next);
        replaced = true;
      } else {
        merged.add(fact);
      }
    }
    if (!replaced) merged.add(next);
    return merged;
  }

  MemoryFact? _memoryFactFromBridge(BridgeMemoryFact bridgeFact) {
    final fact = bridgeFact.fact;
    final rawId = fact['id'];
    if (rawId is! String || rawId.isEmpty) return null;

    final metadata = _metadataFromFact(fact);
    final titleOverride = metadata['title'];
    final (title, content) = switch (bridgeFact.source) {
      'graph' => _graphFactText(fact, titleOverride),
      _ => _labelContentFactText(fact, rawId),
    };

    return MemoryFact(
      source: bridgeFact.source,
      id: rawId,
      title: title,
      content: content,
      disabled: bridgeFact.disabled,
      fact: fact,
    );
  }

  Map<String, dynamic> _factWithMemoryText(
    MemoryFact memoryFact,
    String title,
    String content,
  ) {
    final fact = Map<String, dynamic>.from(memoryFact.fact);
    if (memoryFact.source == 'profile' || memoryFact.source == 'habit') {
      fact['label'] = title;
      fact['content'] = content;
      return fact;
    }

    fact['evidence'] = content;
    final metadata = _metadataFromFact(fact);
    metadata['title'] = title;
    fact['metadata'] = metadata;
    return fact;
  }

  Map<String, dynamic> _factWithDisabledState(
    Map<String, dynamic> rawFact,
    bool disabled,
  ) {
    final fact = Map<String, dynamic>.from(rawFact);
    final metadata = _metadataFromFact(fact);
    metadata['disabled'] = disabled;
    fact['metadata'] = metadata;
    return fact;
  }

  Map<String, dynamic> _metadataFromFact(Map<String, dynamic> fact) {
    final metadata = fact['metadata'];
    return metadata is Map ? Map<String, dynamic>.from(metadata) : {};
  }

  (String, String) _labelContentFactText(
    Map<String, dynamic> fact,
    String fallbackTitle,
  ) {
    final label = fact['label'];
    final content = fact['content'];
    final title = label is String && label.isNotEmpty ? label : fallbackTitle;
    final body = content is String && content.isNotEmpty ? content : title;
    return (title, body);
  }

  (String, String) _graphFactText(
    Map<String, dynamic> fact,
    Object? titleOverride,
  ) {
    final relationTitle = [
      fact['subject'],
      fact['predicate'],
      fact['object'],
    ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
    final title = titleOverride is String && titleOverride.isNotEmpty
        ? titleOverride
        : relationTitle;
    final evidence = fact['evidence'];
    final content = evidence is String && evidence.isNotEmpty
        ? evidence
        : title;
    return (title.isEmpty ? 'Graph relation' : title, content);
  }

  String _nextMessageId() {
    _messageCounter += 1;
    return 'ui-message-$_messageCounter';
  }

  String _nextRequestId() {
    _requestCounter += 1;
    return 'ui-request-$_requestCounter';
  }

  LearningCandidate? _learningCandidateById(String id) {
    for (final candidate in _state.learningCandidates) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }

  List<LearningCandidate> _mergeLearningCandidates(
    List<LearningCandidate> current,
    List<LearningCandidate> next,
  ) {
    final byId = <String, LearningCandidate>{
      for (final candidate in current) candidate.id: candidate,
    };
    for (final candidate in next) {
      byId.putIfAbsent(candidate.id, () => candidate);
    }
    return byId.values.toList();
  }

  List<LearningCandidate> _updateLearningCandidate(
    String id,
    LearningCandidate Function(LearningCandidate candidate) update,
  ) {
    return [
      for (final candidate in _state.learningCandidates)
        if (candidate.id == id) update(candidate) else candidate,
    ];
  }

  List<SessionSummary> _updateActiveSession(
    SessionSummary Function(SessionSummary session) update,
  ) {
    return [
      for (final session in _state.sessions)
        if (session.id == _state.activeSessionId) update(session) else session,
    ];
  }

  String _sessionTitleForPrompt(String prompt) {
    final title = prompt
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
    if (title.length <= 48) return title;
    return '${title.substring(0, 45)}...';
  }

  String _bridgeTargetForKnowledgeTarget(KnowledgeIndexTarget target) {
    return switch (target) {
      KnowledgeIndexTarget.file => 'file',
      KnowledgeIndexTarget.directory => 'directory',
    };
  }

  List<DiagnosticLogEntry> _prependDiagnostic(
    DiagnosticSeverity severity,
    String title,
    String detail,
  ) {
    return [
      DiagnosticLogEntry(
        id: 'diagnostic-${++_diagnosticCounter}',
        severity: severity,
        title: title,
        detail: _redactSensitiveText(detail),
        timestampLabel: 'Now',
      ),
      ..._state.diagnosticLogs,
    ].take(100).toList();
  }

  DiagnosticSeverity _timelineSeverity(TurnTimelineEntry entry) {
    return switch (entry.status) {
      'completed' => DiagnosticSeverity.success,
      'failed' => DiagnosticSeverity.error,
      'skipped' => DiagnosticSeverity.warning,
      _ => DiagnosticSeverity.info,
    };
  }

  String _timelineLogDetail(TurnTimelineEntry entry) {
    final parts = <String>[
      entry.status,
      if (entry.durationLabel.isNotEmpty) entry.durationLabel,
      if (entry.toolName != null && entry.toolName!.isNotEmpty) entry.toolName!,
      if (entry.detail != null && entry.detail!.isNotEmpty) entry.detail!,
    ];
    return parts.join(' · ');
  }

  KnowledgeIndexTarget _knowledgeTargetForBridgeTarget(String target) {
    return target == 'file'
        ? KnowledgeIndexTarget.file
        : KnowledgeIndexTarget.directory;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelScheduledBridgeReconnect();
    unawaited(_bridgeSubscription?.cancel());
    unawaited(_bridgeClient?.close());
    super.dispose();
  }
}

Future<void> _copyTextToClipboard(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}

String _redactSensitiveText(String value) {
  var redacted = value.replaceAllMapped(
    RegExp(r'\b(Bearer\s+)[^\s,;]+', caseSensitive: false),
    (match) => '${match.group(1)}$_redactedSecret',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(
      r'\b([A-Za-z0-9_-]*(?:api[_-]?key|authorization|auth|credential|password|secret|token)[A-Za-z0-9_-]*\s*[=:]\s*)([^\s,;]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}$_redactedSecret',
  );
  redacted = redacted.replaceAll(
    RegExp(r'\bsk-[A-Za-z0-9_-]{6,}\b'),
    _redactedSecret,
  );
  return redacted;
}
