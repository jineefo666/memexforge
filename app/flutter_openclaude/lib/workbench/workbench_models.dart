import 'default_working_directory.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

enum SessionStatus { idle, running, waitingForPermission, failed }

enum MessageRole { user, assistant, system }

enum ToolRunStatus { pending, running, success, error }

enum ChatAttachmentKind { text, image, file }

enum WorkbenchDestination {
  chat,
  context,
  tools,
  extensions,
  diagnostics,
  providers,
  settings,
}

enum InspectorKind { overview, message, tool, permission, settings, context }

enum ThemePreference { light, dark, system }

enum TranscriptContextMode { tokenOptimized, fullRecent }

enum KnowledgeIndexTarget { file, directory }

enum KnowledgeIndexStatus { idle, indexing, completed, failed }

enum LearningCandidateStatus { pending, saving, saved, ignored }

enum RetrievalEvaluationStatus { idle, running, completed, failed }

enum ExtensionInventoryStatus { idle, loading, loaded, failed }

enum DiagnosticSeverity { info, success, warning, error }

enum BridgeLaunchStatus { idle, starting, started, unsupported, failed }

enum DiagnosticsReportCopyStatus { idle, copied, failed }

const defaultWorkbenchBridgeUrl = 'ws://127.0.0.1:58432';

final class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.updatedLabel,
    this.sdkSessionId,
  });

  final String id;
  final String title;
  final String subtitle;
  final SessionStatus status;
  final String updatedLabel;
  final String? sdkSessionId;

  SessionSummary copyWith({
    String? title,
    String? subtitle,
    SessionStatus? status,
    String? updatedLabel,
    String? sdkSessionId,
    bool clearSdkSessionId = false,
  }) {
    return SessionSummary(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      status: status ?? this.status,
      updatedLabel: updatedLabel ?? this.updatedLabel,
      sdkSessionId: clearSdkSessionId
          ? null
          : sdkSessionId ?? this.sdkSessionId,
    );
  }
}

final class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestampLabel,
    this.attachments = const [],
    this.tokenUsage,
  });

  final String id;
  final MessageRole role;
  final String content;
  final String timestampLabel;
  final List<ChatAttachment> attachments;
  final ChatTokenUsage? tokenUsage;
}

final class ChatSendRequest {
  const ChatSendRequest({required this.text, this.attachments = const []});

  final String text;
  final List<ChatAttachment> attachments;
}

final class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.kind,
    this.path,
    this.content,
    this.dataBase64,
  });

  final String id;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final ChatAttachmentKind kind;
  final String? path;
  final String? content;
  final String? dataBase64;
}

final class ChatTokenUsage {
  const ChatTokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheReadInputTokens = 0,
    this.cacheCreationInputTokens = 0,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheReadInputTokens;
  final int cacheCreationInputTokens;
}

final class ToolRun {
  const ToolRun({
    required this.id,
    required this.name,
    required this.command,
    required this.status,
    required this.summary,
    required this.details,
    required this.elapsedLabel,
  });

  final String id;
  final String name;
  final String command;
  final ToolRunStatus status;
  final String summary;
  final String details;
  final String elapsedLabel;

  ToolRun copyWith({
    ToolRunStatus? status,
    String? summary,
    String? details,
    String? elapsedLabel,
  }) {
    return ToolRun(
      id: id,
      name: name,
      command: command,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      details: details ?? this.details,
      elapsedLabel: elapsedLabel ?? this.elapsedLabel,
    );
  }
}

final class PermissionRequest {
  const PermissionRequest({
    required this.id,
    required this.requestId,
    required this.toolUseId,
    required this.title,
    required this.action,
    required this.riskSummary,
    required this.rawPayload,
  });

  final String id;
  final String requestId;
  final String toolUseId;
  final String title;
  final String action;
  final String riskSummary;
  final String rawPayload;
}

final class RetrievedContextItem {
  const RetrievedContextItem({
    required this.source,
    required this.title,
    required this.content,
    required this.score,
  });

  final String source;
  final String title;
  final String content;
  final double score;
}

