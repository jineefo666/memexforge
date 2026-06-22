import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';

import 'app_branding.dart';
import 'chat_attachment_picker.dart';
import 'message_bubble.dart';
import 'tool_call_card.dart';
import 'workbench_models.dart';

typedef ChatAttachmentPicker = Future<List<ChatAttachment>> Function();
typedef ChatSendRequestHandler = void Function(ChatSendRequest request);

class ChatAttachmentDropController extends ChangeNotifier {
  final _pendingBatches = <List<ChatAttachment>>[];

  void addAttachments(List<ChatAttachment> attachments) {
    if (attachments.isEmpty) return;
    _pendingBatches.add(List.unmodifiable(attachments));
    notifyListeners();
  }

  List<ChatAttachment> takePendingAttachments() {
    if (_pendingBatches.isEmpty) return const [];
    final attachments = [for (final batch in _pendingBatches) ...batch];
    _pendingBatches.clear();
    return attachments;
  }
}

class ConversationWorkspace extends StatefulWidget {
  const ConversationWorkspace({
    super.key,
    required this.state,
    this.onSendMessage,
    this.onSendRequest,
    this.onThinkingModeChanged,
    this.onStop,
    this.onProjectDirectorySelected,
    this.onMessageSelected,
    this.onToolSelected,
    this.onLearningCandidateAccepted,
    this.onLearningCandidateDismissed,
    this.onPickAttachments,
    this.attachmentDropController,
  });

  final WorkbenchState state;
  final ValueChanged<String>? onSendMessage;
  final ChatSendRequestHandler? onSendRequest;
  final ValueChanged<bool>? onThinkingModeChanged;
  final VoidCallback? onStop;
  final VoidCallback? onProjectDirectorySelected;
  final ValueChanged<String>? onMessageSelected;
  final ValueChanged<String>? onToolSelected;
  final ValueChanged<String>? onLearningCandidateAccepted;
  final ValueChanged<String>? onLearningCandidateDismissed;
  final ChatAttachmentPicker? onPickAttachments;
  final ChatAttachmentDropController? attachmentDropController;

  @override
  State<ConversationWorkspace> createState() => _ConversationWorkspaceState();
}

class _ConversationWorkspaceState extends State<ConversationWorkspace> {
  final _composerController = TextEditingController();
  final _messageScrollController = ScrollController();
  bool _shouldFollowTail = true;

