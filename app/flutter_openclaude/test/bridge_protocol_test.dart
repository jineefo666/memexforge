import 'dart:convert';

import 'package:flutter_openclaude/bridge/bridge_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodes start messages', () {
    final encoded = encodeStartMessage(
      requestId: 'req-1',
      cwd: '/tmp/project',
      prompt: 'hello',
      model: 'claude-sonnet-4-6',
    );

    expect(jsonDecode(encoded), {
      'type': 'start',
      'requestId': 'req-1',
      'cwd': '/tmp/project',
      'prompt': 'hello',
      'model': 'claude-sonnet-4-6',
    });
  });

  test('encodes optional fields only when provided', () {
    final encoded = encodeStartMessage(
      requestId: 'req-2',
      cwd: '/tmp/project',
      prompt: 'hello',
      sessionId: 'session-1',
      permissionMode: 'acceptEdits',
    );

    expect(jsonDecode(encoded), {
      'type': 'start',
      'requestId': 'req-2',
      'cwd': '/tmp/project',
      'prompt': 'hello',
      'sessionId': 'session-1',
      'permissionMode': 'acceptEdits',
    });
  });

  test('encodes transcript on start messages', () {
    final encoded = encodeStartMessage(
      requestId: 'req-transcript',
      cwd: '/tmp/project',
      prompt: '上一句话是什么',
      transcript: const [
        BridgeTranscriptMessage(
          id: 'message-1',
          role: 'user',
          content: '方向是 Agent Workbench 产品化。',
        ),
        BridgeTranscriptMessage(
          id: 'message-2',
          role: 'assistant',
          content: '我会按这个方向继续。',
        ),
      ],
    );

    expect(jsonDecode(encoded), {
      'type': 'start',
      'requestId': 'req-transcript',
      'cwd': '/tmp/project',
      'prompt': '上一句话是什么',
      'transcript': [
        {
          'id': 'message-1',
          'role': 'user',
          'content': '方向是 Agent Workbench 产品化。',
        },
        {'id': 'message-2', 'role': 'assistant', 'content': '我会按这个方向继续。'},
      ],
    });
  });

  test('encodes image attachments on start messages', () {
    final encoded = encodeStartMessage(
      requestId: 'req-image',
      cwd: '/tmp/project',
      prompt: 'What is in this screenshot?',
      attachments: const [
        BridgeAttachment(
          id: 'attachment-1',
          name: 'screenshot.png',
          kind: 'image',
          mimeType: 'image/png',
          sizeBytes: 4,
          dataBase64: 'ZmFrZQ==',
        ),
      ],
    );

    expect(jsonDecode(encoded), {
      'type': 'start',
      'requestId': 'req-image',
      'cwd': '/tmp/project',
      'prompt': 'What is in this screenshot?',
      'attachments': [
        {
          'id': 'attachment-1',
          'name': 'screenshot.png',
          'kind': 'image',
          'mimeType': 'image/png',
          'sizeBytes': 4,
          'dataBase64': 'ZmFrZQ==',
        },
      ],
    });
  });

  test('encodes transcript context mode on start messages', () {
    final encoded = encodeStartMessage(
      requestId: 'req-context-mode',
      cwd: '/tmp/project',
      prompt: '继续',
      contextTranscriptMode: 'full_recent',
    );

    expect(jsonDecode(encoded), {
      'type': 'start',
      'requestId': 'req-context-mode',
      'cwd': '/tmp/project',
      'prompt': '继续',
      'contextTranscriptMode': 'full_recent',
    });
  });

  test('encodes thinking mode on start messages', () {
    final encoded = encodeStartMessage(
      requestId: 'req-thinking',
      cwd: '/tmp/project',
      prompt: 'hello',
      thinkingMode: 'disabled',
    );

    expect(jsonDecode(encoded), {
      'type': 'start',
      'requestId': 'req-thinking',
      'cwd': '/tmp/project',
      'prompt': 'hello',
      'thinkingMode': 'disabled',
    });
  });

  test('encodes provider settings on start messages', () {
    final encoded = encodeStartMessage(
      requestId: 'req-3',
      cwd: '/tmp/project',
      prompt: 'hello',
      model: 'deepseek-v4-flash',
      provider: const BridgeProviderConfig(
        providerName: 'OpenAI Compatible',
        modelName: 'deepseek-v4-flash',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-secret-value',
      ),
    );

    expect(jsonDecode(encoded), {
      'type': 'start',
      'requestId': 'req-3',
      'cwd': '/tmp/project',
      'prompt': 'hello',
      'model': 'deepseek-v4-flash',
      'provider': {
        'providerName': 'OpenAI Compatible',
        'modelName': 'deepseek-v4-flash',
        'baseUrl': 'https://api.deepseek.com/v1',
        'apiKey': 'sk-secret-value',
      },
    });
  });

  test('encodes context index messages', () {
    final encoded = encodeContextIndexMessage(
      requestId: 'idx-1',
      cwd: '/tmp/project',
      target: 'directory',
      path: 'docs',
      metadata: const {'source': 'workspace-docs'},
    );

    expect(jsonDecode(encoded), {
      'type': 'context_index',
      'requestId': 'idx-1',
      'cwd': '/tmp/project',
      'target': 'directory',
      'path': 'docs',
      'metadata': {'source': 'workspace-docs'},
    });
  });

  test('encodes agent eval trace toggle messages', () {
    final encoded = encodeAgentEvalTraceSetEnabledMessage(
      requestId: 'trace-1',
      enabled: true,
    );

    expect(jsonDecode(encoded), {
      'type': 'agent_eval_trace_set_enabled',
      'requestId': 'trace-1',
      'enabled': true,
    });
  });

  test('decodes agent eval trace status messages', () {
    final decoded = decodeBridgeServerMessage(
      jsonEncode({
        'type': 'agent_eval_trace_status',
        'requestId': 'trace-1',
        'enabled': true,
        'tracePath': 'reports/agent-eval/traces/turns.jsonl',
      }),
    );

    expect(decoded, isA<BridgeAgentEvalTraceStatusMessage>());
    final status = decoded as BridgeAgentEvalTraceStatusMessage;
    expect(status.requestId, 'trace-1');
    expect(status.enabled, isTrue);
    expect(status.tracePath, 'reports/agent-eval/traces/turns.jsonl');
  });

  test('encodes context learn messages', () {
    final encoded = encodeContextLearnMessage(
      requestId: 'learn-1',
      transcript: const [
        BridgeTranscriptMessage(
          id: 'message-1',
          role: 'user',
          content: 'I prefer concise answers.',
        ),
      ],
      maxCandidates: 5,
    );

    expect(jsonDecode(encoded), {
      'type': 'context_learn',
      'requestId': 'learn-1',
      'transcript': [
        {
          'id': 'message-1',
          'role': 'user',
          'content': 'I prefer concise answers.',
        },
      ],
      'maxCandidates': 5,
    });
  });

  test('encodes context fact upsert messages', () {
    final encoded = encodeContextFactUpsertMessage(
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

    expect(jsonDecode(encoded), {
      'type': 'context_fact_upsert',
      'requestId': 'fact-1',
      'cwd': '/tmp/project',
      'source': 'profile',
      'fact': {
        'id': 'profile:preference:concise-answers',
        'label': 'Preference',
        'content': 'User prefers concise answers.',
        'visibility': 'workspace',
        'consent': 'allowed',
      },
    });
  });

  test('encodes context fact list and delete messages', () {
    final list = encodeContextFactsListMessage(
      requestId: 'facts-1',
      cwd: '/tmp/project',
      sources: const ['profile', 'habit'],
    );
    final delete = encodeContextFactDeleteMessage(
      requestId: 'delete-1',
      cwd: '/tmp/project',
      source: 'habit',
      id: 'habit-connection',
    );

    expect(jsonDecode(list), {
      'type': 'context_facts_list',
      'requestId': 'facts-1',
      'cwd': '/tmp/project',
      'sources': ['profile', 'habit'],
    });
    expect(jsonDecode(delete), {
      'type': 'context_fact_delete',
      'requestId': 'delete-1',
      'cwd': '/tmp/project',
      'source': 'habit',
      'id': 'habit-connection',
    });
  });

  test('encodes skills and MCP inventory messages', () {
    final skills = encodeSkillsListMessage(
      requestId: 'skills-1',
      includeDisabled: true,
    );
    final servers = encodeMcpServersListMessage(
      requestId: 'mcp-1',
      includeDisabled: false,
    );
    final capabilities = encodeMcpServerCapabilitiesMessage(
      requestId: 'mcp-capabilities-1',
      serverId: 'filesystem',
    );
    final test = encodeMcpServerTestMessage(
      requestId: 'mcp-test-1',
      cwd: '/tmp/project',
      server: const BridgeMcpServerDraft(
        name: 'Filesystem Server',
        transport: 'stdio',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-filesystem'],
        env: {'FILESYSTEM_TOKEN': 'secret'},
        enabled: true,
      ),
    );

    expect(jsonDecode(skills), {
      'type': 'skills_list',
      'requestId': 'skills-1',
      'includeDisabled': true,
    });
    expect(jsonDecode(servers), {
      'type': 'mcp_servers_list',
      'requestId': 'mcp-1',
      'includeDisabled': false,
    });
    expect(jsonDecode(capabilities), {
      'type': 'mcp_server_capabilities',
      'requestId': 'mcp-capabilities-1',
      'serverId': 'filesystem',
    });
    expect(jsonDecode(test), {
      'type': 'mcp_server_test',
      'requestId': 'mcp-test-1',
      'cwd': '/tmp/project',
      'server': {
        'name': 'Filesystem Server',
        'transport': 'stdio',
        'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-filesystem'],
        'env': {'FILESYSTEM_TOKEN': 'secret'},
        'enabled': true,
      },
    });
  });

  test('encodes skill management messages', () {
    final import = encodeSkillImportMessage(
      requestId: 'skill-import-1',
      path: '/tmp/skills/debug',
    );
    final disable = encodeSkillSetEnabledMessage(
      requestId: 'skill-enable-1',
      skillId: 'debug',
      enabled: false,
    );
    final refresh = encodeSkillRefreshMessage(requestId: 'skill-refresh-1');

    expect(jsonDecode(import), {
      'type': 'skill_import',
      'requestId': 'skill-import-1',
      'path': '/tmp/skills/debug',
    });
    expect(jsonDecode(disable), {
      'type': 'skill_set_enabled',
      'requestId': 'skill-enable-1',
      'skillId': 'debug',
      'enabled': false,
    });
    expect(jsonDecode(refresh), {
      'type': 'skill_refresh',
      'requestId': 'skill-refresh-1',
    });
  });

  test('encodes MCP server CRUD messages', () {
    final save = encodeMcpServerUpsertMessage(
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
    final disable = encodeMcpServerSetEnabledMessage(
      requestId: 'mcp-enable-1',
      cwd: '/tmp/project',
      serverId: 'filesystem-server',
      enabled: false,
    );
    final delete = encodeMcpServerDeleteMessage(
      requestId: 'mcp-delete-1',
      cwd: '/tmp/project',
      serverId: 'filesystem-server',
    );

    expect(jsonDecode(save), {
      'type': 'mcp_server_upsert',
      'requestId': 'mcp-save-1',
      'cwd': '/tmp/project',
      'server': {
        'name': 'Filesystem Server',
        'transport': 'stdio',
        'scope': 'project',
        'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-filesystem'],
        'env': {'FILESYSTEM_TOKEN': 'secret'},
        'enabled': true,
      },
    });
    expect(jsonDecode(disable), {
      'type': 'mcp_server_set_enabled',
      'requestId': 'mcp-enable-1',
      'cwd': '/tmp/project',
      'serverId': 'filesystem-server',
      'enabled': false,
    });
    expect(jsonDecode(delete), {
      'type': 'mcp_server_delete',
      'requestId': 'mcp-delete-1',
      'cwd': '/tmp/project',
      'serverId': 'filesystem-server',
    });
  });

  test('decodes hello messages', () {
    final message = decodeBridgeServerMessage(
      '{"type":"hello","protocolVersion":1}',
    );

    expect(message, isA<BridgeHelloMessage>());
    expect((message as BridgeHelloMessage).protocolVersion, 1);
  });

  test('decodes sdk messages without interpreting their payload', () {
    final message = decodeBridgeServerMessage(
      '{"type":"sdk_message","requestId":"req-1","sessionId":"session-1","message":{"type":"result","result":"ok"}}',
    );

    expect(message, isA<BridgeSdkMessage>());
    final sdk = message as BridgeSdkMessage;
    expect(sdk.requestId, 'req-1');
    expect(sdk.sessionId, 'session-1');
    expect(sdk.message['result'], 'ok');
  });

  test('decodes turn timeline messages', () {
    final message = decodeBridgeServerMessage(
      '{"type":"turn_timeline","requestId":"req-1","stage":"sdk_first_message","status":"completed","at":"2026-06-21T00:00:00.000Z","durationMs":842,"detail":"First SDK message: system.","toolName":"Bash","toolUseId":"tool-1"}',
    );

    expect(message, isA<BridgeTurnTimelineMessage>());
    final timeline = message as BridgeTurnTimelineMessage;
    expect(timeline.requestId, 'req-1');
    expect(timeline.stage, 'sdk_first_message');
    expect(timeline.status, 'completed');
    expect(timeline.durationMs, 842);
    expect(timeline.detail, 'First SDK message: system.');
    expect(timeline.toolName, 'Bash');
    expect(timeline.toolUseId, 'tool-1');
  });

  test('decodes error and closed messages', () {
    final error = decodeBridgeServerMessage(
      '{"type":"error","requestId":"req-1","code":"BAD_MESSAGE","message":"bad"}',
    );
    final closed = decodeBridgeServerMessage(
      '{"type":"closed","requestId":"req-1"}',
    );

    expect(error, isA<BridgeErrorMessage>());
    expect((error as BridgeErrorMessage).code, 'BAD_MESSAGE');
    expect(closed, isA<BridgeClosedMessage>());
    expect((closed as BridgeClosedMessage).requestId, 'req-1');
  });

  test('decodes extension runtime messages', () {
    final message = decodeBridgeServerMessage(
      '{"type":"extension_runtime","requestId":"req-1","runtime":{"mcpServers":["filesystem"],"skills":["debug"],"warnings":["MCP server github failed to connect."]}}',
    );

    expect(message, isA<BridgeExtensionRuntimeMessage>());
    final runtime = message as BridgeExtensionRuntimeMessage;
    expect(runtime.requestId, 'req-1');
    expect(runtime.mcpServers, ['filesystem']);
    expect(runtime.skills, ['debug']);
    expect(runtime.warnings.single, contains('github'));
  });

  test('decodes context index progress, result, and error messages', () {
    final progress = decodeBridgeServerMessage(
      '{"type":"context_index_progress","requestId":"idx-1","target":"directory","path":"docs","status":"indexing"}',
    );
    final result = decodeBridgeServerMessage(
      '{"type":"context_index_result","requestId":"idx-1","result":{"target":"directory","path":"docs","indexedNodes":2,"sourcePaths":["docs/provider-guide.md"]}}',
    );
    final error = decodeBridgeServerMessage(
      '{"type":"context_index_error","requestId":"idx-1","code":"CONTEXT_INDEX_FAILED","message":"Unsupported structured document file"}',
    );

    expect(progress, isA<BridgeContextIndexProgressMessage>());
    final progressMessage = progress as BridgeContextIndexProgressMessage;
    expect(progressMessage.target, 'directory');
    expect(progressMessage.path, 'docs');

    expect(result, isA<BridgeContextIndexResultMessage>());
    final resultMessage = result as BridgeContextIndexResultMessage;
    expect(resultMessage.indexedNodes, 2);
    expect(resultMessage.sourcePaths, ['docs/provider-guide.md']);

    expect(error, isA<BridgeContextIndexErrorMessage>());
    expect(
      (error as BridgeContextIndexErrorMessage).message,
      contains('Unsupported'),
    );
  });

  test('decodes context learn result messages', () {
    final message = decodeBridgeServerMessage(
      '{"type":"context_learn_result","requestId":"learn-1","result":{"candidates":[{"source":"profile","confidence":0.85,"reason":"Detected an explicit user preference.","evidence":"I prefer concise answers.","fact":{"id":"profile:preference:concise-answers","label":"Preference","content":"User prefers concise answers.","visibility":"workspace","consent":"allowed"}}]}}',
    );

    expect(message, isA<BridgeContextLearnResultMessage>());
    final learn = message as BridgeContextLearnResultMessage;
    expect(learn.requestId, 'learn-1');
    expect(learn.candidates.single.source, 'profile');
    expect(
      learn.candidates.single.fact['content'],
      'User prefers concise answers.',
    );
  });

  test('decodes context fact upsert result and error messages', () {
    final result = decodeBridgeServerMessage(
      '{"type":"context_fact_upsert_result","requestId":"fact-1","result":{"source":"profile","id":"profile:preference:concise-answers"}}',
    );
    final error = decodeBridgeServerMessage(
      '{"type":"context_fact_upsert_error","requestId":"fact-2","code":"CONTEXT_FACT_UPSERT_FAILED","message":"bad fact"}',
    );

    expect(result, isA<BridgeContextFactUpsertResultMessage>());
    final upsert = result as BridgeContextFactUpsertResultMessage;
    expect(upsert.source, 'profile');
    expect(upsert.id, 'profile:preference:concise-answers');

    expect(error, isA<BridgeContextFactUpsertErrorMessage>());
    expect((error as BridgeContextFactUpsertErrorMessage).message, 'bad fact');
  });

  test('decodes context facts list and delete result messages', () {
    final list = decodeBridgeServerMessage(
      '{"type":"context_facts_list_result","requestId":"facts-1","result":{"facts":[{"source":"profile","disabled":false,"fact":{"id":"profile-tone","label":"Preferred tone","content":"User prefers concise answers.","visibility":"workspace","consent":"allowed"}}]}}',
    );
    final deleted = decodeBridgeServerMessage(
      '{"type":"context_fact_delete_result","requestId":"delete-1","result":{"source":"profile","id":"profile-tone"}}',
    );

    expect(list, isA<BridgeContextFactsListResultMessage>());
    final listMessage = list as BridgeContextFactsListResultMessage;
    expect(listMessage.facts.single.source, 'profile');
    expect(listMessage.facts.single.disabled, isFalse);
    expect(
      listMessage.facts.single.fact['content'],
      'User prefers concise answers.',
    );

    expect(deleted, isA<BridgeContextFactDeleteResultMessage>());
    expect(
      (deleted as BridgeContextFactDeleteResultMessage).id,
      'profile-tone',
    );
  });

  test('decodes skills and MCP inventory snapshots', () {
    final skills = decodeBridgeServerMessage(
      '{"type":"skills_snapshot","requestId":"skills-1","skills":[{"id":"debug","name":"debug","description":"Debug a failing workflow.","source":"bundled","status":"enabled"}]}',
    );
    final servers = decodeBridgeServerMessage(
      '{"type":"mcp_servers_snapshot","requestId":"mcp-1","servers":[{"id":"filesystem","name":"filesystem","transport":"stdio","scope":"project","enabled":true,"status":"unknown","toolCount":0,"resourceCount":0,"skillCount":0}]}',
    );
    final capabilities = decodeBridgeServerMessage(
      '{"type":"mcp_server_capabilities","requestId":"mcp-capabilities-1","capabilities":{"serverId":"filesystem","tools":[{"name":"read_file","description":"Read a file."}],"resources":[],"prompts":[],"skills":[]}}',
    );
    final testResult = decodeBridgeServerMessage(
      '{"type":"mcp_server_test_result","requestId":"mcp-test-1","result":{"serverId":"filesystem","status":"connected","message":"Connected","durationMs":42,"checkedAt":"2026-06-20T00:00:00.000Z","capabilities":{"serverId":"filesystem","tools":[{"name":"read_file","description":"Read a file."}],"resources":[{"name":"file://workspace"}],"prompts":[{"name":"summarize"}],"skills":[]}}}',
    );

    expect(skills, isA<BridgeSkillsSnapshotMessage>());
    expect((skills as BridgeSkillsSnapshotMessage).skills.single.name, 'debug');
    expect(skills.skills.single.source, 'bundled');

    expect(servers, isA<BridgeMcpServersSnapshotMessage>());
    final server = (servers as BridgeMcpServersSnapshotMessage).servers.single;
    expect(server.name, 'filesystem');
    expect(server.transport, 'stdio');
    expect(server.enabled, isTrue);

    expect(capabilities, isA<BridgeMcpServerCapabilitiesMessage>());
    final tool =
        (capabilities as BridgeMcpServerCapabilitiesMessage).tools.single;
    expect(tool.name, 'read_file');
    expect(tool.description, 'Read a file.');

    expect(testResult, isA<BridgeMcpServerTestResultMessage>());
    final result = testResult as BridgeMcpServerTestResultMessage;
    expect(result.serverId, 'filesystem');
    expect(result.status, 'connected');
    expect(result.durationMs, 42);
    expect(result.tools.single.name, 'read_file');
    expect(result.resources.single.name, 'file://workspace');
    expect(result.prompts.single.name, 'summarize');
  });

  test('decodes skill imported and updated messages', () {
    final imported = decodeBridgeServerMessage(
      '{"type":"skill_imported","requestId":"skill-import-1","skill":{"id":"debug","name":"debug","description":"Debug a failing workflow.","source":"local","status":"enabled","path":"/tmp/skills/debug"}}',
    );
    final updated = decodeBridgeServerMessage(
      '{"type":"skill_updated","requestId":"skill-enable-1","skill":{"id":"debug","name":"debug","description":"Debug a failing workflow.","source":"local","status":"disabled","path":"/tmp/skills/debug"}}',
    );

    expect(imported, isA<BridgeSkillImportedMessage>());
    final importedMessage = imported as BridgeSkillImportedMessage;
    expect(importedMessage.skill.name, 'debug');
    expect(importedMessage.skill.path, '/tmp/skills/debug');

    expect(updated, isA<BridgeSkillUpdatedMessage>());
    expect((updated as BridgeSkillUpdatedMessage).skill.status, 'disabled');
  });

  test('decodes MCP server saved and deleted messages', () {
    final saved = decodeBridgeServerMessage(
      '{"type":"mcp_server_saved","requestId":"mcp-save-1","server":{"id":"filesystem-server","name":"filesystem-server","transport":"stdio","scope":"project","enabled":true,"status":"unknown","toolCount":0,"resourceCount":0,"skillCount":0,"command":"npx","args":["-y","@modelcontextprotocol/server-filesystem"],"env":{"FILESYSTEM_TOKEN":"********"}}}',
    );
    final deleted = decodeBridgeServerMessage(
      '{"type":"mcp_server_deleted","requestId":"mcp-delete-1","serverId":"filesystem-server"}',
    );

    expect(saved, isA<BridgeMcpServerSavedMessage>());
    final savedMessage = saved as BridgeMcpServerSavedMessage;
    expect(savedMessage.server.id, 'filesystem-server');
    expect(savedMessage.server.command, 'npx');
    expect(savedMessage.server.args, [
      '-y',
      '@modelcontextprotocol/server-filesystem',
    ]);
    expect(savedMessage.server.env, {'FILESYSTEM_TOKEN': '********'});

    expect(deleted, isA<BridgeMcpServerDeletedMessage>());
    expect(
      (deleted as BridgeMcpServerDeletedMessage).serverId,
      'filesystem-server',
    );
  });
}
