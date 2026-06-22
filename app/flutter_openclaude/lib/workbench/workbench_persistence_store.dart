import 'workbench_models.dart';

abstract interface class WorkbenchPersistenceStore {
  Future<Map<String, dynamic>?> load();

  Future<void> save(Map<String, dynamic> snapshot);
}

final class PersistedWorkbenchSnapshot {
  const PersistedWorkbenchSnapshot({
    required this.sessions,
    required this.activeSessionId,
    required this.messages,
    required this.messagesBySessionId,
    required this.provider,
    required this.personal,
    required this.bridgeUrl,
    required this.apiKeysByRoute,
    required this.setupAssistantDismissed,
  });

  final List<SessionSummary> sessions;
  final String activeSessionId;
  final List<ChatMessage> messages;
  final Map<String, List<ChatMessage>> messagesBySessionId;
  final ProviderSettings provider;
  final PersonalSettings personal;
  final String bridgeUrl;
  final Map<String, String> apiKeysByRoute;
  final bool setupAssistantDismissed;
}

Map<String, dynamic> encodePersistedWorkbenchState({
  required WorkbenchState state,
  required Map<String, String> apiKeysByRoute,
  Map<String, List<ChatMessage>>? messagesBySessionId,
}) {
  final persistedMessagesBySessionId =
      messagesBySessionId ?? {state.activeSessionId: state.messages};
  return {
    'version': 1,
    'activeSessionId': state.activeSessionId,
    'messagesSessionId': state.activeSessionId,
    'bridgeUrl': state.bridgeUrl,
    'setupAssistantDismissed': state.setupAssistantDismissed,
    'sessions': [
      for (final session in state.sessions)
        {
          'id': session.id,
          'title': session.title,
          'subtitle': session.subtitle,
          'status': session.status.name,
          'updatedLabel': session.updatedLabel,
        },
    ],
    'messages': _encodeMessages(state.messages),
    'messagesBySessionId': {
      for (final entry in persistedMessagesBySessionId.entries)
        entry.key: _encodeMessages(entry.value),
    },
    'provider': {
      'providerName': state.provider.providerName,
      'modelName': state.provider.modelName,
      'baseUrl': state.provider.baseUrl,
      'bridgeUrl': state.provider.bridgeUrl,
      'apiKeyConfigured': state.provider.apiKeyConfigured,
    },
    'apiKeysByRoute': Map<String, String>.from(apiKeysByRoute),
    'personal': {
      'displayName': state.personal.displayName,
      'defaultWorkingDirectory': state.personal.defaultWorkingDirectory,
      'themePreference': state.personal.themePreference.name,
      'fontScale': state.personal.fontScale,
      'autoConnectBridge': state.personal.autoConnectBridge,
      'agentEvalTraceEnabled': state.personal.agentEvalTraceEnabled,
      'fullRecentTranscriptContext': state.personal.fullRecentTranscriptContext,
      'thinkingModeEnabled': state.personal.thinkingModeEnabled,
    },
  };
}

PersistedWorkbenchSnapshot decodePersistedWorkbenchState({
  required Map<String, dynamic> snapshot,
  required WorkbenchState fallback,
}) {
  final sessions = _decodeSessions(snapshot['sessions']);
  final restoredSessions = sessions.isEmpty ? fallback.sessions : sessions;
  final requestedActiveSessionId = _string(
    snapshot['activeSessionId'],
    fallback.activeSessionId,
  );
  final activeSessionId =
      restoredSessions.any((session) => session.id == requestedActiveSessionId)
      ? requestedActiveSessionId
      : restoredSessions.first.id;
  final messagesSessionId = _string(snapshot['messagesSessionId'], '');
  final messagesBySessionId = _decodeMessagesBySessionId(
    snapshot['messagesBySessionId'],
  );
  final legacyMessages = _decodeMessages(snapshot['messages']);
  final restoredMessagesBySessionId = messagesBySessionId.isNotEmpty
      ? messagesBySessionId
      : messagesSessionId.isEmpty
      ? const <String, List<ChatMessage>>{}
      : {messagesSessionId: legacyMessages};
  final decodedProvider = _decodeProvider(
    snapshot['provider'],
    fallback.provider,
  );
  final bridgeUrl = _decodeBridgeUrl(
    snapshot['bridgeUrl'],
    decodedProvider.bridgeUrl,
  );
  final provider = decodedProvider.copyWith(bridgeUrl: bridgeUrl);
  return PersistedWorkbenchSnapshot(
    sessions: restoredSessions,
    activeSessionId: activeSessionId,
    messages: restoredMessagesBySessionId[activeSessionId] ?? const [],
    messagesBySessionId: restoredMessagesBySessionId,
    provider: provider,
    personal: _decodePersonal(snapshot['personal'], fallback.personal),
    bridgeUrl: bridgeUrl,
    apiKeysByRoute: _decodeApiKeys(snapshot['apiKeysByRoute']),
    setupAssistantDismissed: snapshot['setupAssistantDismissed'] == true,
  );
}