  @override
  void dispose() {
    _composerController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ConversationWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldMessages = oldWidget.state.messages;
    final messages = widget.state.messages;
    final hasNewUserMessage =
        messages.length > oldMessages.length &&
        messages.isNotEmpty &&
        messages.last.role == MessageRole.user;
    final tailChanged =
        _tailSignature(widget.state) != _tailSignature(oldWidget.state);

    if (hasNewUserMessage) {
      _shouldFollowTail = true;
      _scheduleScrollToTail();
    } else if (tailChanged && _shouldFollowTail) {
      _scheduleScrollToTail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showInlineStreaming =
        widget.state.isStreaming && widget.state.messages.isNotEmpty;
    final learningCandidates = widget.state.learningCandidates
        .where(
          (candidate) => candidate.status != LearningCandidateStatus.ignored,
        )
        .toList();
    final activeToolRun = _activeToolRunForChat(widget.state.toolRuns);
    return Container(
      key: const ValueKey('conversation-workspace'),
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            _ConversationHeader(
              state: widget.state,
              onProjectDirectorySelected: widget.onProjectDirectorySelected,
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: ListView.separated(
                  controller: _messageScrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  itemCount:
                      widget.state.messages.length +
                      (showInlineStreaming ? 1 : 0) +
                      learningCandidates.length +
                      (activeToolRun == null ? 0 : 1),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final messageCount = widget.state.messages.length;
                    if (index < messageCount) {
                      final message = widget.state.messages[index];
                      return MessageBubble(
                        message: message,
                        onSelected: () =>
                            widget.onMessageSelected?.call(message.id),
                      );
                    }
                    if (showInlineStreaming && index == messageCount) {
                      return const _InlineStreamingStatus();
                    }
                    final learningIndex =
                        index - messageCount - (showInlineStreaming ? 1 : 0);
                    if (learningIndex >= 0 &&
                        learningIndex < learningCandidates.length) {
                      final candidate = learningCandidates[learningIndex];
                      return _LearningCandidateCard(
                        candidate: candidate,
                        onAccepted: () => widget.onLearningCandidateAccepted
                            ?.call(candidate.id),
                        onDismissed: () => widget.onLearningCandidateDismissed
                            ?.call(candidate.id),
                      );
                    }
                    final toolIndex =
                        index -
                        messageCount -
                        (showInlineStreaming ? 1 : 0) -
                        learningCandidates.length;
                    if (toolIndex == 0 && activeToolRun != null) {
                      return ToolCallCard(
                        toolRun: activeToolRun,
                        onSelected: () =>
                            widget.onToolSelected?.call(activeToolRun.id),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
            _Composer(
              controller: _composerController,
              isStreaming: widget.state.isStreaming,
              thinkingModeEnabled: widget.state.personal.thinkingModeEnabled,
              skills: widget.state.extensions.skills,
              onSendMessage: widget.onSendMessage,
              onSendRequest: widget.onSendRequest,
              onThinkingModeChanged: widget.onThinkingModeChanged,
              onStop: widget.onStop,
              onPickAttachments: widget.onPickAttachments,
              attachmentDropController: widget.attachmentDropController,
            ),
          ],
        ),
      ),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final isUserDriven =
        notification is UserScrollNotification ||
        notification is ScrollUpdateNotification &&
            notification.dragDetails != null;
    if (isUserDriven) {
      _shouldFollowTail = _isNearTail(notification.metrics);
    }
    return false;
  }

  bool _isNearTail(ScrollMetrics metrics) {
    return metrics.maxScrollExtent - metrics.pixels <= 56;
  }

  void _scheduleScrollToTail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToTail();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToTail();
      });
    });
  }

  void _jumpToTail() {
    if (!mounted || !_messageScrollController.hasClients) return;
    final position = _messageScrollController.position;
    final target = position.maxScrollExtent;
    if ((position.pixels - target).abs() <= 1) return;
    _messageScrollController.jumpTo(target);
  }

  String _tailSignature(WorkbenchState state) {
    final lastMessage = state.messages.isEmpty ? null : state.messages.last;
    final learningCount = state.learningCandidates
        .where(
          (candidate) => candidate.status != LearningCandidateStatus.ignored,
        )
        .length;
    final activeToolRun = _activeToolRunForChat(state.toolRuns);
    return [
      state.messages.length,
      lastMessage?.id ?? '',
      lastMessage?.content.length ?? 0,
      state.isStreaming,
      learningCount,
      activeToolRun?.id,
      activeToolRun?.status.name,
    ].join(':');
  }

  ToolRun? _activeToolRunForChat(List<ToolRun> toolRuns) {
    for (final run in toolRuns) {
      if (run.status == ToolRunStatus.running) return run;
    }
    for (final run in toolRuns) {
      if (run.status == ToolRunStatus.pending) return run;
    }
    return null;
  }
}

class _LearningCandidateCard extends StatelessWidget {
  const _LearningCandidateCard({
    required this.candidate,
    required this.onAccepted,
    required this.onDismissed,
  });