final class LearningCandidate {
  const LearningCandidate({
    required this.id,
    required this.source,
    required this.confidence,
    required this.reason,
    required this.evidence,
    required this.fact,
    this.status = LearningCandidateStatus.pending,
  });

  final String id;
  final String source;
  final double confidence;
  final String reason;
  final String evidence;
  final Map<String, dynamic> fact;
  final LearningCandidateStatus status;

  String get sourceLabel {
    return switch (source) {
      'profile' => 'Profile',
      'habit' => 'Habit',
      'graph' => 'Graph',
      _ => source,
    };
  }

  String get summary {
    final content = fact['content'];
    if (content is String && content.isNotEmpty) return content;
    final subject = fact['subject'];
    final predicate = fact['predicate'];
    final object = fact['object'];
    if (subject is String && predicate is String && object is String) {
      return '$subject $predicate $object';
    }
    return evidence;
  }

  LearningCandidate copyWith({
    String? id,
    String? source,
    double? confidence,
    String? reason,
    String? evidence,
    Map<String, dynamic>? fact,
    LearningCandidateStatus? status,
  }) {
    return LearningCandidate(
      id: id ?? this.id,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      reason: reason ?? this.reason,
      evidence: evidence ?? this.evidence,
      fact: fact ?? this.fact,
      status: status ?? this.status,
    );
  }
}

final class MemoryFact {
  const MemoryFact({
    required this.source,
    required this.id,
    required this.title,
    required this.content,
    required this.disabled,
    required this.fact,
  });

  final String source;
  final String id;
  final String title;
  final String content;
  final bool disabled;
  final Map<String, dynamic> fact;

  String get sourceLabel {
    return switch (source) {
      'profile' => 'Profile',
      'habit' => 'Habit',
      'graph' => 'Graph',
      _ => source,
    };
  }

  MemoryFact copyWith({
    String? source,
    String? id,
    String? title,
    String? content,
    bool? disabled,
    Map<String, dynamic>? fact,
  }) {
    return MemoryFact(
      source: source ?? this.source,
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      disabled: disabled ?? this.disabled,
      fact: fact ?? this.fact,
    );
  }
}

final class MemoryFactEditRequest {
  const MemoryFactEditRequest({
    required this.source,
    required this.id,
    required this.title,
    required this.content,
  });

  final String source;
  final String id;
  final String title;
  final String content;
}

final class KnowledgeIndexRequest {
  const KnowledgeIndexRequest({required this.target, required this.path});

  final KnowledgeIndexTarget target;
  final String path;
}

final class KnowledgeIndexState {
  const KnowledgeIndexState({
    required this.target,
    required this.path,
    required this.status,
    required this.indexedNodes,
    required this.sourcePaths,
    this.errorMessage,
  });

  final KnowledgeIndexTarget target;
  final String path;
  final KnowledgeIndexStatus status;
  final int indexedNodes;
  final List<String> sourcePaths;
  final String? errorMessage;

