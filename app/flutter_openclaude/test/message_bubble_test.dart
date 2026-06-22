import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_openclaude/workbench/message_bubble.dart';
import 'package:flutter_openclaude/workbench/workbench_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'assistant message bubble updates markdown for streamed content',
    (tester) async {
      const messageId = 'assistant-stream';

      Future<void> pumpBubble(String content) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: ChatMessage(
                  id: messageId,
                  role: MessageRole.assistant,
                  content: content,
                  timestampLabel: 'Now',
                ),
              ),
            ),
          ),
        );
      }

      await pumpBubble('Partial reply');
      expect(find.text('Partial reply'), findsOneWidget);

      await pumpBubble('STREAM_END_MARKER');
      await tester.pump();

      expect(find.text('Partial reply'), findsNothing);
      expect(find.text('STREAM_END_MARKER'), findsOneWidget);
    },
  );

  testWidgets(
    'assistant message bubble stays white and adds blue hover border',
    (tester) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                id: 'assistant-1',
                role: MessageRole.assistant,
                content: 'Ready',
                timestampLabel: 'Now',
              ),
            ),
          ),
        ),
      );

      BoxDecoration bubbleDecoration() {
        final bubble = tester.widget<AnimatedContainer>(
          find.byKey(const ValueKey('message-bubble-assistant-1')),
        );
        return bubble.decoration! as BoxDecoration;
      }

      final initialDecoration = bubbleDecoration();
      expect(initialDecoration.color, Colors.white);
      expect(initialDecoration.border!.top.color, Colors.transparent);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer();
      await gesture.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('message-bubble-assistant-1')),
        ),
      );
      await tester.pumpAndSettle();

      final hoveredDecoration = bubbleDecoration();
      expect(hoveredDecoration.color, Colors.white);
      expect(hoveredDecoration.border!.top.color, const Color(0xFF93C5FD));
    },
  );
}