  final LearningCandidate candidate;
  final VoidCallback? onAccepted;
  final VoidCallback? onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSaved = candidate.status == LearningCandidateStatus.saved;
    final isSaving = candidate.status == LearningCandidateStatus.saving;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Material(
          key: ValueKey('learning-candidate-${candidate.id}'),
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _iconForSource(candidate.source),
                      size: 18,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Learning candidate',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      candidate.sourceLabel,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(candidate.summary),
                if (candidate.evidence.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    candidate.evidence,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${(candidate.confidence * 100).round()}% confidence',
                      style: theme.textTheme.labelSmall,
                    ),
                    const Spacer(),
                    if (isSaved)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text('Saved', style: theme.textTheme.labelMedium),
                        ],
                      )
                    else ...[
                      Tooltip(
                        message: 'Dismiss memory',
                        child: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: isSaving ? null : onDismissed,
                        ),
                      ),
                      Tooltip(
                        message: 'Save memory',
                        child: IconButton.filledTonal(
                          icon: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          onPressed: isSaving ? null : onAccepted,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForSource(String source) {
    return switch (source) {
      'profile' => Icons.person_outline,
      'habit' => Icons.repeat,
      'graph' => Icons.account_tree_outlined,
      _ => Icons.auto_awesome_outlined,
    };
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.state,
    required this.onProjectDirectorySelected,
  });

  final WorkbenchState state;
  final VoidCallback? onProjectDirectorySelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = switch (state.connectionStatus) {
      ConnectionStatus.connected =>
        state.isStreaming
            ? 'Streaming'
            : state.errorMessage == null
            ? 'Ready'
            : 'Request error',
      ConnectionStatus.connecting => 'Connecting',
      ConnectionStatus.error => 'Connection error',
      ConnectionStatus.disconnected => 'Disconnected',
    };
    final activeExtensions = state.activeExtensions;
    final showActiveExtensions =
        activeExtensions.totalCount > 0 || activeExtensions.hasWarnings;
    final workspacePath =
        state.activeSession?.subtitle.trim().isNotEmpty == true
        ? state.activeSession!.subtitle.trim()
        : state.personal.defaultWorkingDirectory;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  state.activeSession?.title ?? 'Chat',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(statusText),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${state.provider.providerName} / ${state.provider.modelName}',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('chat-open-project-button'),
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Open project'),
                onPressed: onProjectDirectorySelected,
              ),
            ],
          ),
          if (workspacePath.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    workspacePath,
                    key: const ValueKey('chat-workspace-path'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (showActiveExtensions) ...[
            const SizedBox(height: 6),
            _ActiveExtensionsIndicator(activeExtensions: activeExtensions),
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 2),
            Text(
              state.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActiveExtensionsIndicator extends StatelessWidget {
  const _ActiveExtensionsIndicator({required this.activeExtensions});

  final ActiveExtensionsState activeExtensions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warningCount = activeExtensions.warnings.length;
    final warningLabel = warningCount == 1 ? '1 issue' : '$warningCount issues';
    final warningDetails = activeExtensions.warnings.join('\n');
    return Wrap(
      key: const ValueKey('active-extensions-indicator'),
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.extension_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 5),
            Text(
              'Extensions ${activeExtensions.totalCount}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (activeExtensions.hasWarnings)
          Tooltip(
            message: warningDetails,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 16,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 5),
                Text(
                  warningLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.tertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InlineStreamingStatus extends StatelessWidget {
  const _InlineStreamingStatus();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        key: const ValueKey('inline-streaming-indicator'),
        constraints: const BoxConstraints(maxWidth: 760),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.22),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text('Thinking...', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.isStreaming,
    required this.thinkingModeEnabled,
    required this.skills,
    required this.onSendMessage,
    required this.onSendRequest,
    required this.onThinkingModeChanged,
    required this.onStop,
    required this.onPickAttachments,
    required this.attachmentDropController,
  });

  final TextEditingController controller;
  final bool isStreaming;
  final bool thinkingModeEnabled;
  final List<SkillSummary> skills;
  final ValueChanged<String>? onSendMessage;
  final ChatSendRequestHandler? onSendRequest;
  final ValueChanged<bool>? onThinkingModeChanged;
  final VoidCallback? onStop;
  final ChatAttachmentPicker? onPickAttachments;
  final ChatAttachmentDropController? attachmentDropController;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  var _showSlashPalette = false;
  var _isDraggingFiles = false;
  final _attachments = <ChatAttachment>[];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleComposerChanged);
    widget.attachmentDropController?.addListener(_handleDroppedAttachments);
  }

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleComposerChanged);
      widget.controller.addListener(_handleComposerChanged);
      _handleComposerChanged();
    }
    if (oldWidget.attachmentDropController != widget.attachmentDropController) {
      oldWidget.attachmentDropController?.removeListener(
        _handleDroppedAttachments,
      );
      widget.attachmentDropController?.addListener(_handleDroppedAttachments);
      _handleDroppedAttachments();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleComposerChanged);
    widget.attachmentDropController?.removeListener(_handleDroppedAttachments);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slashCommands = _filteredSlashCommands();
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.enter): const _SendIntent(),
      const SingleActivator(LogicalKeyboardKey.numpadEnter):
          const _SendIntent(),
      const SingleActivator(LogicalKeyboardKey.enter, alt: true):
          const _InsertNewlineIntent(),
      const SingleActivator(LogicalKeyboardKey.numpadEnter, alt: true):
          const _InsertNewlineIntent(),
    };
    final composer = Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showSlashPalette && slashCommands.isNotEmpty) ...[
            _SlashCommandPalette(
              commands: slashCommands,
              onSelected: _selectSlashCommand,
            ),
            const SizedBox(height: 8),
          ],
          if (_attachments.isNotEmpty) ...[
            _AttachmentTray(
              attachments: _attachments,
              onRemoved: _removeAttachment,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Shortcuts(
                  shortcuts: shortcuts,
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _SendIntent: CallbackAction<_SendIntent>(
                        onInvoke: (_) {
                          _send();
                          return null;
                        },
                      ),
                      _InsertNewlineIntent:
                          CallbackAction<_InsertNewlineIntent>(
                            onInvoke: (_) {
                              _insertNewline();
                              return null;
                            },
                          ),
                    },
                    child: TextField(
                      key: const ValueKey('composer-input'),
                      controller: widget.controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Message $appDisplayName',
                        prefixIcon: Tooltip(
                          message: 'Attach context',
                          child: IconButton(
                            icon: const Icon(Icons.attach_file),
                            onPressed: _pickAttachments,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _ThinkingModeButton(
                enabled: widget.thinkingModeEnabled,
                onChanged: widget.onThinkingModeChanged,
              ),
              const SizedBox(width: 8),
              if (widget.isStreaming)
                Tooltip(
                  message: 'Stop',
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.stop),
                    onPressed: widget.onStop,
                  ),
                )
              else
                Tooltip(
                  message: 'Send',
                  child: IconButton.filled(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _send,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDraggingFiles = true),
      onDragExited: (_) => setState(() => _isDraggingFiles = false),
      onDragDone: _handleNativeDrop,
      child: Stack(
        children: [
          composer,
          if (_isDraggingFiles)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.45),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Text(
                          'Drop files to attach',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAttachments() async {
    final picker = widget.onPickAttachments;
    if (picker == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attachment picker is unavailable.')),
      );
      return;
    }
    final attachments = await picker();
    if (!mounted) return;
    _addAttachments(attachments);
  }

  void _handleDroppedAttachments() {
    final attachments =
        widget.attachmentDropController?.takePendingAttachments() ?? const [];
    _addAttachments(attachments);
  }

  Future<void> _handleNativeDrop(DropDoneDetails details) async {
    setState(() => _isDraggingFiles = false);
    final attachments = await chatAttachmentsFromFiles(details.files);
    if (!mounted) return;
    _addAttachments(attachments);
  }

  void _addAttachments(List<ChatAttachment> attachments) {
    if (attachments.isEmpty) return;
    setState(() {
      _attachments
        ..removeWhere((existing) {
          return attachments.any((next) => next.id == existing.id);
        })
        ..addAll(attachments);
    });
  }

  void _removeAttachment(ChatAttachment attachment) {
    setState(() {
      _attachments.removeWhere((item) => item.id == attachment.id);
    });
  }

  void _handleComposerChanged() {
    final shouldShow = _slashQuery() != null;
    if (shouldShow == _showSlashPalette) {
      if (mounted) setState(() {});
      return;
    }
    setState(() => _showSlashPalette = shouldShow);
  }

  String? _slashQuery() {
    final value = widget.controller.value;
    final text = value.text;
    final caret = value.selection.baseOffset < 0
        ? text.length
        : value.selection.baseOffset;
    if (caret > text.length) return null;
    final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    final token = text.substring(lineStart, caret);
    if (!token.startsWith('/')) return null;
    if (token.contains(RegExp(r'\s'))) return null;
    return token.substring(1).toLowerCase();
  }

  List<_SlashCommand> _filteredSlashCommands() {
    final query = _slashQuery();
    if (query == null) return const [];
    final slashCommands = _slashCommandsForSkills(widget.skills);
    if (query.isEmpty) return slashCommands;
    return [
      for (final command in slashCommands)
        if (command.command.substring(1).contains(query) ||
            command.title.toLowerCase().contains(query) ||
            command.description.toLowerCase().contains(query))
          command,
    ];
  }

  void _selectSlashCommand(_SlashCommand command) {
    final value = widget.controller.value;
    final text = value.text;
    final caret = value.selection.baseOffset < 0
        ? text.length
        : value.selection.baseOffset;
    final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    final nextText = text.replaceRange(lineStart, caret, '${command.command} ');
    widget.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(
        offset: lineStart + command.command.length + 1,
      ),
    );
    setState(() => _showSlashPalette = false);
  }

  void _send() {
    final text = widget.controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final sendText = text.isEmpty ? _defaultAttachmentPrompt() : text;
    final attachments = List<ChatAttachment>.unmodifiable(_attachments);
    final request = ChatSendRequest(text: sendText, attachments: attachments);
    if (widget.onSendRequest != null) {
      widget.onSendRequest!(request);
    } else {
      widget.onSendMessage?.call(sendText);
    }
    widget.controller.clear();
    if (_showSlashPalette || _attachments.isNotEmpty) {
      setState(() {
        _showSlashPalette = false;
        _attachments.clear();
      });
    }
  }

  String _defaultAttachmentPrompt() {
    return _attachments.length == 1
        ? 'Review the attached file.'
        : 'Review the attached files.';
  }

  void _insertNewline() {
    final value = widget.controller.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final nextText = text.replaceRange(start, end, '\n');
    widget.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }
}

class _ThinkingModeButton extends StatelessWidget {
  const _ThinkingModeButton({required this.enabled, this.onChanged});

  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final message = enabled ? 'Think mode on' : 'Think mode off';
    final icon = const Icon(Icons.psychology);
    return Tooltip(
      message: message,
      child: enabled
          ? IconButton.filledTonal(
              icon: icon,
              isSelected: enabled,
              onPressed: onChanged == null
                  ? null
                  : () => onChanged?.call(!enabled),
            )
          : IconButton(
              icon: icon,
              isSelected: enabled,
              onPressed: onChanged == null
                  ? null
                  : () => onChanged?.call(!enabled),
            ),
    );
  }
}

class _AttachmentTray extends StatelessWidget {
  const _AttachmentTray({required this.attachments, required this.onRemoved});

  final List<ChatAttachment> attachments;
  final ValueChanged<ChatAttachment> onRemoved;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final attachment in attachments)
            InputChip(
              key: ValueKey('composer-attachment-${attachment.id}'),
              avatar: Icon(_iconForAttachment(attachment), size: 18),
              label: Text(attachment.name, overflow: TextOverflow.ellipsis),
              tooltip:
                  '${attachment.name} • ${_formatAttachmentSize(attachment.sizeBytes)}',
              onDeleted: () => onRemoved(attachment),
              deleteButtonTooltipMessage: 'Remove ${attachment.name}',
            ),
        ],
      ),
    );
  }

  IconData _iconForAttachment(ChatAttachment attachment) {
    return switch (attachment.kind) {
      ChatAttachmentKind.image => Icons.image_outlined,
      ChatAttachmentKind.text => Icons.description_outlined,
      ChatAttachmentKind.file => Icons.insert_drive_file_outlined,
    };
  }

  String _formatAttachmentSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
}

