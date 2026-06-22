import 'package:flutter/material.dart';

import 'workbench_models.dart';

class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.state});

  final WorkbenchState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasRetrievedContext = state.retrievedContextItems.isNotEmpty;
    final hasVisibleMemoryFacts = state.memoryFacts.any(
      (item) => !item.disabled,
    );
    final showContextSection = hasRetrievedContext || hasVisibleMemoryFacts;
    final showSelectionDetails = state.inspector.kind != InspectorKind.context;
    return Container(
      key: const ValueKey('inspector-panel'),
      width: 360,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Inspector', style: theme.textTheme.titleMedium),
            if (showSelectionDetails) ...[
              const SizedBox(height: 16),
              _SelectionDetails(state: state),
            ],
            if (showContextSection) ...[
              const SizedBox(height: 20),
              Text('Context', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
            ],
            if (hasRetrievedContext) ...[
              _RetrievedContextList(items: state.retrievedContextItems),
              const SizedBox(height: 8),
            ],
            if (hasVisibleMemoryFacts) ...[
              _MemoryFactList(items: state.memoryFacts),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 20),
            Text('Provider', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '${state.provider.providerName} / ${state.provider.modelName}',
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionDetails extends StatelessWidget {
  const _SelectionDetails({required this.state});

  final WorkbenchState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = state.inspector;
    final title = switch (selection.kind) {
      InspectorKind.message => 'Selected message',
      InspectorKind.tool => 'Selected tool',
      InspectorKind.permission => 'Permission request',
      InspectorKind.settings => 'Settings',
      InspectorKind.context => 'Context overview',
      InspectorKind.overview => 'Overview',
    };
    final body = _bodyForSelection(state);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(body),
        ],
      ),
    );
  }

  String _bodyForSelection(WorkbenchState state) {
    final selection = state.inspector;
    return switch (selection.kind) {
      InspectorKind.message =>
        _messageById(state, selection.itemId)?.content ??
            'No message selected.',
      InspectorKind.tool =>
        _toolById(state, selection.itemId)?.details ?? 'No tool selected.',
      InspectorKind.permission =>
        _permissionById(state, selection.itemId)?.riskSummary ??
            'No permission request selected.',
      InspectorKind.settings => 'Provider and personal settings are editable.',
      InspectorKind.context => 'Context used by the current turn.',
      InspectorKind.overview => 'Select a message, tool, or permission.',
    };
  }

  ChatMessage? _messageById(WorkbenchState state, String? id) {
    for (final message in state.messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  ToolRun? _toolById(WorkbenchState state, String? id) {
    for (final tool in state.toolRuns) {
      if (tool.id == id) return tool;
    }
    return null;
  }

  PermissionRequest? _permissionById(WorkbenchState state, String? id) {
    for (final request in state.permissionRequests) {
      if (request.id == id) return request;
    }
    return null;
  }
}

class _RetrievedContextList extends StatelessWidget {
  const _RetrievedContextList({required this.items});

  final List<RetrievedContextItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Retrieved context', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final item in items) ...[
            Text(item.title, style: theme.textTheme.labelMedium),
            const SizedBox(height: 2),
            Text(
              item.source,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(item.content, style: theme.textTheme.bodySmall),
            if (item != items.last) const Divider(height: 16),
          ],
        ],
      ),
    );
  }
}

class _MemoryFactList extends StatelessWidget {
  const _MemoryFactList({required this.items});

  final List<MemoryFact> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleItems = [
      for (final item in items)
        if (!item.disabled) item,
    ];
    if (visibleItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Memory and profile', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final item in visibleItems) ...[
            Text(item.title, style: theme.textTheme.labelMedium),
            const SizedBox(height: 2),
            Text(
              item.sourceLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(item.content, style: theme.textTheme.bodySmall),
            if (item != visibleItems.last) const Divider(height: 16),
          ],
        ],
      ),
    );
  }
}