List<Map<String, dynamic>> _encodeMessages(List<ChatMessage> messages) {
  return [
    for (final message in messages)
      {
        'id': message.id,
        'role': message.role.name,
        'content': message.content,
        'timestampLabel': message.timestampLabel,
        if (message.attachments.isNotEmpty)
          'attachments': [
            for (final attachment in message.attachments)
              {
                'id': attachment.id,
                'name': attachment.name,
                'mimeType': attachment.mimeType,
                'sizeBytes': attachment.sizeBytes,
                'kind': attachment.kind.name,
                if (attachment.path != null) 'path': attachment.path,
                if (attachment.content != null) 'content': attachment.content,
              },
          ],
        if (message.tokenUsage != null)
          'tokenUsage': {
            'inputTokens': message.tokenUsage!.inputTokens,
            'outputTokens': message.tokenUsage!.outputTokens,
            'cacheReadInputTokens': message.tokenUsage!.cacheReadInputTokens,
            'cacheCreationInputTokens':
                message.tokenUsage!.cacheCreationInputTokens,
          },
      },
  ];
}

List<SessionSummary> _decodeSessions(Object? value) {
  if (value is! List) return const [];
  final sessions = <SessionSummary>[];
  for (final entry in value) {
    if (entry is! Map) continue;
    final session = Map<String, dynamic>.from(entry);
    final id = session['id'];
    if (id is! String || id.isEmpty) continue;
    sessions.add(
      SessionSummary(
        id: id,
        title: _string(session['title'], 'New chat'),
        subtitle: _string(session['subtitle'], ''),
        status: _sessionStatusFromName(session['status']),
        updatedLabel: _string(session['updatedLabel'], 'Now'),
      ),
    );
  }
  return sessions;
}

List<ChatMessage> _decodeMessages(Object? value) {
  if (value is! List) return const [];
  final messages = <ChatMessage>[];
  for (final entry in value) {
    if (entry is! Map) continue;
    final message = Map<String, dynamic>.from(entry);
    final id = message['id'];
    final content = message['content'];
    if (id is! String || content is! String) continue;
    messages.add(
      ChatMessage(
        id: id,
        role: _messageRoleFromName(message['role']),
        content: content,
        timestampLabel: _string(message['timestampLabel'], 'Now'),
        attachments: _decodeAttachments(message['attachments']),
        tokenUsage: _decodeTokenUsage(message['tokenUsage']),
      ),
    );
  }
  return messages;
}

Map<String, List<ChatMessage>> _decodeMessagesBySessionId(Object? value) {
  if (value is! Map) return const {};
  final messagesBySessionId = <String, List<ChatMessage>>{};
  for (final entry in value.entries) {
    final sessionId = entry.key;
    if (sessionId is! String || sessionId.isEmpty) continue;
    messagesBySessionId[sessionId] = _decodeMessages(entry.value);
  }
  return messagesBySessionId;
}

List<ChatAttachment> _decodeAttachments(Object? value) {
  if (value is! List) return const [];
  final attachments = <ChatAttachment>[];
  for (final entry in value) {
    if (entry is! Map) continue;
    final attachment = Map<String, dynamic>.from(entry);
    final id = attachment['id'];
    final name = attachment['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      continue;
    }
    attachments.add(
      ChatAttachment(
        id: id,
        name: name,
        mimeType: _string(attachment['mimeType'], 'application/octet-stream'),
        sizeBytes: _intOrNull(attachment['sizeBytes']) ?? 0,
        kind: _attachmentKindFromName(attachment['kind']),
        path: attachment['path'] is String
            ? attachment['path'] as String
            : null,
        content: attachment['content'] is String
            ? attachment['content'] as String
            : null,
      ),
    );
  }
  return attachments;
}