  KnowledgeIndexState copyWith({
    KnowledgeIndexTarget? target,
    String? path,
    KnowledgeIndexStatus? status,
    int? indexedNodes,
    List<String>? sourcePaths,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return KnowledgeIndexState(
      target: target ?? this.target,
      path: path ?? this.path,
      status: status ?? this.status,
      indexedNodes: indexedNodes ?? this.indexedNodes,
      sourcePaths: sourcePaths ?? this.sourcePaths,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

final class RetrievalEvaluationCaseResult {
  const RetrievalEvaluationCaseResult({
    required this.name,
    required this.query,
    required this.hit,
    required this.precisionAtK,
    required this.firstRelevantRank,
    required this.reciprocalRank,
  });

  final String name;
  final String query;
  final bool hit;
  final double precisionAtK;
  final int? firstRelevantRank;
  final double reciprocalRank;

  factory RetrievalEvaluationCaseResult.fromMap(Map<String, dynamic> value) {
    return RetrievalEvaluationCaseResult(
      name: _stringFrom(value['name']),
      query: _stringFrom(value['query']),
      hit: value['hit'] == true,
      precisionAtK: _doubleFrom(value['precisionAtK']),
      firstRelevantRank: value['firstRelevantRank'] is num
          ? (value['firstRelevantRank'] as num).toInt()
          : null,
      reciprocalRank: _doubleFrom(value['reciprocalRank']),
    );
  }
}

final class RetrievalEvaluationReport {
  const RetrievalEvaluationReport({
    required this.k,
    required this.hitRate,
    required this.precisionAtK,
    required this.mrr,
    required this.sourceShare,
    required this.cases,
  });

  final int k;
  final double hitRate;
  final double precisionAtK;
  final double mrr;
  final Map<String, double> sourceShare;
  final List<RetrievalEvaluationCaseResult> cases;

  factory RetrievalEvaluationReport.fromMap(Map<String, dynamic> value) {
    final rawCases = value['cases'];
    return RetrievalEvaluationReport(
      k: value['k'] is num ? (value['k'] as num).toInt() : 0,
      hitRate: _doubleFrom(value['hitRate']),
      precisionAtK: _doubleFrom(value['precisionAtK']),
      mrr: _doubleFrom(value['mrr']),
      sourceShare: _doubleMapFrom(value['sourceShare']),
      cases: rawCases is List
          ? [
              for (final rawCase in rawCases)
                if (rawCase is Map)
                  RetrievalEvaluationCaseResult.fromMap(
                    Map<String, dynamic>.from(rawCase),
                  ),
            ]
          : const [],
    );
  }
}

final class RetrievalEvaluationState {
  const RetrievalEvaluationState({
    required this.status,
    this.report,
    this.errorMessage,
  });

  final RetrievalEvaluationStatus status;
  final RetrievalEvaluationReport? report;
  final String? errorMessage;

  RetrievalEvaluationState copyWith({
    RetrievalEvaluationStatus? status,
    RetrievalEvaluationReport? report,
    String? errorMessage,
    bool clearReport = false,
    bool clearErrorMessage = false,
  }) {
    return RetrievalEvaluationState(
      status: status ?? this.status,
      report: clearReport ? null : report ?? this.report,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

final class SkillSummary {
  const SkillSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
    required this.status,
    this.path,
    this.serverId,
    this.unavailableReason,
  });

  final String id;
  final String name;
  final String description;
  final String source;
  final String status;
  final String? path;
  final String? serverId;
  final String? unavailableReason;
}

final class McpCapabilityItem {
  const McpCapabilityItem({required this.name, this.description});

  final String name;
  final String? description;
}

final class McpConnectionTestResult {
  const McpConnectionTestResult({
    required this.serverId,
    required this.status,
    required this.message,
    required this.durationMs,
    required this.checkedAt,
    this.tools = const [],
    this.resources = const [],
    this.prompts = const [],
    this.skills = const [],
  });

  final String serverId;
  final String status;
  final String message;
  final int durationMs;
  final String checkedAt;
  final List<McpCapabilityItem> tools;
  final List<McpCapabilityItem> resources;
  final List<McpCapabilityItem> prompts;
  final List<SkillSummary> skills;
}

final class McpServerSummary {
  const McpServerSummary({
    required this.id,
    required this.name,
    required this.transport,
    required this.scope,
    required this.enabled,
    required this.status,
    required this.toolCount,
    required this.resourceCount,
    required this.skillCount,
    this.lastError,
    this.command,
    this.args,
    this.url,
    this.headers,
    this.env,
  });

  final String id;
  final String name;
  final String transport;
  final String scope;
  final bool enabled;
  final String status;
  final int toolCount;
  final int resourceCount;
  final int skillCount;
  final String? lastError;
  final String? command;
  final List<String>? args;
  final String? url;
  final Map<String, String>? headers;
  final Map<String, String>? env;

  McpServerSummary copyWith({
    String? id,
    String? name,
    String? transport,
    String? scope,
    bool? enabled,
    String? status,
    int? toolCount,
    int? resourceCount,
    int? skillCount,
    String? lastError,
    String? command,
    List<String>? args,
    String? url,
    Map<String, String>? headers,
    Map<String, String>? env,
  }) {
    return McpServerSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      transport: transport ?? this.transport,
      scope: scope ?? this.scope,
      enabled: enabled ?? this.enabled,
      status: status ?? this.status,
      toolCount: toolCount ?? this.toolCount,
      resourceCount: resourceCount ?? this.resourceCount,
      skillCount: skillCount ?? this.skillCount,
      lastError: lastError ?? this.lastError,
      command: command ?? this.command,
      args: args ?? this.args,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      env: env ?? this.env,
    );
  }
}

final class McpServerDraft {
  const McpServerDraft({
    this.id,
    required this.name,
    required this.transport,
    this.scope,
    this.command,
    this.args,
    this.url,
    this.headers,
    this.env,
    this.enabled,
  });

  final String? id;
  final String name;
  final String transport;
  final String? scope;
  final String? command;
  final List<String>? args;
  final String? url;
  final Map<String, String>? headers;
  final Map<String, String>? env;
  final bool? enabled;
}

final class ExtensionsState {
  const ExtensionsState({
    required this.skillsStatus,
    required this.skills,
    required this.mcpStatus,
    required this.mcpServers,
    this.mcpTestResults = const {},
    this.skillsErrorMessage,
    this.mcpErrorMessage,
  });

  final ExtensionInventoryStatus skillsStatus;
  final List<SkillSummary> skills;
  final String? skillsErrorMessage;
  final ExtensionInventoryStatus mcpStatus;
  final List<McpServerSummary> mcpServers;
  final Map<String, McpConnectionTestResult> mcpTestResults;
  final String? mcpErrorMessage;

  ExtensionsState copyWith({
    ExtensionInventoryStatus? skillsStatus,
    List<SkillSummary>? skills,
    String? skillsErrorMessage,
    bool clearSkillsErrorMessage = false,
    ExtensionInventoryStatus? mcpStatus,
    List<McpServerSummary>? mcpServers,
    Map<String, McpConnectionTestResult>? mcpTestResults,
    String? mcpErrorMessage,
    bool clearMcpErrorMessage = false,
  }) {
    return ExtensionsState(
      skillsStatus: skillsStatus ?? this.skillsStatus,
      skills: skills ?? this.skills,
      skillsErrorMessage: clearSkillsErrorMessage
          ? null
          : skillsErrorMessage ?? this.skillsErrorMessage,
      mcpStatus: mcpStatus ?? this.mcpStatus,
      mcpServers: mcpServers ?? this.mcpServers,
      mcpTestResults: mcpTestResults ?? this.mcpTestResults,
      mcpErrorMessage: clearMcpErrorMessage
          ? null
          : mcpErrorMessage ?? this.mcpErrorMessage,
    );
  }
}

final class ActiveExtensionsState {
  const ActiveExtensionsState({
    this.mcpServers = const [],
    this.skills = const [],
    this.warnings = const [],
  });

  final List<String> mcpServers;
  final List<String> skills;
  final List<String> warnings;

  int get totalCount => mcpServers.length + skills.length;
  bool get hasWarnings => warnings.isNotEmpty;
}

final class DiagnosticLogEntry {
  const DiagnosticLogEntry({
    required this.id,
    required this.severity,
    required this.title,
    required this.detail,
    required this.timestampLabel,
  });

  final String id;
  final DiagnosticSeverity severity;
  final String title;
  final String detail;
  final String timestampLabel;
}

final class TurnTimelineEntry {
  const TurnTimelineEntry({
    required this.id,
    required this.requestId,
    required this.stage,
    required this.status,
    required this.timestamp,
    this.durationMs,
    this.detail,
    this.toolName,
    this.toolUseId,
  });

  final String id;
  final String requestId;
  final String stage;
  final String status;
  final String timestamp;
  final int? durationMs;
  final String? detail;
  final String? toolName;
  final String? toolUseId;

  String get stageLabel {
    return switch (stage) {
      'bridge_received' => 'Bridge received',
      'context_retrieval' => 'Context retrieval',
      'session_start' => 'Session',
      'extension_runtime' => 'Extensions',
      'sdk_query' => 'Provider request',
      'sdk_first_message' => 'First SDK message',
      'sdk_stream_event' => 'First stream event',
      'sdk_thinking_delta' => 'First thinking delta',
      'sdk_text_delta' => 'First text delta',
      'permission_wait' => 'Permission wait',
      _ => stage,
    };
  }

  String get durationLabel {
    final value = durationMs;
    if (value == null) return '';
    if (value < 1000) return '$value ms';
    return '${(value / 1000).toStringAsFixed(1)} s';
  }
}

final class MarketplaceExtension {
  const MarketplaceExtension({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.source,
    required this.installed,
    required this.enabled,
  });

  final String id;
  final String name;
  final String description;
  final String category;
  final String source;
  final bool installed;
  final bool enabled;
}

final class ProviderSettings {
  const ProviderSettings({
    required this.providerName,
    required this.modelName,
    required this.baseUrl,
    required this.bridgeUrl,
    required this.apiKeyConfigured,
  });

  final String providerName;
  final String modelName;
  final String baseUrl;
  final String bridgeUrl;
  final bool apiKeyConfigured;

  ProviderSettings copyWith({
    String? providerName,
    String? modelName,
    String? baseUrl,
    String? bridgeUrl,
    bool? apiKeyConfigured,
  }) {
    return ProviderSettings(
      providerName: providerName ?? this.providerName,
      modelName: modelName ?? this.modelName,
      baseUrl: baseUrl ?? this.baseUrl,
      bridgeUrl: bridgeUrl ?? this.bridgeUrl,
      apiKeyConfigured: apiKeyConfigured ?? this.apiKeyConfigured,
    );
  }
}

final class ProviderConnectionRequest {
  const ProviderConnectionRequest({
    required this.providerName,
    required this.modelName,
    required this.baseUrl,
    required this.apiKey,
  });

  final String providerName;
  final String modelName;
  final String baseUrl;
  final String apiKey;

  String get routeKey => '$providerName::$modelName::$baseUrl';
}

final class PersonalSettings {
  const PersonalSettings({
    required this.displayName,
    required this.defaultWorkingDirectory,
    required this.themePreference,
    required this.fontScale,
    required this.autoConnectBridge,
    required this.agentEvalTraceEnabled,
    this.fullRecentTranscriptContext = false,
    this.thinkingModeEnabled = true,
  });

  final String displayName;
  final String defaultWorkingDirectory;
  final ThemePreference themePreference;
  final double fontScale;
  final bool autoConnectBridge;
  final bool agentEvalTraceEnabled;
  final bool fullRecentTranscriptContext;
  final bool thinkingModeEnabled;

  PersonalSettings copyWith({
    String? displayName,
    String? defaultWorkingDirectory,
    ThemePreference? themePreference,
    double? fontScale,
    bool? autoConnectBridge,
    bool? agentEvalTraceEnabled,
    bool? fullRecentTranscriptContext,
    bool? thinkingModeEnabled,
  }) {
    return PersonalSettings(
      displayName: displayName ?? this.displayName,
      defaultWorkingDirectory:
          defaultWorkingDirectory ?? this.defaultWorkingDirectory,
      themePreference: themePreference ?? this.themePreference,
      fontScale: fontScale ?? this.fontScale,
      autoConnectBridge: autoConnectBridge ?? this.autoConnectBridge,
      agentEvalTraceEnabled:
          agentEvalTraceEnabled ?? this.agentEvalTraceEnabled,
      fullRecentTranscriptContext:
          fullRecentTranscriptContext ?? this.fullRecentTranscriptContext,
      thinkingModeEnabled: thinkingModeEnabled ?? this.thinkingModeEnabled,
    );
  }
}

final class InspectorSelection {
  const InspectorSelection({required this.kind, this.itemId});

  final InspectorKind kind;
  final String? itemId;

  InspectorSelection copyWith({InspectorKind? kind, String? itemId}) {
    return InspectorSelection(
      kind: kind ?? this.kind,
      itemId: itemId ?? this.itemId,
    );
  }
}

final class WorkbenchState {
  const WorkbenchState({
    required this.connectionStatus,
    required this.destination,
    required this.sessionSearchQuery,
    required this.sessions,
    required this.activeSessionId,
    required this.messages,
    required this.toolRuns,
    required this.permissionRequests,
    required this.retrievedContextItems,
    required this.learningCandidates,
    required this.memoryFacts,
    required this.retrievalEvaluation,
    required this.extensions,
    required this.activeExtensions,
    required this.diagnosticLogs,
    required this.turnTimeline,
    required this.bridgeLaunchStatus,
    required this.diagnosticsReportCopyStatus,
    required this.provider,
    required this.personal,
    required this.knowledgeIndex,
    required this.inspector,
    required this.isStreaming,
    required this.bridgeUrl,
    required this.setupAssistantDismissed,
    this.errorMessage,
  });

  final ConnectionStatus connectionStatus;
  final WorkbenchDestination destination;
  final String sessionSearchQuery;
  final List<SessionSummary> sessions;
  final String activeSessionId;
  final List<ChatMessage> messages;
  final List<ToolRun> toolRuns;
  final List<PermissionRequest> permissionRequests;
  final List<RetrievedContextItem> retrievedContextItems;
  final List<LearningCandidate> learningCandidates;
  final List<MemoryFact> memoryFacts;
  final RetrievalEvaluationState retrievalEvaluation;
  final ExtensionsState extensions;
  final ActiveExtensionsState activeExtensions;
  final List<DiagnosticLogEntry> diagnosticLogs;
  final List<TurnTimelineEntry> turnTimeline;
  final BridgeLaunchStatus bridgeLaunchStatus;
  final DiagnosticsReportCopyStatus diagnosticsReportCopyStatus;
  final ProviderSettings provider;
  final PersonalSettings personal;
  final KnowledgeIndexState knowledgeIndex;
  final InspectorSelection inspector;
  final bool isStreaming;
  final String bridgeUrl;
  final bool setupAssistantDismissed;
  final String? errorMessage;

  SessionSummary? get activeSession {
    for (final session in sessions) {
      if (session.id == activeSessionId) return session;
    }
    return sessions.isEmpty ? null : sessions.first;
  }

  List<SessionSummary> get filteredSessions {
    final query = sessionSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return sessions;
    return [
      for (final session in sessions)
        if (session.title.toLowerCase().contains(query) ||
            session.subtitle.toLowerCase().contains(query) ||
            (session.sdkSessionId?.toLowerCase().contains(query) ?? false))
          session,
    ];
  }

  bool get shouldShowSetupAssistant {
    return !setupAssistantDismissed &&
        destination == WorkbenchDestination.chat &&
        (connectionStatus != ConnectionStatus.connected ||
            !provider.apiKeyConfigured);
  }

  WorkbenchState copyWith({
    ConnectionStatus? connectionStatus,
    WorkbenchDestination? destination,
    String? sessionSearchQuery,
    List<SessionSummary>? sessions,
    String? activeSessionId,
    List<ChatMessage>? messages,
    List<ToolRun>? toolRuns,
    List<PermissionRequest>? permissionRequests,
    List<RetrievedContextItem>? retrievedContextItems,
    List<LearningCandidate>? learningCandidates,
    List<MemoryFact>? memoryFacts,
    RetrievalEvaluationState? retrievalEvaluation,
    ExtensionsState? extensions,
    ActiveExtensionsState? activeExtensions,
    List<DiagnosticLogEntry>? diagnosticLogs,
    List<TurnTimelineEntry>? turnTimeline,
    BridgeLaunchStatus? bridgeLaunchStatus,
    DiagnosticsReportCopyStatus? diagnosticsReportCopyStatus,
    ProviderSettings? provider,
    PersonalSettings? personal,
    KnowledgeIndexState? knowledgeIndex,
    InspectorSelection? inspector,
    bool? isStreaming,
    String? bridgeUrl,
    bool? setupAssistantDismissed,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return WorkbenchState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      destination: destination ?? this.destination,
      sessionSearchQuery: sessionSearchQuery ?? this.sessionSearchQuery,
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      messages: messages ?? this.messages,
      toolRuns: toolRuns ?? this.toolRuns,
      permissionRequests: permissionRequests ?? this.permissionRequests,
      retrievedContextItems:
          retrievedContextItems ?? this.retrievedContextItems,
      learningCandidates: learningCandidates ?? this.learningCandidates,
      memoryFacts: memoryFacts ?? this.memoryFacts,
      retrievalEvaluation: retrievalEvaluation ?? this.retrievalEvaluation,
      extensions: extensions ?? this.extensions,
      activeExtensions: activeExtensions ?? this.activeExtensions,
      diagnosticLogs: diagnosticLogs ?? this.diagnosticLogs,
      turnTimeline: turnTimeline ?? this.turnTimeline,
      bridgeLaunchStatus: bridgeLaunchStatus ?? this.bridgeLaunchStatus,
      diagnosticsReportCopyStatus:
          diagnosticsReportCopyStatus ?? this.diagnosticsReportCopyStatus,
      provider: provider ?? this.provider,
      personal: personal ?? this.personal,
      knowledgeIndex: knowledgeIndex ?? this.knowledgeIndex,
      inspector: inspector ?? this.inspector,
      isStreaming: isStreaming ?? this.isStreaming,
      bridgeUrl: bridgeUrl ?? this.bridgeUrl,
      setupAssistantDismissed:
          setupAssistantDismissed ?? this.setupAssistantDismissed,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

WorkbenchState createInitialWorkbenchState() {
  const bridgeUrl = defaultWorkbenchBridgeUrl;
  final defaultWorkingDirectory = defaultWorkbenchWorkingDirectory();
  return WorkbenchState(
    connectionStatus: ConnectionStatus.disconnected,
    destination: WorkbenchDestination.chat,
    sessionSearchQuery: '',
    sessions: [
      SessionSummary(
        id: 'ui-session-1',
        title: 'New chat',
        subtitle: defaultWorkingDirectory,
        status: SessionStatus.idle,
        updatedLabel: 'Now',
      ),
    ],
    activeSessionId: 'ui-session-1',
    messages: [],
    toolRuns: [],
    permissionRequests: [],
    retrievedContextItems: [],
    learningCandidates: [],
    memoryFacts: [],
    retrievalEvaluation: RetrievalEvaluationState(
      status: RetrievalEvaluationStatus.idle,
    ),
    extensions: ExtensionsState(
      skillsStatus: ExtensionInventoryStatus.idle,
      skills: [],
      mcpStatus: ExtensionInventoryStatus.idle,
      mcpServers: [],
    ),
    activeExtensions: ActiveExtensionsState(),
    diagnosticLogs: [],
    turnTimeline: [],
    bridgeLaunchStatus: BridgeLaunchStatus.idle,
    diagnosticsReportCopyStatus: DiagnosticsReportCopyStatus.idle,
    provider: const ProviderSettings(
      providerName: 'OpenAI Compatible',
      modelName: 'gpt-5.5',
      baseUrl: 'https://api.openai.com/v1',
      bridgeUrl: bridgeUrl,
      apiKeyConfigured: false,
    ),
    personal: PersonalSettings(
      displayName: 'Developer',
      defaultWorkingDirectory: defaultWorkingDirectory,
      themePreference: ThemePreference.system,
      fontScale: 1,
      autoConnectBridge: true,
      agentEvalTraceEnabled: false,
    ),
    knowledgeIndex: const KnowledgeIndexState(
      target: KnowledgeIndexTarget.directory,
      path: 'docs',
      status: KnowledgeIndexStatus.idle,
      indexedNodes: 0,
      sourcePaths: [],
    ),
    inspector: const InspectorSelection(kind: InspectorKind.context),
    isStreaming: false,
    bridgeUrl: bridgeUrl,
    setupAssistantDismissed: false,
  );
}

String _stringFrom(Object? value) {
  return value is String ? value : '';
}

double _doubleFrom(Object? value) {
  return value is num ? value.toDouble() : 0;
}

Map<String, double> _doubleMapFrom(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.value is num)
        entry.key.toString(): (entry.value as num).toDouble(),
  };
}
