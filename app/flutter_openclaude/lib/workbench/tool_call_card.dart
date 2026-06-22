import 'package:flutter/material.dart';

import 'workbench_models.dart';

class ToolCallCard extends StatefulWidget {
  const ToolCallCard({super.key, required this.toolRun, this.onSelected});

  final ToolRun toolRun;
  final VoidCallback? onSelected;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusLabel(widget.toolRun.status);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onSelected,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_statusIcon(widget.toolRun.status), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.toolRun.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(label: status, status: widget.toolRun.status),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Expand tool details',
                    child: IconButton(
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(widget.toolRun.summary),
              const SizedBox(height: 6),
              Text(
                '${widget.toolRun.command} • ${widget.toolRun.elapsedLabel}',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                SelectableText(widget.toolRun.details),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(ToolRunStatus status) {
    return switch (status) {
      ToolRunStatus.pending => 'Pending',
      ToolRunStatus.running => 'Running',
      ToolRunStatus.success => 'Success',
      ToolRunStatus.error => 'Error',
    };
  }

  IconData _statusIcon(ToolRunStatus status) {
    return switch (status) {
      ToolRunStatus.pending => Icons.schedule,
      ToolRunStatus.running => Icons.sync,
      ToolRunStatus.success => Icons.check_circle_outline,
      ToolRunStatus.error => Icons.error_outline,
    };
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.status});

  final String label;
  final ToolRunStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ToolRunStatus.pending => Colors.amber,
      ToolRunStatus.running => Colors.blue,
      ToolRunStatus.success => Colors.green,
      ToolRunStatus.error => Colors.red,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}
