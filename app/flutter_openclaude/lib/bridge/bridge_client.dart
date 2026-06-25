import 'dart:async';

import 'bridge_protocol.dart';
import 'bridge_transport.dart';

final class BridgeClient {
  BridgeClient(this._transport) {
    _subscription = _transport.messages.listen(
      (message) => _messages.add(decodeBridgeServerMessage(message)),
      onError: _messages.addError,
      onDone: _messages.close,
    );
  }

  final BridgeTransport _transport;
  final _messages = StreamController<BridgeServerMessage>.broadcast();
  late final StreamSubscription<String> _subscription;

  Stream<BridgeServerMessage> get messages => _messages.stream;

  void start({
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
    _transport.send(
      encodeStartMessage(
        requestId: requestId,
        cwd: cwd,
        prompt: prompt,
        sessionId: sessionId,
        model: model,
        permissionMode: permissionMode,
        contextTranscriptMode: contextTranscriptMode,
        thinkingMode: thinkingMode,
        transcript: transcript,
        attachments: attachments,
        provider: provider,
      ),
    );
  }

  void respondToPermission({
    required String requestId,
    required String toolUseId,
    required Map<String, dynamic> decision,
  }) {
    _transport.send(
      encodePermissionResponseMessage(
        requestId: requestId,
        toolUseId: toolUseId,
        decision: decision,
      ),
    );
  }

  void retrieveContext({
    required String requestId,
    required String query,
    String? cwd,
    String? memoryDir,
    List<String>? sources,
    List<BridgeTranscriptMessage> transcript = const [],
    int? maxItems,
    int? maxCharacters,
  }) {
    _transport.send(
      encodeRetrieveContextMessage(
        requestId: requestId,
        query: query,
        cwd: cwd,
        memoryDir: memoryDir,
        sources: sources,
        transcript: transcript,
        maxItems: maxItems,
        maxCharacters: maxCharacters,
      ),
    );
  }

  void evaluateContext({
    required String requestId,
    required List<BridgeContextEvaluationCase> cases,
    String? cwd,
    List<String>? sources,
    int? k,
    int? maxItems,
    int? maxCharacters,
  }) {
    _transport.send(
      encodeContextEvaluationMessage(
        requestId: requestId,
        cases: cases,
        cwd: cwd,
        sources: sources,
        k: k,
        maxItems: maxItems,
        maxCharacters: maxCharacters,
      ),
    );
  }

  void indexContext({
    required String requestId,
    required String cwd,
    required String target,
    required String path,
    Map<String, dynamic>? metadata,
  }) {
    _transport.send(
      encodeContextIndexMessage(
        requestId: requestId,
        cwd: cwd,
        target: target,
        path: path,
        metadata: metadata,
      ),
    );
  }

  void learnContext({
    required String requestId,
    required List<BridgeTranscriptMessage> transcript,
    int? maxCandidates,
  }) {
    _transport.send(
      encodeContextLearnMessage(
        requestId: requestId,
        transcript: transcript,
        maxCandidates: maxCandidates,
      ),
    );
  }

  void upsertContextFact({
    required String requestId,
    required String cwd,
    required String source,
    required Map<String, dynamic> fact,
  }) {
    _transport.send(
      encodeContextFactUpsertMessage(
        requestId: requestId,
        cwd: cwd,
        source: source,
        fact: fact,
      ),
    );
  }

  void listContextFacts({
    required String requestId,
    required String cwd,
    List<String>? sources,
  }) {
    _transport.send(
      encodeContextFactsListMessage(
        requestId: requestId,
        cwd: cwd,
        sources: sources,
      ),
    );
  }

  void deleteContextFact({
    required String requestId,
    required String cwd,
    required String source,
    required String id,
  }) {
    _transport.send(
      encodeContextFactDeleteMessage(
        requestId: requestId,
        cwd: cwd,
        source: source,
        id: id,
      ),
    );
  }

  void listSkills({required String requestId, bool? includeDisabled}) {
    _transport.send(
      encodeSkillsListMessage(
        requestId: requestId,
        includeDisabled: includeDisabled,
      ),
    );
  }

  void importSkill({required String requestId, required String path}) {
    _transport.send(encodeSkillImportMessage(requestId: requestId, path: path));
  }

  void setSkillEnabled({
    required String requestId,
    required String skillId,
    required bool enabled,
  }) {
    _transport.send(
      encodeSkillSetEnabledMessage(
        requestId: requestId,
        skillId: skillId,
        enabled: enabled,
      ),
    );
  }

  void refreshSkills({required String requestId}) {
    _transport.send(encodeSkillRefreshMessage(requestId: requestId));
  }

  void listMcpServers({
    required String requestId,
    String? cwd,
    bool? includeDisabled,
  }) {
    _transport.send(
      encodeMcpServersListMessage(
        requestId: requestId,
        cwd: cwd,
        includeDisabled: includeDisabled,
      ),
    );
  }

  void listMcpServerCapabilities({
    required String requestId,
    required String serverId,
  }) {
    _transport.send(
      encodeMcpServerCapabilitiesMessage(
        requestId: requestId,
        serverId: serverId,
      ),
    );
  }

  void saveMcpServer({
    required String requestId,
    String? cwd,
    required BridgeMcpServerDraft server,
  }) {
    _transport.send(
      encodeMcpServerUpsertMessage(
        requestId: requestId,
        cwd: cwd,
        server: server,
      ),
    );
  }

  void setMcpServerEnabled({
    required String requestId,
    String? cwd,
    required String serverId,
    required bool enabled,
  }) {
    _transport.send(
      encodeMcpServerSetEnabledMessage(
        requestId: requestId,
        cwd: cwd,
        serverId: serverId,
        enabled: enabled,
      ),
    );
  }

  void deleteMcpServer({
    required String requestId,
    String? cwd,
    required String serverId,
  }) {
    _transport.send(
      encodeMcpServerDeleteMessage(
        requestId: requestId,
        cwd: cwd,
        serverId: serverId,
      ),
    );
  }

  void testMcpServer({
    required String requestId,
    String? cwd,
    required BridgeMcpServerDraft server,
  }) {
    _transport.send(
      encodeMcpServerTestMessage(
        requestId: requestId,
        cwd: cwd,
        server: server,
      ),
    );
  }

  void interrupt(String requestId) {
    _transport.send(encodeInterruptMessage(requestId));
  }

  void closeSession(String requestId) {
    _transport.send(encodeCloseSessionMessage(requestId));
  }

  void setAgentEvalTraceEnabled({
    required String requestId,
    required bool enabled,
  }) {
    _transport.send(
      encodeAgentEvalTraceSetEnabledMessage(
        requestId: requestId,
        enabled: enabled,
      ),
    );
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _transport.close();
    await _messages.close();
  }
}