ChatAttachmentKind _attachmentKindFromName(Object? value) {
  if (value is String) {
    for (final kind in ChatAttachmentKind.values) {
      if (kind.name == value) return kind;
    }
  }
  return ChatAttachmentKind.file;
}

ChatTokenUsage? _decodeTokenUsage(Object? value) {
  if (value is! Map) return null;
  final usage = Map<String, dynamic>.from(value);
  final inputTokens = _intOrNull(usage['inputTokens']);
  final outputTokens = _intOrNull(usage['outputTokens']);
  if (inputTokens == null && outputTokens == null) return null;
  return ChatTokenUsage(
    inputTokens: inputTokens ?? 0,
    outputTokens: outputTokens ?? 0,
    cacheReadInputTokens: _intOrNull(usage['cacheReadInputTokens']) ?? 0,
    cacheCreationInputTokens:
        _intOrNull(usage['cacheCreationInputTokens']) ?? 0,
  );
}

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return null;
}

ProviderSettings _decodeProvider(Object? value, ProviderSettings fallback) {
  if (value is! Map) return fallback;
  final provider = Map<String, dynamic>.from(value);
  return ProviderSettings(
    providerName: _string(provider['providerName'], fallback.providerName),
    modelName: _string(provider['modelName'], fallback.modelName),
    baseUrl: _string(provider['baseUrl'], fallback.baseUrl),
    bridgeUrl: _decodeBridgeUrl(provider['bridgeUrl'], fallback.bridgeUrl),
    apiKeyConfigured: provider['apiKeyConfigured'] == true,
  );
}

PersonalSettings _decodePersonal(Object? value, PersonalSettings fallback) {
  if (value is! Map) return fallback;
  final personal = Map<String, dynamic>.from(value);
  return PersonalSettings(
    displayName: _string(personal['displayName'], fallback.displayName),
    defaultWorkingDirectory: _string(
      personal['defaultWorkingDirectory'],
      fallback.defaultWorkingDirectory,
    ),
    themePreference: _themePreferenceFromName(
      personal['themePreference'],
      fallback.themePreference,
    ),
    fontScale: personal['fontScale'] is num
        ? (personal['fontScale'] as num).toDouble()
        : fallback.fontScale,
    autoConnectBridge:
        personal['autoConnectBridge'] ?? fallback.autoConnectBridge,
    agentEvalTraceEnabled:
        personal['agentEvalTraceEnabled'] ?? fallback.agentEvalTraceEnabled,
    fullRecentTranscriptContext:
        personal['fullRecentTranscriptContext'] ??
        fallback.fullRecentTranscriptContext,
    thinkingModeEnabled:
        personal['thinkingModeEnabled'] ?? fallback.thinkingModeEnabled,
  );
}

Map<String, String> _decodeApiKeys(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.value is String) entry.key.toString(): entry.value as String,
  };
}

String _string(Object? value, String fallback) {
  return value is String ? value : fallback;
}

String _decodeBridgeUrl(Object? value, String fallback) {
  final raw = _string(value, fallback).trim();
  if (raw.isEmpty) return fallback;
  final uri = Uri.tryParse(raw);
  if (uri == null || (uri.scheme != 'ws' && uri.scheme != 'wss')) {
    return fallback;
  }
  return raw;
}

SessionStatus _sessionStatusFromName(Object? value) {
  for (final status in SessionStatus.values) {
    if (status.name == value) return status;
  }
  return SessionStatus.idle;
}

MessageRole _messageRoleFromName(Object? value) {
  for (final role in MessageRole.values) {
    if (role.name == value) return role;
  }
  return MessageRole.user;
}

ThemePreference _themePreferenceFromName(
  Object? value,
  ThemePreference fallback,
) {
  for (final theme in ThemePreference.values) {
    if (theme.name == value) return theme;
  }
  return fallback;
}
