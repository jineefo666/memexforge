import 'dart:convert';

const bridgeProtocolVersion = 1;

sealed class BridgeServerMessage {
  const BridgeServerMessage();
}

final class BridgeHelloMessage extends BridgeServerMessage {
  const BridgeHelloMessage({required this.protocolVersion});

  final int protocolVersion;
}

final class BridgeSdkMessage extends BridgeServerMessage {
  const BridgeSdkMessage({
    required this.requestId,
    required this.sessionId,
    required this.message,
  });

  final String requestId;
  final String sessionId;
  final Map<String, dynamic> message;
}

final class BridgeErrorMessage extends BridgeServerMessage {
  const BridgeErrorMessage({
    this.requestId,
    required this.code,
    required this.message,
  });

  final String? requestId;
  final String code;
  final String message;
}

final class BridgeClosedMessage extends BridgeServerMessage {
  const BridgeClosedMessage({required this.requestId});

  final String requestId;
}

final class BridgeExtensionRuntimeMessage extends BridgeServerMessage {
  const BridgeExtensionRuntimeMessage({
    required this.requestId,
    required this.mcpServers,
    required this.skills,
    required this.warnings,
  });

  final String requestId;
  final List<String> mcpServers;
  final List<String> skills;
  final List<String> warnings;
}

final class BridgeAgentEvalTraceStatusMessage extends BridgeServerMessage {
  const BridgeAgentEvalTraceStatusMessage({
    required this.requestId,
    required this.enabled,
    required this.tracePath,
  });

  final String requestId;
  final bool enabled;
  final String tracePath;
}

final class BridgeTurnTimelineMessage extends BridgeServerMessage {
  const BridgeTurnTimelineMessage({
    required this.requestId,
    required this.stage,
    required this.status,
    required this.at,
    this.durationMs,
    this.detail,
    this.toolName,
    this.toolUseId,
  });

  final String requestId;
  final String stage;
  final String status;
  final String at;
  final int? durationMs;
  final String? detail;
  final String? toolName;
  final String? toolUseId;
}

