import 'dart:async';
import 'dart:convert';

import 'package:flutter_openclaude/bridge/bridge_client.dart';
import 'package:flutter_openclaude/bridge/bridge_protocol.dart';
import 'package:flutter_openclaude/bridge/bridge_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBridgeTransport implements BridgeTransport {
  final sent = <String>[];
  final _incoming = StreamController<String>();

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String message) => sent.add(message);

  void receive(String message) => _incoming.add(message);

  @override
  Future<void> close() async => _incoming.close();
}

void main() {
  test(
    'start sends a bridge start message and emits decoded responses',
    () async {
      final transport = FakeBridgeTransport();
      final client = BridgeClient(transport);
      final received = <BridgeServerMessage>[];
      final sub = client.messages.listen(received.add);

      client.start(requestId: 'req-1', cwd: '/tmp/project', prompt: 'hello');
      expect(jsonDecode(transport.sent.single)['type'], 'start');

      transport.receive('{"type":"hello","protocolVersion":1}');
      await Future<void>.delayed(Duration.zero);

      expect(received.single, isA<BridgeHelloMessage>());
      await sub.cancel();
      await client.close();
    },
  );

  test(
    'permission response, interrupt, and close send bridge messages',
    () async {
      final transport = FakeBridgeTransport();
      final client = BridgeClient(transport);

      client.respondToPermission(
        requestId: 'req-1',
        toolUseId: 'tool-1',
        decision: {'behavior': 'allow'},
      );
      client.interrupt('req-2');
      client.closeSession('req-3');

      expect(transport.sent.map((message) => jsonDecode(message)['type']), [
        'permission_response',
        'interrupt',
        'close_session',
      ]);

      await client.close();
    },
  );

  test('context retrieval sends request and decodes response', () async {
    final transport = FakeBridgeTransport();
    final client = BridgeClient(transport);
    final received = <BridgeServerMessage>[];
    final sub = client.messages.listen(received.add);

    client.retrieveContext(
      requestId: 'ctx-1',
      query: 'provider api key',
      memoryDir: '/tmp/memory',
      transcript: const [
        BridgeTranscriptMessage(
          id: 'message-1',
          role: 'user',
          content: 'Provider API key setup was discussed.',
        ),
      ],
      maxItems: 3,
      maxCharacters: 500,
    );

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'retrieve_context');
    expect(sent['requestId'], 'ctx-1');
    expect(sent['query'], 'provider api key');
    expect(sent['memoryDir'], '/tmp/memory');
    expect(sent['transcript'], [
      {
        'id': 'message-1',
        'role': 'user',
        'content': 'Provider API key setup was discussed.',
      },
    ]);

    transport.receive(
      '{"type":"context_retrieval","requestId":"ctx-1","result":{"items":[],"attachment":null}}',
    );
    await Future<void>.delayed(Duration.zero);

    final message = received.single;
    expect(message, isA<BridgeContextRetrievalMessage>());
    expect((message as BridgeContextRetrievalMessage).requestId, 'ctx-1');
    expect(message.result['items'], isEmpty);

    await sub.cancel();
    await client.close();
  });

  test('context evaluation sends request and decodes report', () async {
    final transport = FakeBridgeTransport();
    final client = BridgeClient(transport);
    final received = <BridgeServerMessage>[];
    final sub = client.messages.listen(received.add);

    client.evaluateContext(
      requestId: 'eval-1',
      cwd: '/tmp/project',
      k: 2,
      sources: const ['document', 'profile'],
      cases: const [
        BridgeContextEvaluationCase(
          name: 'provider docs',
          query: 'provider api key setup',
          relevantIds: ['doc-provider'],
        ),
      ],
    );

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'context_eval');
    expect(sent['requestId'], 'eval-1');
    expect(sent['cwd'], '/tmp/project');
    expect(sent['k'], 2);
    expect(sent['sources'], ['document', 'profile']);
    expect(sent['cases'], [
      {
        'name': 'provider docs',
        'query': 'provider api key setup',
        'relevantIds': ['doc-provider'],
      },
    ]);

    transport.receive(
      '{"type":"context_eval_result","requestId":"eval-1","result":{"k":2,"hitRate":1,"precisionAtK":0.5,"mrr":1,"sourceCounts":{"document":1,"profile":1},"sourceShare":{"document":0.5,"profile":0.5},"cases":[]}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(received.single, isA<BridgeContextEvaluationResultMessage>());
    final message = received.single as BridgeContextEvaluationResultMessage;
    expect(message.requestId, 'eval-1');
    expect(message.result['hitRate'], 1);

    await sub.cancel();
    await client.close();
  });

  test('context index sends request and decodes progress/result', () async {
    final transport = FakeBridgeTransport();
    final client = BridgeClient(transport);
    final received = <BridgeServerMessage>[];
    final sub = client.messages.listen(received.add);

    client.indexContext(
      requestId: 'idx-1',
      cwd: '/tmp/project',
      target: 'directory',
      path: 'docs',
    );

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'context_index');
    expect(sent['requestId'], 'idx-1');
    expect(sent['cwd'], '/tmp/project');
    expect(sent['target'], 'directory');
    expect(sent['path'], 'docs');

    transport.receive(
      '{"type":"context_index_progress","requestId":"idx-1","target":"directory","path":"docs","status":"indexing"}',
    );
    transport.receive(
      '{"type":"context_index_result","requestId":"idx-1","result":{"target":"directory","path":"docs","indexedNodes":2,"sourcePaths":["docs/provider-guide.md"]}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(received.first, isA<BridgeContextIndexProgressMessage>());
    expect(received.last, isA<BridgeContextIndexResultMessage>());

    await sub.cancel();
    await client.close();
  });

  test('context learn sends request and decodes candidates', () async {
    final transport = FakeBridgeTransport();
    final client = BridgeClient(transport);
    final received = <BridgeServerMessage>[];
    final sub = client.messages.listen(received.add);

    client.learnContext(
      requestId: 'learn-1',
      transcript: const [
        BridgeTranscriptMessage(
          id: 'message-1',
          role: 'user',
          content: 'I prefer concise answers.',
        ),
      ],
      maxCandidates: 3,
    );

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'context_learn');
    expect(sent['requestId'], 'learn-1');
    expect(sent['maxCandidates'], 3);

    transport.receive(
      '{"type":"context_learn_result","requestId":"learn-1","result":{"candidates":[{"source":"profile","confidence":0.85,"reason":"Detected an explicit user preference.","evidence":"I prefer concise answers.","fact":{"id":"profile:preference:concise-answers","label":"Preference","content":"User prefers concise answers.","visibility":"workspace","consent":"allowed"}}]}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(received.single, isA<BridgeContextLearnResultMessage>());
    expect(
      (received.single as BridgeContextLearnResultMessage)
          .candidates
          .single
          .fact['id'],
      'profile:preference:concise-answers',
    );

    await sub.cancel();
    await client.close();
  });

  test('context fact upsert sends request and decodes result', () async {
    final transport = FakeBridgeTransport();
    final client = BridgeClient(transport);
    final received = <BridgeServerMessage>[];
    final sub = client.messages.listen(received.add);

    client.upsertContextFact(
      requestId: 'fact-1',
      cwd: '/tmp/project',
      source: 'profile',
      fact: const {
        'id': 'profile:preference:concise-answers',
        'label': 'Preference',
        'content': 'User prefers concise answers.',
        'visibility': 'workspace',
        'consent': 'allowed',
      },
    );

    final sent = jsonDecode(transport.sent.single) as Map<String, dynamic>;
    expect(sent['type'], 'context_fact_upsert');
    expect(sent['source'], 'profile');
    expect(sent['fact']['id'], 'profile:preference:concise-answers');

    transport.receive(
      '{"type":"context_fact_upsert_result","requestId":"fact-1","result":{"source":"profile","id":"profile:preference:concise-answers"}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(received.single, isA<BridgeContextFactUpsertResultMessage>());

    await sub.cancel();
    await client.close();
  });

  test('context facts list and delete send requests and decode results', () async {
    final transport = FakeBridgeTransport();
    final client = BridgeClient(transport);
    final received = <BridgeServerMessage>[];
    final sub = client.messages.listen(received.add);

    client.listContextFacts(
      requestId: 'facts-1',
      cwd: '/tmp/project',
      sources: const ['profile', 'habit'],
    );
    client.deleteContextFact(
      requestId: 'delete-1',
      cwd: '/tmp/project',
      source: 'habit',
      id: 'habit-connection',
    );

    expect(transport.sent.map((message) => jsonDecode(message)['type']), [
      'context_facts_list',
      'context_fact_delete',
    ]);

    transport.receive(
      '{"type":"context_facts_list_result","requestId":"facts-1","result":{"facts":[{"source":"profile","disabled":false,"fact":{"id":"profile-tone","label":"Preferred tone","content":"User prefers concise answers.","visibility":"workspace","consent":"allowed"}}]}}',
    );
    transport.receive(
      '{"type":"context_fact_delete_result","requestId":"delete-1","result":{"source":"habit","id":"habit-connection"}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(received.first, isA<BridgeContextFactsListResultMessage>());
    expect(received.last, isA<BridgeContextFactDeleteResultMessage>());

    await sub.cancel();
    await client.close();
  });

  test('skills and MCP inventory sends requests and decodes snapshots', () async {
    final transport = FakeBridgeTransport();
    final client = BridgeClient(transport);
    final received = <BridgeServerMessage>[];
    final sub = client.messages.listen(received.add);

    client.listSkills(requestId: 'skills-1', includeDisabled: true);
    client.listMcpServers(requestId: 'mcp-1', includeDisabled: false);
    client.listMcpServerCapabilities(
      requestId: 'mcp-capabilities-1',
      serverId: 'filesystem',
    );
    client.testMcpServer(
      requestId: 'mcp-test-1',
      cwd: '/tmp/project',
      server: const BridgeMcpServerDraft(
        name: 'Filesystem Server',
        transport: 'stdio',
        command: 'npx',
      ),
    );

    expect(transport.sent.map((message) => jsonDecode(message)['type']), [
      'skills_list',
      'mcp_servers_list',
      'mcp_server_capabilities',
      'mcp_server_test',
    ]);

    transport.receive(
      '{"type":"skills_snapshot","requestId":"skills-1","skills":[{"id":"debug","name":"debug","description":"Debug a failing workflow.","source":"bundled","status":"enabled"}]}',
    );
    transport.receive(
      '{"type":"mcp_servers_snapshot","requestId":"mcp-1","servers":[{"id":"filesystem","name":"filesystem","transport":"stdio","scope":"project","enabled":true,"status":"unknown","toolCount":0,"resourceCount":0,"skillCount":0}]}',
    );
    transport.receive(
      '{"type":"mcp_server_capabilities","requestId":"mcp-capabilities-1","capabilities":{"serverId":"filesystem","tools":[{"name":"read_file","description":"Read a file."}],"resources":[],"prompts":[],"skills":[]}}',
    );
    transport.receive(
      '{"type":"mcp_server_test_result","requestId":"mcp-test-1","result":{"serverId":"filesystem","status":"connected","message":"Connected","durationMs":42,"checkedAt":"2026-06-20T00:00:00.000Z","capabilities":{"serverId":"filesystem","tools":[{"name":"read_file","description":"Read a file."}],"resources":[],"prompts":[],"skills":[]}}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(received[0], isA<BridgeSkillsSnapshotMessage>());
    expect(received[1], isA<BridgeMcpServersSnapshotMessage>());
    expect(received[2], isA<BridgeMcpServerCapabilitiesMessage>());
    expect(received[3], isA<BridgeMcpServerTestResultMessage>());

    await sub.cancel();
    await client.close();
  });

  test('skill management sends requests and decodes responses', () async {
    final transport = FakeBridgeTransport();
    final client = BridgeClient(transport);
    final received = <BridgeServerMessage>[];
    final sub = client.messages.listen(received.add);

    client.importSkill(requestId: 'skill-import-1', path: '/tmp/skills/debug');
    client.setSkillEnabled(
      requestId: 'skill-enable-1',
      skillId: 'debug',
      enabled: false,
    );
    client.refreshSkills(requestId: 'skill-refresh-1');

    expect(transport.sent.map((message) => jsonDecode(message)['type']), [
      'skill_import',
      'skill_set_enabled',
      'skill_refresh',
    ]);

    transport.receive(
      '{"type":"skill_imported","requestId":"skill-import-1","skill":{"id":"debug","name":"debug","description":"Debug a failing workflow.","source":"local","status":"enabled","path":"/tmp/skills/debug"}}',
    );
    transport.receive(
      '{"type":"skill_updated","requestId":"skill-enable-1","skill":{"id":"debug","name":"debug","description":"Debug a failing workflow.","source":"local","status":"disabled","path":"/tmp/skills/debug"}}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(received.first, isA<BridgeSkillImportedMessage>());
    expect(received.last, isA<BridgeSkillUpdatedMessage>());

    await sub.cancel();
    await client.close();
  });

  test('MCP server CRUD sends requests and decodes responses', () async {
    final transport = FakeBridgeTransport();
    final client = BridgeClient(transport);
    final received = <BridgeServerMessage>[];
    final sub = client.messages.listen(received.add);

    client.saveMcpServer(
      requestId: 'mcp-save-1',
      cwd: '/tmp/project',
      server: const BridgeMcpServerDraft(
        name: 'Filesystem Server',
        transport: 'stdio',
        scope: 'project',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-filesystem'],
        env: {'FILESYSTEM_TOKEN': 'secret'},
        enabled: true,
      ),
    );
    client.setMcpServerEnabled(
      requestId: 'mcp-enable-1',
      cwd: '/tmp/project',
      serverId: 'filesystem-server',
      enabled: false,
    );
    client.deleteMcpServer(
      requestId: 'mcp-delete-1',
      cwd: '/tmp/project',
      serverId: 'filesystem-server',
    );

    expect(transport.sent.map((message) => jsonDecode(message)['type']), [
      'mcp_server_upsert',
      'mcp_server_set_enabled',
      'mcp_server_delete',
    ]);
    expect(jsonDecode(transport.sent.first)['server']['env'], {
      'FILESYSTEM_TOKEN': 'secret',
    });

    transport.receive(
      '{"type":"mcp_server_saved","requestId":"mcp-save-1","server":{"id":"filesystem-server","name":"filesystem-server","transport":"stdio","scope":"project","enabled":true,"status":"unknown","toolCount":0,"resourceCount":0,"skillCount":0,"command":"npx","args":["-y","@modelcontextprotocol/server-filesystem"],"env":{"FILESYSTEM_TOKEN":"********"}}}',
    );
    transport.receive(
      '{"type":"mcp_server_deleted","requestId":"mcp-delete-1","serverId":"filesystem-server"}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(received.first, isA<BridgeMcpServerSavedMessage>());
    expect(received.last, isA<BridgeMcpServerDeletedMessage>());

    await sub.cancel();
    await client.close();
  });
}
