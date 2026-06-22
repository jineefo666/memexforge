import 'package:flutter/material.dart';
import 'package:flutter_openclaude/workbench/inspector_panel.dart';
import 'package:flutter_openclaude/workbench/permission_dialog.dart';
import 'package:flutter_openclaude/workbench/tool_call_card.dart';
import 'package:flutter_openclaude/workbench/workbench_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tool card renders status and selection callback', (
    tester,
  ) async {
    String? selected;
    const tool = ToolRun(
      id: 'tool-1',
      name: 'Bridge smoke test',
      command: 'bun run app-bridge --help',
      status: ToolRunStatus.success,
      summary: 'App bridge command is available.',
      details: 'Verified WebSocket bridge CLI help output.',
      elapsedLabel: '0.8s',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolCallCard(
            toolRun: tool,
            onSelected: () => selected = tool.id,
          ),
        ),
      ),
    );

    expect(find.text(tool.name), findsOneWidget);
    expect(find.text('Success'), findsOneWidget);

    await tester.tap(find.byType(ToolCallCard));
    expect(selected, tool.id);
  });

  testWidgets('permission dialog emits allow and deny decisions', (
    tester,
  ) async {
    final request = PermissionRequest(
      id: 'perm-1',
      requestId: 'req-1',
      toolUseId: 'tool-1',
      title: 'Run shell command',
      action: 'bun test',
      riskSummary: 'Executes a local command.',
      rawPayload: '{"tool":"bash"}',
    );
    final decisions = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => PermissionDialog(
                  request: request,
                  onDecision: decisions.add,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('needs your permission to continue'),
      findsOneWidget,
    );
    expect(find.textContaining('Executes a local command.'), findsOneWidget);

    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();

    expect(decisions, ['allow']);
  });

  testWidgets('permission dialog emits allow all decision', (tester) async {
    final request = PermissionRequest(
      id: 'perm-1',
      requestId: 'req-1',
      toolUseId: 'tool-1',
      title: 'Run shell command',
      action: 'bun test',
      riskSummary: 'Executes a local command.',
      rawPayload: '{"tool":"bash"}',
    );
    final decisions = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => PermissionDialog(
                  request: request,
                  onDecision: decisions.add,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Allow all'));
    await tester.pumpAndSettle();

    expect(decisions, ['allow_all']);
  });

  testWidgets('inspector hides empty context placeholders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: InspectorPanel(state: createInitialWorkbenchState())),
    );

    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('Context overview'), findsNothing);
    expect(find.text('Context'), findsNothing);
    expect(find.text('Retrieved context'), findsNothing);
    expect(find.text('Memory and profile'), findsNothing);
    expect(find.text('Document structure'), findsNothing);
    expect(find.textContaining('P2'), findsNothing);
  });

  testWidgets('inspector shows retrieved context items', (tester) async {
    final state = createInitialWorkbenchState().copyWith(
      retrievedContextItems: const [
        RetrievedContextItem(
          source: 'transcript',
          title: 'Transcript message 1',
          content: 'Provider API key setup was discussed.',
          score: 1,
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(home: InspectorPanel(state: state)));

    expect(find.text('Retrieved context'), findsOneWidget);
    expect(find.text('Transcript message 1'), findsOneWidget);
    expect(find.text('Provider API key setup was discussed.'), findsOneWidget);
  });

  testWidgets('inspector shows saved memory and profile facts', (tester) async {
    final state = createInitialWorkbenchState().copyWith(
      memoryFacts: const [
        MemoryFact(
          source: 'profile',
          id: 'profile:preference:cherries',
          title: 'Preference',
          content: 'User prefers 吃樱桃.',
          disabled: false,
          fact: {
            'id': 'profile:preference:cherries',
            'label': 'Preference',
            'content': 'User prefers 吃樱桃.',
            'visibility': 'workspace',
            'consent': 'allowed',
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(home: InspectorPanel(state: state)));

    expect(find.text('Memory and profile'), findsOneWidget);
    expect(find.text('Preference'), findsOneWidget);
    expect(find.text('User prefers 吃樱桃.'), findsOneWidget);
    expect(
      find.text('User profile and usage habits will appear here.'),
      findsNothing,
    );
  });
}