List<_SlashCommand> _slashCommandsForSkills(List<SkillSummary> skills) {
  final skillCommands = <_SlashCommand>[];
  final seen = <String>{for (final command in _slashCommands) command.command};
  for (final skill in skills) {
    if (skill.status.toLowerCase() != 'enabled') continue;
    final name = _skillSlashName(skill);
    if (name.isEmpty) continue;
    final command = '/$name';
    if (!seen.add(command)) continue;
    skillCommands.add(
      _SlashCommand(
        command: command,
        title: 'Skill: ${skill.name}',
        description: skill.description,
        icon: Icons.extension_outlined,
      ),
    );
  }
  return [...skillCommands, ..._slashCommands];
}

String _skillSlashName(SkillSummary skill) {
  final rawName = skill.name.trim().isNotEmpty ? skill.name : skill.id;
  return rawName.trim().replaceAll(RegExp(r'\s+'), '-').toLowerCase();
}

class _SlashCommandPalette extends StatelessWidget {
  const _SlashCommandPalette({
    required this.commands,
    required this.onSelected,
  });

  final List<_SlashCommand> commands;
  final ValueChanged<_SlashCommand> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('slash-command-palette'),
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: commands.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            color: theme.dividerColor.withValues(alpha: 0.55),
          ),
          itemBuilder: (context, index) {
            final command = commands[index];
            return InkWell(
              onTap: () => onSelected(command),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(command.icon, size: 20),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 96,
                      child: Text(
                        command.command,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            command.title,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            command.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SlashCommand {
  const _SlashCommand({
    required this.command,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String command;
  final String title;
  final String description;
  final IconData icon;
}

const _slashCommands = [
  _SlashCommand(
    command: '/provider',
    title: 'Provider settings',
    description: 'Switch provider, model, or API key',
    icon: Icons.api_outlined,
  ),
  _SlashCommand(
    command: '/tools',
    title: 'Tool activity',
    description: 'Review current and recent tool runs',
    icon: Icons.construction_outlined,
  ),
  _SlashCommand(
    command: '/mcp',
    title: 'MCP servers',
    description: 'Manage connected MCP servers',
    icon: Icons.hub_outlined,
  ),
  _SlashCommand(
    command: '/skills',
    title: 'Skills',
    description: 'Import, enable, or disable skills',
    icon: Icons.extension_outlined,
  ),
  _SlashCommand(
    command: '/context',
    title: 'Context retrieval',
    description: 'Inspect memory and retrieval state',
    icon: Icons.account_tree_outlined,
  ),
  _SlashCommand(
    command: '/memory',
    title: 'Memory',
    description: 'Review profile, habit, and graph facts',
    icon: Icons.psychology_outlined,
  ),
  _SlashCommand(
    command: '/compact',
    title: 'Compact context',
    description: 'Ask the agent to summarize long context',
    icon: Icons.compress_outlined,
  ),
  _SlashCommand(
    command: '/help',
    title: 'Help',
    description: 'Ask for available commands',
    icon: Icons.help_outline,
  ),
];

class _SendIntent extends Intent {
  const _SendIntent();
}

class _InsertNewlineIntent extends Intent {
  const _InsertNewlineIntent();
}
