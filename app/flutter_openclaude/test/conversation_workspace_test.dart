import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_openclaude/workbench/conversation_workspace.dart';
import 'package:flutter_openclaude/workbench/tool_call_card.dart';
import 'package:flutter_openclaude/workbench/workbench_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<ChatMessage> scrollMessages(int count) {
    return [
      for (var index = 0; index < count; index += 1)
        ChatMessage(
          id: 'scroll-message-$index',
          role: index.isEven ? MessageRole.user : MessageRole.assistant,
          content:
              'Scroll message $index\n'
              'This message has enough body text to make the chat list tall.',
          timestampLabel: 'Now',
        ),
    ];
  }

  Future<void> pumpConversation(
    WidgetTester tester,
    WorkbenchState state,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationWorkspace(state: state)),
      ),
    );
  }

  testWidgets('conversation renders messages and sends composer text', (
    tester,
  ) async {
    String? sent;
    final state = createInitialWorkbenchState();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationWorkspace(
            state: state,
            onSendMessage: (text) => sent = text,
          ),
        ),
      ),
    );

    expect(state.messages, isEmpty);
    expect(find.byType(ToolCallCard), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('composer-input')),
      'Build the UI',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(sent, 'Build the UI');
    expect(find.text('Build the UI'), findsNothing);
  });

  testWidgets('composer sends on Enter and inserts newline on Option Enter', (
    tester,
  ) async {
    String? sent;
    final state = createInitialWorkbenchState();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationWorkspace(
            state: state,
            onSendMessage: (text) => sent = text,
          ),
        ),
      ),
    );

    final input = find.byKey(const ValueKey('composer-input'));
    await tester.tap(input);
    await tester.enterText(input, 'Line one');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    expect(sent, isNull);
    expect(tester.widget<TextField>(input).controller?.text, 'Line one\n');

    await tester.enterText(input, 'Build the UI');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, 'Build the UI');
    expect(tester.widget<TextField>(input).controller?.text, isEmpty);
  });

  testWidgets('conversation shows stop action while streaming', (tester) async {
    var stopped = false;
    final state = createInitialWorkbenchState().copyWith(isStreaming: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationWorkspace(
            state: state,
            onStop: () => stopped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Stop'));
    expect(stopped, isTrue);
  });

  testWidgets('composer think mode button toggles personal setting', (
    tester,
  ) async {
    bool? nextThinkingMode;
    final state = createInitialWorkbenchState();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationWorkspace(
            state: state,
            onThinkingModeChanged: (enabled) => nextThinkingMode = enabled,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Think mode on'));
    await tester.pump();

    expect(nextThinkingMode, isFalse);
  });

  testWidgets('composer think mode button matches send button size', (
    tester,
  ) async {
    final state = createInitialWorkbenchState();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationWorkspace(state: state)),
      ),
    );

    final thinkSize = tester.getSize(find.byTooltip('Think mode on'));
    final sendSize = tester.getSize(find.byTooltip('Send'));

    expect(thinkSize, sendSize);
  });

  testWidgets('user messages render attachment chips', (tester) async {
    final state = createInitialWorkbenchState().copyWith(
      messages: const [
        ChatMessage(
          id: 'message-1',
          role: MessageRole.user,
          content: 'Use this mockup',
          timestampLabel: 'Now',
          attachments: [
            ChatAttachment(
              id: 'image-1',
              name: 'mockup.png',
              mimeType: 'image/png',
              sizeBytes: 4096,
              kind: ChatAttachmentKind.image,
              path: '/tmp/mockup.png',
            ),
          ],
        ),
      ],
    );

    await pumpConversation(tester, state);

    expect(find.text('Use this mockup'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('message-attachment-image-1')),
      findsOneWidget,
    );
    expect(find.text('mockup.png'), findsOneWidget);
  });

  testWidgets('composer attachment button adds removable file chips', (
    tester,
  ) async {
    ChatSendRequest? sent;
    final state = createInitialWorkbenchState();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationWorkspace(
            state: state,
            onPickAttachments: () async => const [
              ChatAttachment(
                id: 'attachment-1',
                name: 'notes.txt',
                mimeType: 'text/plain',
                sizeBytes: 42,
                kind: ChatAttachmentKind.text,
                content: 'Project notes',
              ),
            ],
            onSendRequest: (request) => sent = request,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Attach context'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('composer-attachment-attachment-1')),
      findsOneWidget,
    );
    expect(find.text('notes.txt'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove notes.txt'));
    await tester.pump();

    expect(find.text('notes.txt'), findsNothing);

    await tester.tap(find.byTooltip('Attach context'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('composer-input')),
      'Summarize this',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(sent?.text, 'Summarize this');
    expect(sent?.attachments.single.name, 'notes.txt');
    expect(find.text('notes.txt'), findsNothing);
  });

  testWidgets('composer drop handler adds dropped file chips', (tester) async {
    final state = createInitialWorkbenchState();
    final dropController = ChatAttachmentDropController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationWorkspace(
            state: state,
            attachmentDropController: dropController,
          ),
        ),
      ),
    );

    dropController.addAttachments(const [
      ChatAttachment(
        id: 'image-1',
        name: 'mockup.png',
        mimeType: 'image/png',
        sizeBytes: 2048,
        kind: ChatAttachmentKind.image,
        path: '/tmp/mockup.png',
      ),
    ]);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('composer-attachment-image-1')),
      findsOneWidget,
    );
    expect(find.text('mockup.png'), findsOneWidget);
  });

  testWidgets('composer exposes a native file drop target', (tester) async {
    final state = createInitialWorkbenchState();

    await pumpConversation(tester, state);

    expect(find.byType(DropTarget), findsOneWidget);
  });

  testWidgets('composer opens slash command palette from slash input', (
    tester,
  ) async {
    final state = createInitialWorkbenchState();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationWorkspace(state: state)),
      ),
    );

    final input = find.byKey(const ValueKey('composer-input'));
    await tester.enterText(input, '/');
    await tester.pump();

    expect(find.byKey(const ValueKey('slash-command-palette')), findsOneWidget);
    expect(find.text('/provider'), findsOneWidget);
    expect(find.text('/tools'), findsOneWidget);

    await tester.tap(find.text('/provider'));
    await tester.pump();

    expect(find.byKey(const ValueKey('slash-command-palette')), findsNothing);
    expect(tester.widget<TextField>(input).controller?.text, '/provider ');
  });

  testWidgets('composer slash palette lists enabled skills', (tester) async {
    final state = createInitialWorkbenchState().copyWith(
      extensions: const ExtensionsState(
        skillsStatus: ExtensionInventoryStatus.loaded,
        skills: [
          SkillSummary(
            id: 'debug',
            name: 'debug',
            description: 'Debug a failing workflow.',
            source: 'local',
            status: 'enabled',
          ),
          SkillSummary(
            id: 'draft-docs',
            name: 'draft-docs',
            description: 'Draft project documentation.',
            source: 'local',
            status: 'disabled',
          ),
        ],
        mcpStatus: ExtensionInventoryStatus.idle,
        mcpServers: [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationWorkspace(state: state)),
      ),
    );

    final input = find.byKey(const ValueKey('composer-input'));
    await tester.enterText(input, '/');
    await tester.pump();

    expect(find.text('/debug'), findsOneWidget);
    expect(find.text('Debug a failing workflow.'), findsOneWidget);
    expect(find.text('/draft-docs'), findsNothing);

    await tester.tap(find.text('/debug'));
    await tester.pump();

    expect(tester.widget<TextField>(input).controller?.text, '/debug ');
  });

  testWidgets('conversation scrolls to the latest user message after send', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final initialState = createInitialWorkbenchState().copyWith(
      messages: scrollMessages(28),
    );
    final sentState = initialState.copyWith(
      isStreaming: true,
      messages: [
        ...initialState.messages,
        const ChatMessage(
          id: 'latest-user-message',
          role: MessageRole.user,
          content: 'Latest user prompt',
          timestampLabel: 'Now',
        ),
      ],
    );

    await pumpConversation(tester, initialState);
    expect(find.text('Latest user prompt'), findsNothing);

    await pumpConversation(tester, sentState);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('Latest user prompt'), findsOneWidget);
  });

  testWidgets('conversation follows assistant replies while at the bottom', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final initialState = createInitialWorkbenchState().copyWith(
      messages: [
        ...scrollMessages(28),
        const ChatMessage(
          id: 'waiting-user-message',
          role: MessageRole.user,
          content: 'Waiting for reply',
          timestampLabel: 'Now',
        ),
      ],
    );
    final repliedState = initialState.copyWith(
      messages: [
        ...initialState.messages,
        const ChatMessage(
          id: 'latest-assistant-message',
          role: MessageRole.assistant,
          content: 'Latest assistant reply',
          timestampLabel: 'Now',
        ),
      ],
    );

    await pumpConversation(tester, initialState);
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for reply'), findsOneWidget);

    await pumpConversation(tester, repliedState);
    await tester.pumpAndSettle();

    expect(find.text('Latest assistant reply'), findsOneWidget);
  });

  testWidgets('conversation follows streaming assistant content growth', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const streamingMessageId = 'streaming-assistant-message';
    final initialState = createInitialWorkbenchState().copyWith(
      isStreaming: true,
      messages: [
        ...scrollMessages(24),
        const ChatMessage(
          id: 'streaming-user-message',
          role: MessageRole.user,
          content: 'Stream a long reply',
          timestampLabel: 'Now',
        ),
        const ChatMessage(
          id: streamingMessageId,
          role: MessageRole.assistant,
          content: 'Partial reply',
          timestampLabel: 'Now',
        ),
      ],
    );
    final streamedState = initialState.copyWith(
      isStreaming: true,
      messages: [
        ...initialState.messages.take(initialState.messages.length - 1),
        ChatMessage(
          id: streamingMessageId,
          role: MessageRole.assistant,
          content:
              '${List.generate(36, (index) => 'Streaming line $index').join('\n')}\nSTREAM_END_MARKER',
          timestampLabel: 'Now',
        ),
      ],
    );

    await pumpConversation(tester, initialState);
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('Partial reply'), findsOneWidget);

    await pumpConversation(tester, streamedState);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(
      scrollable.position.maxScrollExtent - scrollable.position.pixels,
      lessThanOrEqualTo(1),
    );
    expect(find.textContaining('STREAM_END_MARKER'), findsOneWidget);
  });

  testWidgets('conversation does not follow replies after manual scroll up', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final initialState = createInitialWorkbenchState().copyWith(
      messages: [
        ...scrollMessages(32),
        const ChatMessage(
          id: 'tail-user-message',
          role: MessageRole.user,
          content: 'Tail user prompt',
          timestampLabel: 'Now',
        ),
      ],
    );
    final repliedState = initialState.copyWith(
      messages: [
        ...initialState.messages,
        const ChatMessage(
          id: 'assistant-after-scroll-up',
          role: MessageRole.assistant,
          content: 'Assistant reply after manual scroll',
          timestampLabel: 'Now',
        ),
      ],
    );

    await pumpConversation(tester, initialState);
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(find.text('Tail user prompt'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('Tail user prompt'), findsNothing);

    await pumpConversation(tester, repliedState);
    await tester.pumpAndSettle();

    expect(find.text('Assistant reply after manual scroll'), findsNothing);
  });

  testWidgets('conversation shows streaming status after latest user message', (
    tester,
  ) async {
    final state = createInitialWorkbenchState().copyWith(
      isStreaming: true,
      messages: const [
        ChatMessage(
          id: 'message-1',
          role: MessageRole.user,
          content: 'Explain the bridge flow',
          timestampLabel: 'Now',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationWorkspace(state: state)),
      ),
    );

    final messageFinder = find.text('Explain the bridge flow');
    final streamingFinder = find.byKey(
      const ValueKey('inline-streaming-indicator'),
    );

    expect(messageFinder, findsOneWidget);
    expect(streamingFinder, findsOneWidget);
    expect(find.text('Thinking...'), findsOneWidget);
    expect(
      tester.getTopLeft(streamingFinder).dy,
      greaterThan(tester.getTopLeft(messageFinder).dy),
    );
  });

  testWidgets('conversation header shows active workspace path', (
    tester,
  ) async {
    final state = createInitialWorkbenchState().copyWith(
      sessions: const [
        SessionSummary(
          id: 'session-test',
          title: 'testclaude',
          subtitle: '/workspace/testclaude',
          status: SessionStatus.idle,
          updatedLabel: 'Now',
        ),
      ],
      activeSessionId: 'session-test',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationWorkspace(state: state)),
      ),
    );

    expect(find.textContaining('/workspace/testclaude'), findsOneWidget);
  });

  testWidgets(
    'conversation shows only the active tool run while it is pending',
    (tester) async {
      final state = createInitialWorkbenchState().copyWith(
        toolRuns: const [
          ToolRun(
            id: 'tool-old',
            name: 'Bash',
            command: 'echo done',
            status: ToolRunStatus.success,
            summary: 'Completed',
            details: '{}',
            elapsedLabel: '1s',
          ),
          ToolRun(
            id: 'tool-active',
            name: 'Bash',
            command: 'touch text.txt',
            status: ToolRunStatus.running,
            summary: 'Executing approved command',
            details: '{}',
            elapsedLabel: 'Now',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ConversationWorkspace(state: state)),
        ),
      );

      expect(find.byType(ToolCallCard), findsOneWidget);
      expect(find.textContaining('touch text.txt'), findsOneWidget);
      expect(find.text('echo done'), findsNothing);
    },
  );

  testWidgets('conversation removes tool run after it completes', (
    tester,
  ) async {
    final state = createInitialWorkbenchState().copyWith(
      toolRuns: const [
        ToolRun(
          id: 'tool-complete',
          name: 'Bash',
          command: 'touch text.txt',
          status: ToolRunStatus.success,
          summary: 'Completed',
          details: '{}',
          elapsedLabel: '1s',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationWorkspace(state: state)),
      ),
    );

    expect(find.byType(ToolCallCard), findsNothing);
    expect(find.text('touch text.txt'), findsNothing);
  });

  testWidgets('assistant markdown messages render instead of raw source', (
    tester,
  ) async {
    const markdown = '''
## Plan

- **Build** the UI
- Add `tests`

```dart
void main() {}
```
''';
    final state = createInitialWorkbenchState().copyWith(
      messages: const [
        ChatMessage(
          id: 'message-1',
          role: MessageRole.assistant,
          content: markdown,
          timestampLabel: 'Now',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationWorkspace(state: state)),
      ),
    );

    expect(find.text(markdown), findsNothing);
    expect(
      find.byKey(const ValueKey('message-markdown-message-1')),
      findsOneWidget,
    );
  });

  testWidgets('assistant messages show input and output token usage', (
    tester,
  ) async {
    final state = createInitialWorkbenchState().copyWith(
      messages: const [
        ChatMessage(
          id: 'message-token-usage',
          role: MessageRole.assistant,
          content: 'Token counted reply',
          timestampLabel: 'Now',
          tokenUsage: ChatTokenUsage(inputTokens: 1234, outputTokens: 56),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationWorkspace(state: state)),
      ),
    );

    expect(find.text('Input 1,234'), findsOneWidget);
    expect(find.text('Output 56'), findsOneWidget);
  });

  testWidgets('conversation header shows bridge errors', (tester) async {
    final state = createInitialWorkbenchState().copyWith(
      connectionStatus: ConnectionStatus.error,
      errorMessage: 'App bridge connection failed',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationWorkspace(state: state)),
      ),
    );

    expect(find.text('Connection error'), findsOneWidget);
    expect(find.text('App bridge connection failed'), findsOneWidget);
  });

  testWidgets('conversation header shows request errors separately', (
    tester,
  ) async {
    final state = createInitialWorkbenchState().copyWith(
      connectionStatus: ConnectionStatus.connected,
      errorMessage: 'Provider rejected the request',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationWorkspace(state: state)),
      ),
    );

    expect(find.text('Request error'), findsOneWidget);
    expect(find.text('Provider rejected the request'), findsOneWidget);
  });

  testWidgets('conversation shows learning candidate cards', (tester) async {
    String? acceptedId;
    String? dismissedId;
    final state = createInitialWorkbenchState().copyWith(
      learningCandidates: const [
        LearningCandidate(
          id: 'profile:preference:concise-answers',
          source: 'profile',
          confidence: 0.85,
          reason: 'Detected an explicit user preference.',
          evidence: 'I prefer concise answers.',
          fact: {
            'id': 'profile:preference:concise-answers',
            'label': 'Preference',
            'content': 'User prefers concise answers.',
            'visibility': 'workspace',
            'consent': 'allowed',
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationWorkspace(
            state: state,
            onLearningCandidateAccepted: (id) => acceptedId = id,
            onLearningCandidateDismissed: (id) => dismissedId = id,
          ),
        ),
      ),
    );

    expect(find.text('Learning candidate'), findsOneWidget);
    expect(find.text('User prefers concise answers.'), findsOneWidget);

    await tester.tap(find.byTooltip('Save memory'));
    expect(acceptedId, 'profile:preference:concise-answers');

    await tester.tap(find.byTooltip('Dismiss memory'));
    expect(dismissedId, 'profile:preference:concise-answers');
  });
}
