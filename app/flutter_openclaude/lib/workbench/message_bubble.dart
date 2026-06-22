import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'workbench_models.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({super.key, required this.message, this.onSelected});

  final ChatMessage message;
  final VoidCallback? onSelected;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  var _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = widget.message.role == MessageRole.user;
    final isAssistant = widget.message.role == MessageRole.assistant;
    final roleLabel = switch (widget.message.role) {
      MessageRole.user => 'You',
      MessageRole.assistant => 'Assistant',
      MessageRole.system => 'System',
    };
    final background = switch (widget.message.role) {
      MessageRole.user => theme.colorScheme.primaryContainer,
      MessageRole.assistant => Colors.white,
      MessageRole.system => theme.colorScheme.secondaryContainer,
    };
    const assistantHoverBorder = Color(0xFF93C5FD);
    final radius = BorderRadius.circular(8);
    final border = Border.all(
      color: isAssistant && _isHovered
          ? assistantHoverBorder
          : Colors.transparent,
      width: isAssistant ? 1 : 0,
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            key: ValueKey('message-bubble-${widget.message.id}'),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: background,
              borderRadius: radius,
              border: border,
            ),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: radius,
                hoverColor: Colors.transparent,
                highlightColor: isAssistant
                    ? assistantHoverBorder.withValues(alpha: 0.08)
                    : theme.colorScheme.primary.withValues(alpha: 0.08),
                onTap: widget.onSelected,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            roleLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.message.timestampLabel,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (isUser)
                        Text(widget.message.content)
                      else
                        SelectionArea(
                          child: GptMarkdown(
                            key: ValueKey(
                              'message-markdown-${widget.message.id}',
                            ),
                            widget.message.content,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      if (widget.message.attachments.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _MessageAttachmentRow(
                          attachments: widget.message.attachments,
                        ),
                      ],
                      if (!isUser && widget.message.tokenUsage != null) ...[
                        const SizedBox(height: 10),
                        _TokenUsageRow(usage: widget.message.tokenUsage!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageAttachmentRow extends StatelessWidget {
  const _MessageAttachmentRow({required this.attachments});

  final List<ChatAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final attachment in attachments)
          DecoratedBox(
            key: ValueKey('message-attachment-${attachment.id}'),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.62,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconForAttachment(attachment), size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      attachment.name,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  IconData _iconForAttachment(ChatAttachment attachment) {
    return switch (attachment.kind) {
      ChatAttachmentKind.image => Icons.image_outlined,
      ChatAttachmentKind.text => Icons.description_outlined,
      ChatAttachmentKind.file => Icons.insert_drive_file_outlined,
    };
  }
}

class _TokenUsageRow extends StatelessWidget {
  const _TokenUsageRow({required this.usage});

  final ChatTokenUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = [
      _TokenUsageChip(label: 'Input', value: usage.inputTokens),
      _TokenUsageChip(label: 'Output', value: usage.outputTokens),
      if (usage.cacheReadInputTokens > 0)
        _TokenUsageChip(label: 'Cache read', value: usage.cacheReadInputTokens),
      if (usage.cacheCreationInputTokens > 0)
        _TokenUsageChip(
          label: 'Cache write',
          value: usage.cacheCreationInputTokens,
        ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final token in tokens)
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.62,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '${token.label} ${_formatTokenCount(token.value)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TokenUsageChip {
  const _TokenUsageChip({required this.label, required this.value});

  final String label;
  final int value;
}

String _formatTokenCount(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index += 1) {
    final remaining = text.length - index;
    buffer.write(text[index]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}