final class BridgeSkillSummary {
  const BridgeSkillSummary({
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

final class BridgeMcpServerSummary {
  const BridgeMcpServerSummary({
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
}

final class BridgeMcpServerDraft {
  const BridgeMcpServerDraft({
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

  Map<String, dynamic> toJson() {
    final value = <String, dynamic>{'name': name, 'transport': transport};
    if (id != null) value['id'] = id;
    if (scope != null) value['scope'] = scope;
    if (command != null) value['command'] = command;
    if (args != null) value['args'] = args;
    if (url != null) value['url'] = url;
    if (headers != null && headers!.isNotEmpty) value['headers'] = headers;
    if (env != null && env!.isNotEmpty) value['env'] = env;
    if (enabled != null) value['enabled'] = enabled;
    return value;
  }
}

final class BridgeMcpCapabilityItem {
  const BridgeMcpCapabilityItem({required this.name, this.description});

  final String name;
  final String? description;
}

final class BridgeSkillsSnapshotMessage extends BridgeServerMessage {
  const BridgeSkillsSnapshotMessage({
    required this.requestId,
    required this.skills,
  });

  final String requestId;
  final List<BridgeSkillSummary> skills;
}

final class BridgeSkillImportedMessage extends BridgeServerMessage {
  const BridgeSkillImportedMessage({
    required this.requestId,
    required this.skill,
  });

  final String requestId;
  final BridgeSkillSummary skill;
}

final class BridgeSkillUpdatedMessage extends BridgeServerMessage {
  const BridgeSkillUpdatedMessage({
    required this.requestId,
    required this.skill,
  });

  final String requestId;
  final BridgeSkillSummary skill;
}

final class BridgeMcpServersSnapshotMessage extends BridgeServerMessage {
  const BridgeMcpServersSnapshotMessage({
    required this.requestId,
    required this.servers,
  });

  final String requestId;
  final List<BridgeMcpServerSummary> servers;
}

final class BridgeMcpServerCapabilitiesMessage extends BridgeServerMessage {
  const BridgeMcpServerCapabilitiesMessage({
    required this.requestId,
    required this.serverId,
    required this.tools,
    required this.resources,
    required this.prompts,
    required this.skills,
  });

  final String requestId;
  final String serverId;
  final List<BridgeMcpCapabilityItem> tools;
  final List<BridgeMcpCapabilityItem> resources;
  final List<BridgeMcpCapabilityItem> prompts;
  final List<BridgeSkillSummary> skills;
}

final class BridgeMcpServerTestResultMessage extends BridgeServerMessage {
  const BridgeMcpServerTestResultMessage({
    required this.requestId,
    required this.serverId,
    required this.status,
    required this.message,
    required this.durationMs,
    required this.checkedAt,
    required this.tools,
    required this.resources,
    required this.prompts,
    required this.skills,
  });

  final String requestId;
  final String serverId;
  final String status;
  final String message;
  final int durationMs;
  final String checkedAt;
  final List<BridgeMcpCapabilityItem> tools;
  final List<BridgeMcpCapabilityItem> resources;
  final List<BridgeMcpCapabilityItem> prompts;
  final List<BridgeSkillSummary> skills;
}

final class BridgeMcpServerSavedMessage extends BridgeServerMessage {
  const BridgeMcpServerSavedMessage({
    required this.requestId,
    required this.server,
  });

  final String requestId;
  final BridgeMcpServerSummary server;
}

final class BridgeMcpServerDeletedMessage extends BridgeServerMessage {
  const BridgeMcpServerDeletedMessage({
    required this.requestId,
    required this.serverId,
  });

  final String requestId;
  final String serverId;
}

final class BridgeContextRetrievalMessage extends BridgeServerMessage {
  const BridgeContextRetrievalMessage({
    required this.requestId,
    required this.result,
  });

  final String requestId;
  final Map<String, dynamic> result;
}

final class BridgeContextEvaluationCase {
  const BridgeContextEvaluationCase({
    required this.name,
    required this.query,
    required this.relevantIds,
  });

  final String name;
  final String query;
  final List<String> relevantIds;

  Map<String, dynamic> toJson() {
    return {'name': name, 'query': query, 'relevantIds': relevantIds};
  }
}

final class BridgeContextEvaluationResultMessage extends BridgeServerMessage {
  const BridgeContextEvaluationResultMessage({
    required this.requestId,
    required this.result,
  });

  final String requestId;
  final Map<String, dynamic> result;
}

final class BridgeContextEvaluationErrorMessage extends BridgeServerMessage {
  const BridgeContextEvaluationErrorMessage({
    required this.requestId,
    required this.code,
    required this.message,
  });

  final String requestId;
  final String code;
  final String message;
}

final class BridgeContextIndexProgressMessage extends BridgeServerMessage {
  const BridgeContextIndexProgressMessage({
    required this.requestId,
    required this.target,
    required this.path,
    required this.status,
  });

  final String requestId;
  final String target;
  final String path;
  final String status;
}

final class BridgeContextIndexResultMessage extends BridgeServerMessage {
  const BridgeContextIndexResultMessage({
    required this.requestId,
    required this.target,
    required this.path,
    required this.indexedNodes,
    required this.sourcePaths,
  });

  final String requestId;
  final String target;
  final String path;
  final int indexedNodes;
  final List<String> sourcePaths;
}

final class BridgeContextIndexErrorMessage extends BridgeServerMessage {
  const BridgeContextIndexErrorMessage({
    required this.requestId,
    required this.code,
    required this.message,
  });

  final String requestId;
  final String code;
  final String message;
}

final class BridgeLearningCandidate {
  const BridgeLearningCandidate({
    required this.source,
    required this.confidence,
    required this.reason,
    required this.evidence,
    required this.fact,
  });

  final String source;
  final double confidence;
  final String reason;
  final String evidence;
  final Map<String, dynamic> fact;
}

final class BridgeContextLearnResultMessage extends BridgeServerMessage {
  const BridgeContextLearnResultMessage({
    required this.requestId,
    required this.candidates,
  });

  final String requestId;
  final List<BridgeLearningCandidate> candidates;
}

final class BridgeContextLearnErrorMessage extends BridgeServerMessage {
  const BridgeContextLearnErrorMessage({
    required this.requestId,
    required this.code,
    required this.message,
  });

  final String requestId;
  final String code;
  final String message;
}

final class BridgeContextFactUpsertResultMessage extends BridgeServerMessage {
  const BridgeContextFactUpsertResultMessage({
    required this.requestId,
    required this.source,
    required this.id,
  });

  final String requestId;
  final String source;
  final String id;
}

final class BridgeContextFactUpsertErrorMessage extends BridgeServerMessage {
  const BridgeContextFactUpsertErrorMessage({
    required this.requestId,
    required this.code,
    required this.message,
  });

  final String requestId;
  final String code;
  final String message;
}

final class BridgeMemoryFact {
  const BridgeMemoryFact({
    required this.source,
    required this.disabled,
    required this.fact,
  });

  final String source;
  final bool disabled;
  final Map<String, dynamic> fact;
}

final class BridgeContextFactsListResultMessage extends BridgeServerMessage {
  const BridgeContextFactsListResultMessage({
    required this.requestId,
    required this.facts,
  });

  final String requestId;
  final List<BridgeMemoryFact> facts;
}

final class BridgeContextFactsListErrorMessage extends BridgeServerMessage {
  const BridgeContextFactsListErrorMessage({
    required this.requestId,
    required this.code,
    required this.message,
  });

  final String requestId;
  final String code;
  final String message;
}

final class BridgeContextFactDeleteResultMessage extends BridgeServerMessage {
  const BridgeContextFactDeleteResultMessage({
    required this.requestId,
    required this.source,
    required this.id,
  });

  final String requestId;
  final String source;
  final String id;
}

final class BridgeContextFactDeleteErrorMessage extends BridgeServerMessage {
  const BridgeContextFactDeleteErrorMessage({
    required this.requestId,
    required this.code,
    required this.message,
  });

  final String requestId;
  final String code;
  final String message;
}

final class BridgeTranscriptMessage {
  const BridgeTranscriptMessage({
    required this.id,
    required this.role,
    required this.content,
    this.timestamp,
  });

  final String id;
  final String role;
  final String content;
  final String? timestamp;

  Map<String, dynamic> toJson() {
    final value = <String, dynamic>{'id': id, 'role': role, 'content': content};
    if (timestamp != null) value['timestamp'] = timestamp;
    return value;
  }
}

final class BridgeAttachment {
  const BridgeAttachment({
    required this.id,
    required this.name,
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    this.path,
    this.content,
    this.dataBase64,
  });

  final String id;
  final String name;
  final String kind;
  final String mimeType;
  final int sizeBytes;
  final String? path;
  final String? content;
  final String? dataBase64;

  Map<String, dynamic> toJson() {
    final value = <String, dynamic>{
      'id': id,
      'name': name,
      'kind': kind,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
    };
    if (path != null) value['path'] = path;
    if (content != null) value['content'] = content;
    if (dataBase64 != null) value['dataBase64'] = dataBase64;
    return value;
  }
}

final class BridgeProviderConfig {
  const BridgeProviderConfig({
    required this.providerName,
    required this.modelName,
    required this.baseUrl,
    required this.apiKey,
  });

  final String providerName;
  final String modelName;
  final String baseUrl;
  final String apiKey;

  Map<String, dynamic> toJson() {
    return {
      'providerName': providerName,
      'modelName': modelName,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
    };
  }
}

String encodeStartMessage({
  required String requestId,
  required String cwd,
  required String prompt,
  String? sessionId,
  String? model,
  String? permissionMode,
  String? contextTranscriptMode,
  String? thinkingMode,
  List<BridgeTranscriptMessage> transcript = const [],
  List<BridgeAttachment> attachments = const [],
  BridgeProviderConfig? provider,
}) {
  final message = <String, dynamic>{
    'type': 'start',
    'requestId': requestId,
    'cwd': cwd,
    'prompt': prompt,
  };
  if (sessionId != null) message['sessionId'] = sessionId;
  if (model != null) message['model'] = model;
  if (permissionMode != null) message['permissionMode'] = permissionMode;
  if (contextTranscriptMode != null) {
    message['contextTranscriptMode'] = contextTranscriptMode;
  }
  if (thinkingMode != null) message['thinkingMode'] = thinkingMode;
  if (transcript.isNotEmpty) {
    message['transcript'] = [for (final entry in transcript) entry.toJson()];
  }
  if (attachments.isNotEmpty) {
    message['attachments'] = [
      for (final attachment in attachments) attachment.toJson(),
    ];
  }
  if (provider != null) message['provider'] = provider.toJson();
  return _encode(message);
}

String encodeRetrieveContextMessage({
  required String requestId,
  required String query,
  String? cwd,
  String? memoryDir,
  List<String>? sources,
  List<BridgeTranscriptMessage> transcript = const [],
  int? maxItems,
  int? maxCharacters,
}) {
  final message = <String, dynamic>{
    'type': 'retrieve_context',
    'requestId': requestId,
    'query': query,
  };
  if (cwd != null) message['cwd'] = cwd;
  if (memoryDir != null) message['memoryDir'] = memoryDir;
  if (sources != null) message['sources'] = sources;
  if (transcript.isNotEmpty) {
    message['transcript'] = [for (final entry in transcript) entry.toJson()];
  }
  if (maxItems != null) message['maxItems'] = maxItems;
  if (maxCharacters != null) message['maxCharacters'] = maxCharacters;
  return _encode(message);
}

String encodeContextEvaluationMessage({
  required String requestId,
  required List<BridgeContextEvaluationCase> cases,
  String? cwd,
  List<String>? sources,
  int? k,
  int? maxItems,
  int? maxCharacters,
}) {
  final message = <String, dynamic>{
    'type': 'context_eval',
    'requestId': requestId,
    'cases': [for (final testCase in cases) testCase.toJson()],
  };
  if (cwd != null) message['cwd'] = cwd;
  if (sources != null) message['sources'] = sources;
  if (k != null) message['k'] = k;
  if (maxItems != null) message['maxItems'] = maxItems;
  if (maxCharacters != null) message['maxCharacters'] = maxCharacters;
  return _encode(message);
}

String encodeContextLearnMessage({
  required String requestId,
  required List<BridgeTranscriptMessage> transcript,
  int? maxCandidates,
}) {
  final message = <String, dynamic>{
    'type': 'context_learn',
    'requestId': requestId,
    'transcript': [for (final entry in transcript) entry.toJson()],
  };
  if (maxCandidates != null) message['maxCandidates'] = maxCandidates;
  return _encode(message);
}

String encodeContextFactUpsertMessage({
  required String requestId,
  required String cwd,
  required String source,
  required Map<String, dynamic> fact,
}) {
  return _encode({
    'type': 'context_fact_upsert',
    'requestId': requestId,
    'cwd': cwd,
    'source': source,
    'fact': fact,
  });
}

String encodeContextFactsListMessage({
  required String requestId,
  required String cwd,
  List<String>? sources,
}) {
  final message = <String, dynamic>{
    'type': 'context_facts_list',
    'requestId': requestId,
    'cwd': cwd,
  };
  if (sources != null) message['sources'] = sources;
  return _encode(message);
}

String encodeContextFactDeleteMessage({
  required String requestId,
  required String cwd,
  required String source,
  required String id,
}) {
  return _encode({
    'type': 'context_fact_delete',
    'requestId': requestId,
    'cwd': cwd,
    'source': source,
    'id': id,
  });
}

String encodeSkillsListMessage({
  required String requestId,
  bool? includeDisabled,
}) {
  final message = <String, dynamic>{
    'type': 'skills_list',
    'requestId': requestId,
  };
  if (includeDisabled != null) {
    message['includeDisabled'] = includeDisabled;
  }
  return _encode(message);
}

String encodeSkillImportMessage({
  required String requestId,
  required String path,
}) {
  return _encode({
    'type': 'skill_import',
    'requestId': requestId,
    'path': path,
  });
}

String encodeSkillSetEnabledMessage({
  required String requestId,
  required String skillId,
  required bool enabled,
}) {
  return _encode({
    'type': 'skill_set_enabled',
    'requestId': requestId,
    'skillId': skillId,
    'enabled': enabled,
  });
}

String encodeSkillRefreshMessage({required String requestId}) {
  return _encode({'type': 'skill_refresh', 'requestId': requestId});
}

String encodeMcpServersListMessage({
  required String requestId,
  String? cwd,
  bool? includeDisabled,
}) {
  final message = <String, dynamic>{
    'type': 'mcp_servers_list',
    'requestId': requestId,
  };
  if (cwd != null) {
    message['cwd'] = cwd;
  }
  if (includeDisabled != null) {
    message['includeDisabled'] = includeDisabled;
  }
  return _encode(message);
}

String encodeMcpServerCapabilitiesMessage({
  required String requestId,
  required String serverId,
}) {
  return _encode({
    'type': 'mcp_server_capabilities',
    'requestId': requestId,
    'serverId': serverId,
  });
}

String encodeMcpServerUpsertMessage({
  required String requestId,
  String? cwd,
  required BridgeMcpServerDraft server,
}) {
  final message = <String, dynamic>{
    'type': 'mcp_server_upsert',
    'requestId': requestId,
    'server': server.toJson(),
  };
  if (cwd != null) message['cwd'] = cwd;
  return _encode(message);
}

String encodeMcpServerSetEnabledMessage({
  required String requestId,
  String? cwd,
  required String serverId,
  required bool enabled,
}) {
  final message = <String, dynamic>{
    'type': 'mcp_server_set_enabled',
    'requestId': requestId,
    'serverId': serverId,
    'enabled': enabled,
  };
  if (cwd != null) message['cwd'] = cwd;
  return _encode(message);
}

String encodeMcpServerDeleteMessage({
  required String requestId,
  String? cwd,
  required String serverId,
}) {
  final message = <String, dynamic>{
    'type': 'mcp_server_delete',
    'requestId': requestId,
    'serverId': serverId,
  };
  if (cwd != null) message['cwd'] = cwd;
  return _encode(message);
}

String encodeMcpServerTestMessage({
  required String requestId,
  String? cwd,
  required BridgeMcpServerDraft server,
}) {
  final message = <String, dynamic>{
    'type': 'mcp_server_test',
    'requestId': requestId,
    'server': server.toJson(),
  };
  if (cwd != null) message['cwd'] = cwd;
  return _encode(message);
}

String encodeContextIndexMessage({
  required String requestId,
  required String cwd,
  required String target,
  required String path,
  Map<String, dynamic>? metadata,
}) {
  final message = <String, dynamic>{
    'type': 'context_index',
    'requestId': requestId,
    'cwd': cwd,
    'target': target,
    'path': path,
  };
  if (metadata != null && metadata.isNotEmpty) {
    message['metadata'] = metadata;
  }
  return _encode(message);
}

String encodePermissionResponseMessage({
  required String requestId,
  required String toolUseId,
  required Map<String, dynamic> decision,
}) {
  return _encode({
    'type': 'permission_response',
    'requestId': requestId,
    'toolUseId': toolUseId,
    'decision': decision,
  });
}

String encodeInterruptMessage(String requestId) {
  return _encode({'type': 'interrupt', 'requestId': requestId});
}

String encodeCloseSessionMessage(String requestId) {
  return _encode({'type': 'close_session', 'requestId': requestId});
}

String encodeAgentEvalTraceSetEnabledMessage({
  required String requestId,
  required bool enabled,
}) {
  return _encode({
    'type': 'agent_eval_trace_set_enabled',
    'requestId': requestId,
    'enabled': enabled,
  });
}

BridgeServerMessage decodeBridgeServerMessage(String rawJson) {
  final decoded = jsonDecode(rawJson);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Bridge server message must be a JSON object.');
  }

  return switch (decoded['type']) {
    'hello' => BridgeHelloMessage(
      protocolVersion: decoded['protocolVersion'] as int,
    ),
    'sdk_message' => BridgeSdkMessage(
      requestId: decoded['requestId'] as String,
      sessionId: decoded['sessionId'] as String,
      message: Map<String, dynamic>.from(decoded['message'] as Map),
    ),
    'error' => BridgeErrorMessage(
      requestId: decoded['requestId'] as String?,
      code: decoded['code'] as String,
      message: decoded['message'] as String,
    ),
    'closed' => BridgeClosedMessage(requestId: decoded['requestId'] as String),
    'turn_timeline' => BridgeTurnTimelineMessage(
      requestId: decoded['requestId'] as String,
      stage: decoded['stage']?.toString() ?? '',
      status: decoded['status']?.toString() ?? '',
      at: decoded['at']?.toString() ?? '',
      durationMs: decoded['durationMs'] is num
          ? (decoded['durationMs'] as num).toInt()
          : null,
      detail: decoded['detail'] as String?,
      toolName: decoded['toolName'] as String?,
      toolUseId: decoded['toolUseId'] as String?,
    ),
    'agent_eval_trace_status' => BridgeAgentEvalTraceStatusMessage(
      requestId: decoded['requestId'] as String,
      enabled: decoded['enabled'] == true,
      tracePath: decoded['tracePath']?.toString() ?? '',
    ),
    'extension_runtime' => _decodeExtensionRuntime(decoded),
    'skills_snapshot' => _decodeSkillsSnapshot(decoded),
    'skill_imported' => BridgeSkillImportedMessage(
      requestId: decoded['requestId'] as String,
      skill: _decodeSkillSummary(
        Map<String, dynamic>.from(decoded['skill'] as Map),
      ),
    ),
    'skill_updated' => BridgeSkillUpdatedMessage(
      requestId: decoded['requestId'] as String,
      skill: _decodeSkillSummary(
        Map<String, dynamic>.from(decoded['skill'] as Map),
      ),
    ),
    'mcp_servers_snapshot' => _decodeMcpServersSnapshot(decoded),
    'mcp_server_capabilities' => _decodeMcpServerCapabilities(decoded),
    'mcp_server_test_result' => _decodeMcpServerTestResult(decoded),
    'mcp_server_saved' => BridgeMcpServerSavedMessage(
      requestId: decoded['requestId'] as String,
      server: _decodeMcpServerSummary(
        Map<String, dynamic>.from(decoded['server'] as Map),
      ),
    ),
    'mcp_server_deleted' => BridgeMcpServerDeletedMessage(
      requestId: decoded['requestId'] as String,
      serverId: decoded['serverId'] as String,
    ),
    'context_retrieval' => BridgeContextRetrievalMessage(
      requestId: decoded['requestId'] as String,
      result: Map<String, dynamic>.from(decoded['result'] as Map),
    ),
    'context_eval_result' => BridgeContextEvaluationResultMessage(
      requestId: decoded['requestId'] as String,
      result: Map<String, dynamic>.from(decoded['result'] as Map),
    ),
    'context_eval_error' => BridgeContextEvaluationErrorMessage(
      requestId: decoded['requestId'] as String,
      code: decoded['code'] as String,
      message: decoded['message'] as String,
    ),
    'context_index_progress' => BridgeContextIndexProgressMessage(
      requestId: decoded['requestId'] as String,
      target: decoded['target'] as String,
      path: decoded['path'] as String,
      status: decoded['status'] as String,
    ),
    'context_index_result' => _decodeContextIndexResult(decoded),
    'context_index_error' => BridgeContextIndexErrorMessage(
      requestId: decoded['requestId'] as String,
      code: decoded['code'] as String,
      message: decoded['message'] as String,
    ),
    'context_learn_result' => _decodeContextLearnResult(decoded),
    'context_learn_error' => BridgeContextLearnErrorMessage(
      requestId: decoded['requestId'] as String,
      code: decoded['code'] as String,
      message: decoded['message'] as String,
    ),
    'context_fact_upsert_result' => _decodeContextFactUpsertResult(decoded),
    'context_fact_upsert_error' => BridgeContextFactUpsertErrorMessage(
      requestId: decoded['requestId'] as String,
      code: decoded['code'] as String,
      message: decoded['message'] as String,
    ),
    'context_facts_list_result' => _decodeContextFactsListResult(decoded),
    'context_facts_list_error' => BridgeContextFactsListErrorMessage(
      requestId: decoded['requestId'] as String,
      code: decoded['code'] as String,
      message: decoded['message'] as String,
    ),
    'context_fact_delete_result' => _decodeContextFactDeleteResult(decoded),
    'context_fact_delete_error' => BridgeContextFactDeleteErrorMessage(
      requestId: decoded['requestId'] as String,
      code: decoded['code'] as String,
      message: decoded['message'] as String,
    ),
    final type => throw FormatException('Unknown bridge server message: $type'),
  };
}

BridgeExtensionRuntimeMessage _decodeExtensionRuntime(
  Map<String, dynamic> decoded,
) {
  final runtime = Map<String, dynamic>.from(decoded['runtime'] as Map);
  return BridgeExtensionRuntimeMessage(
    requestId: decoded['requestId'] as String,
    mcpServers: _stringListOrEmpty(runtime['mcpServers']),
    skills: _stringListOrEmpty(runtime['skills']),
    warnings: _stringListOrEmpty(runtime['warnings']),
  );
}

BridgeSkillsSnapshotMessage _decodeSkillsSnapshot(
  Map<String, dynamic> decoded,
) {
  final rawSkills = decoded['skills'];
  return BridgeSkillsSnapshotMessage(
    requestId: decoded['requestId'] as String,
    skills: rawSkills is List
        ? [
            for (final rawSkill in rawSkills)
              if (rawSkill is Map)
                _decodeSkillSummary(Map<String, dynamic>.from(rawSkill)),
          ]
        : const [],
  );
}

BridgeMcpServersSnapshotMessage _decodeMcpServersSnapshot(
  Map<String, dynamic> decoded,
) {
  final rawServers = decoded['servers'];
  return BridgeMcpServersSnapshotMessage(
    requestId: decoded['requestId'] as String,
    servers: rawServers is List
        ? [
            for (final rawServer in rawServers)
              if (rawServer is Map)
                _decodeMcpServerSummary(Map<String, dynamic>.from(rawServer)),
          ]
        : const [],
  );
}

BridgeMcpServerCapabilitiesMessage _decodeMcpServerCapabilities(
  Map<String, dynamic> decoded,
) {
  final capabilities = Map<String, dynamic>.from(
    decoded['capabilities'] as Map,
  );
  return BridgeMcpServerCapabilitiesMessage(
    requestId: decoded['requestId'] as String,
    serverId: capabilities['serverId']?.toString() ?? '',
    tools: _decodeCapabilityItems(capabilities['tools']),
    resources: _decodeCapabilityItems(capabilities['resources']),
    prompts: _decodeCapabilityItems(capabilities['prompts']),
    skills: _decodeSkillList(capabilities['skills']),
  );
}

BridgeMcpServerTestResultMessage _decodeMcpServerTestResult(
  Map<String, dynamic> decoded,
) {
  final result = Map<String, dynamic>.from(decoded['result'] as Map);
  final capabilities = Map<String, dynamic>.from(result['capabilities'] as Map);
  return BridgeMcpServerTestResultMessage(
    requestId: decoded['requestId'] as String,
    serverId: result['serverId']?.toString() ?? '',
    status: result['status']?.toString() ?? 'failed',
    message: result['message']?.toString() ?? '',
    durationMs: _intFrom(result['durationMs']),
    checkedAt: result['checkedAt']?.toString() ?? '',
    tools: _decodeCapabilityItems(capabilities['tools']),
    resources: _decodeCapabilityItems(capabilities['resources']),
    prompts: _decodeCapabilityItems(capabilities['prompts']),
    skills: _decodeSkillList(capabilities['skills']),
  );
}

BridgeSkillSummary _decodeSkillSummary(Map<String, dynamic> value) {
  return BridgeSkillSummary(
    id: value['id']?.toString() ?? '',
    name: value['name']?.toString() ?? '',
    description: value['description']?.toString() ?? '',
    source: value['source']?.toString() ?? 'local',
    status: value['status']?.toString() ?? 'enabled',
    path: value['path'] as String?,
    serverId: value['serverId'] as String?,
    unavailableReason: value['unavailableReason'] as String?,
  );
}

BridgeMcpServerSummary _decodeMcpServerSummary(Map<String, dynamic> value) {
  return BridgeMcpServerSummary(
    id: value['id']?.toString() ?? '',
    name: value['name']?.toString() ?? '',
    transport: value['transport']?.toString() ?? 'stdio',
    scope: value['scope']?.toString() ?? 'project',
    enabled: value['enabled'] == true,
    status: value['status']?.toString() ?? 'unknown',
    toolCount: _intFrom(value['toolCount']),
    resourceCount: _intFrom(value['resourceCount']),
    skillCount: _intFrom(value['skillCount']),
    lastError: value['lastError'] as String?,
    command: value['command'] as String?,
    args: _stringListFrom(value['args']),
    url: value['url'] as String?,
    headers: _stringMapFrom(value['headers']),
    env: _stringMapFrom(value['env']),
  );
}

List<BridgeMcpCapabilityItem> _decodeCapabilityItems(Object? value) {
  if (value is! List) return const [];
  return [
    for (final rawItem in value)
      if (rawItem is Map)
        BridgeMcpCapabilityItem(
          name: rawItem['name']?.toString() ?? '',
          description: rawItem['description'] as String?,
        ),
  ];
}

List<BridgeSkillSummary> _decodeSkillList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final rawSkill in value)
      if (rawSkill is Map)
        _decodeSkillSummary(Map<String, dynamic>.from(rawSkill)),
  ];
}

BridgeContextIndexResultMessage _decodeContextIndexResult(
  Map<String, dynamic> decoded,
) {
  final result = Map<String, dynamic>.from(decoded['result'] as Map);
  final sourcePaths = result['sourcePaths'];
  return BridgeContextIndexResultMessage(
    requestId: decoded['requestId'] as String,
    target: result['target'] as String,
    path: result['path'] as String,
    indexedNodes: result['indexedNodes'] as int,
    sourcePaths: sourcePaths is List
        ? [for (final path in sourcePaths) path.toString()]
        : const [],
  );
}

BridgeContextLearnResultMessage _decodeContextLearnResult(
  Map<String, dynamic> decoded,
) {
  final result = Map<String, dynamic>.from(decoded['result'] as Map);
  final rawCandidates = result['candidates'];
  final candidates = <BridgeLearningCandidate>[];
  if (rawCandidates is List) {
    for (final rawCandidate in rawCandidates) {
      if (rawCandidate is! Map) continue;
      final candidate = Map<String, dynamic>.from(rawCandidate);
      final fact = candidate['fact'];
      candidates.add(
        BridgeLearningCandidate(
          source: candidate['source']?.toString() ?? 'profile',
          confidence: _doubleFrom(candidate['confidence']),
          reason: candidate['reason']?.toString() ?? '',
          evidence: candidate['evidence']?.toString() ?? '',
          fact: fact is Map ? Map<String, dynamic>.from(fact) : const {},
        ),
      );
    }
  }
  return BridgeContextLearnResultMessage(
    requestId: decoded['requestId'] as String,
    candidates: candidates,
  );
}

BridgeContextFactUpsertResultMessage _decodeContextFactUpsertResult(
  Map<String, dynamic> decoded,
) {
  final result = Map<String, dynamic>.from(decoded['result'] as Map);
  return BridgeContextFactUpsertResultMessage(
    requestId: decoded['requestId'] as String,
    source: result['source'] as String,
    id: result['id'] as String,
  );
}

BridgeContextFactsListResultMessage _decodeContextFactsListResult(
  Map<String, dynamic> decoded,
) {
  final result = Map<String, dynamic>.from(decoded['result'] as Map);
  final rawFacts = result['facts'];
  final facts = <BridgeMemoryFact>[];
  if (rawFacts is List) {
    for (final rawFact in rawFacts) {
      if (rawFact is! Map) continue;
      final factEntry = Map<String, dynamic>.from(rawFact);
      final fact = factEntry['fact'];
      facts.add(
        BridgeMemoryFact(
          source: factEntry['source']?.toString() ?? 'profile',
          disabled: factEntry['disabled'] == true,
          fact: fact is Map ? Map<String, dynamic>.from(fact) : const {},
        ),
      );
    }
  }
  return BridgeContextFactsListResultMessage(
    requestId: decoded['requestId'] as String,
    facts: facts,
  );
}

BridgeContextFactDeleteResultMessage _decodeContextFactDeleteResult(
  Map<String, dynamic> decoded,
) {
  final result = Map<String, dynamic>.from(decoded['result'] as Map);
  return BridgeContextFactDeleteResultMessage(
    requestId: decoded['requestId'] as String,
    source: result['source'] as String,
    id: result['id'] as String,
  );
}

double _doubleFrom(Object? value) {
  return value is num ? value.toDouble() : 0;
}

int _intFrom(Object? value) {
  return value is num ? value.toInt() : 0;
}

List<String>? _stringListFrom(Object? value) {
  if (value is! List) return null;
  return [for (final item in value) item.toString()];
}

List<String> _stringListOrEmpty(Object? value) {
  return _stringListFrom(value) ?? const [];
}

Map<String, String>? _stringMapFrom(Object? value) {
  if (value is! Map) return null;
  final result = <String, String>{};
  for (final entry in value.entries) {
    result[entry.key.toString()] = entry.value.toString();
  }
  return result.isEmpty ? null : result;
}

String _encode(Map<String, dynamic> message) {
  return jsonEncode(message);
}
