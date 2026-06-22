import 'package:flutter/material.dart';

import 'tool_call_card.dart';
import 'workbench_models.dart';

class ToolsPanel extends StatelessWidget {
  const ToolsPanel({super.key, required this.state, this.onToolSelected});

  final WorkbenchState state;
  final ValueChanged<String>? onToolSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('tools-panel'),
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tools', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          '${state.toolRuns.length} runs in this session',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _ToolSummaryPill(
                    label: 'Pending',
                    count: _countByStatus(ToolRunStatus.pending),
                  ),
                  const SizedBox(width: 8),
                  _ToolSummaryPill(
                    label: 'Errors',
                    count: _countByStatus(ToolRunStatus.error),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: state.toolRuns.isEmpty
                  ? const _EmptyToolsState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: state.toolRuns.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final toolRun = state.toolRuns[index];
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: ToolCallCard(
                            toolRun: toolRun,
                            onSelected: () => onToolSelected?.call(toolRun.id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  int _countByStatus(ToolRunStatus status) {
    return state.toolRuns.where((toolRun) => toolRun.status == status).length;
  }
}

class _ToolSummaryPill extends StatelessWidget {
  const _ToolSummaryPill({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label $count', style: theme.textTheme.labelMedium),
    );
  }
}

class _EmptyToolsState extends StatelessWidget {
  const _EmptyToolsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.handyman_outlined,
            size: 34,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 10),
          Text('No tool runs yet', style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}
