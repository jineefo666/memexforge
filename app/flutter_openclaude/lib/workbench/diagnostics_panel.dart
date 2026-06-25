import 'package:flutter/material.dart';

import 'workbench_models.dart';

class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({
    super.key,
    required this.state,
    this.onBridgeReconnect,
    this.onBridgeStart,
    this.onBridgeSwitchPort,
    this.onCopyReport,
  });

  final WorkbenchState state;
  final VoidCallback? onBridgeReconnect;
  final VoidCallback? onBridgeStart;
  final VoidCallback? onBridgeSwitchPort;
  final VoidCallback? onCopyReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final workspacePath =
        state.activeSession?.subtitle.trim().isNotEmpty == true
        ? state.activeSession!.subtitle.trim()
        : state.personal.defaultWorkingDirectory;
    return ColoredBox(
      key: const ValueKey('diagnostics-panel'),
      color: colorScheme.surface,
      child: SafeArea(
        child: ListView(
          key: const ValueKey('diagnostics-scroll'),
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text('Diagnostics', style: theme.textTheme.titleLarge),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('diagnostics-start-button'),
                  onPressed: onBridgeStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start bridge'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('diagnostics-switch-port-button'),
                  onPressed: onBridgeSwitchPort,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Switch port'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('diagnostics-copy-button'),
                  onPressed: onCopyReport,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy report'),
                ),
                FilledButton.icon(
                  key: const ValueKey('diagnostics-reconnect-button'),
                  onPressed: onBridgeReconnect,
                  icon: const Icon(Icons.sync),
                  label: const Text('Reconnect bridge'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (state.diagnosticsReportCopyStatus !=
                DiagnosticsReportCopyStatus.idle) ...[
              _ReportCopyStatus(status: state.diagnosticsReportCopyStatus),
              const SizedBox(height: 16),
            ],
            Text('Setup checklist', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _ChecklistGrid(
              items: [
                _ChecklistItem(
                  title: 'Bridge',
                  detail: 'Managed internally',
                  complete:
                      state.connectionStatus == ConnectionStatus.connected,
                  status: _connectionStatusLabel(state.connectionStatus),
                ),
                _ChecklistItem(
                  title: 'Launcher',
                  detail: 'Desktop app-bridge process',
                  complete:
                      state.bridgeLaunchStatus == BridgeLaunchStatus.started,
                  status: _bridgeLaunchStatusLabel(state.bridgeLaunchStatus),
                ),
                _ChecklistItem(
                  title: 'Provider',
                  detail: state.provider.modelName,
                  complete: state.provider.modelName.trim().isNotEmpty,
                  status: state.provider.providerName,
                ),
                _ChecklistItem(
                  title: 'API key',
                  detail: state.provider.apiKeyConfigured
                      ? 'Configured'
                      : 'Not configured',
                  complete: state.provider.apiKeyConfigured,
                  status: state.provider.apiKeyConfigured
                      ? 'Ready'
                      : 'Needs setup',
                ),
                _ChecklistItem(
                  title: 'Workspace',
                  detail: workspacePath,
                  complete: workspacePath.trim().isNotEmpty,
                  status: 'Project scope',
                ),
                _ChecklistItem(
                  title: 'Agent eval trace',
                  detail: state.personal.agentEvalTraceEnabled
                      ? 'Recording real turns'
                      : 'Disabled',
                  complete: state.personal.agentEvalTraceEnabled,
                  status: state.personal.agentEvalTraceEnabled
                      ? 'Enabled'
                      : 'Opt-in',
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Turn timeline', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (state.turnTimeline.isEmpty)
              const _EmptyTimeline()
            else
              for (final entry in state.turnTimeline)
                _TimelineTile(entry: entry),
            const SizedBox(height: 24),
            Text('Event log', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (state.diagnosticLogs.isEmpty)
              const _EmptyLog()
            else
              for (final entry in state.diagnosticLogs)
                _DiagnosticLogTile(entry: entry),
          ],
        ),
      ),
    );
  }
}

class _ReportCopyStatus extends StatelessWidget {
  const _ReportCopyStatus({required this.status});

  final DiagnosticsReportCopyStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final failed = status == DiagnosticsReportCopyStatus.failed;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: failed
            ? colorScheme.errorContainer.withValues(alpha: 0.35)
            : colorScheme.primaryContainer.withValues(alpha: 0.35),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed ? Icons.error_outline : Icons.check_circle_outline,
              color: failed ? colorScheme.error : colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(failed ? 'Report copy failed' : 'Report copied'),
          ],
        ),
      ),
    );
  }
}

class _ChecklistGrid extends StatelessWidget {
  const _ChecklistGrid({required this.items});

  final List<_ChecklistItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: columns == 2 ? 4.8 : 5.6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final item in items) _ChecklistTile(item: item)],
        );
      },
    );
  }
}

class _ChecklistItem {
  const _ChecklistItem({
    required this.title,
    required this.detail,
    required this.complete,
    required this.status,
  });

  final String title;
  final String detail;
  final bool complete;
  final String status;
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({required this.item});

  final _ChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = item.complete
        ? colorScheme.primary.withValues(alpha: 0.42)
        : colorScheme.outlineVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
        color: item.complete
            ? colorScheme.primaryContainer.withValues(alpha: 0.28)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              item.complete ? Icons.check_circle_outline : Icons.error_outline,
              color: item.complete ? colorScheme.primary : colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(item.status, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.entry});

  final TurnTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _timelineStatusColor(colorScheme, entry.status);
    final detail = entry.detail ?? '';
    return Padding(
      key: ValueKey('diagnostics-timeline-${entry.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_timelineStatusIcon(entry.status), color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          entry.stageLabel,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        _TimelineBadge(label: entry.status, color: statusColor),
                        if (entry.durationLabel.isNotEmpty)
                          _TimelineBadge(
                            label: entry.durationLabel,
                            color: colorScheme.primary,
                          ),
                      ],
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (entry.toolName != null &&
                        entry.toolName!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Tool: ${entry.toolName}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineBadge extends StatelessWidget {
  const _TimelineBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _DiagnosticLogTile extends StatelessWidget {
  const _DiagnosticLogTile({required this.entry});

  final DiagnosticLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: ListTile(
          leading: Icon(
            _iconForSeverity(entry.severity),
            color: _colorForSeverity(colorScheme, entry.severity),
          ),
          title: Text(entry.title),
          subtitle: Text(entry.detail),
          trailing: Text(entry.timestampLabel),
        ),
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Text('No turn timeline yet'),
      ),
    );
  }
}

class _EmptyLog extends StatelessWidget {
  const _EmptyLog();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Text('No diagnostic events yet'),
      ),
    );
  }
}

String _bridgeLaunchStatusLabel(BridgeLaunchStatus status) {
  return switch (status) {
    BridgeLaunchStatus.idle => 'Idle',
    BridgeLaunchStatus.starting => 'Starting',
    BridgeLaunchStatus.started => 'Started',
    BridgeLaunchStatus.unsupported => 'Unsupported',
    BridgeLaunchStatus.failed => 'Failed',
  };
}

String _connectionStatusLabel(ConnectionStatus status) {
  return switch (status) {
    ConnectionStatus.connected => 'Connected',
    ConnectionStatus.connecting => 'Connecting',
    ConnectionStatus.disconnected => 'Disconnected',
    ConnectionStatus.error => 'Error',
  };
}

IconData _iconForSeverity(DiagnosticSeverity severity) {
  return switch (severity) {
    DiagnosticSeverity.info => Icons.info_outline,
    DiagnosticSeverity.success => Icons.check_circle_outline,
    DiagnosticSeverity.warning => Icons.warning_amber_outlined,
    DiagnosticSeverity.error => Icons.error_outline,
  };
}

Color _colorForSeverity(ColorScheme colorScheme, DiagnosticSeverity severity) {
  return switch (severity) {
    DiagnosticSeverity.info => colorScheme.primary,
    DiagnosticSeverity.success => colorScheme.tertiary,
    DiagnosticSeverity.warning => colorScheme.secondary,
    DiagnosticSeverity.error => colorScheme.error,
  };
}

IconData _timelineStatusIcon(String status) {
  return switch (status) {
    'completed' => Icons.check_circle_outline,
    'failed' => Icons.error_outline,
    'skipped' => Icons.remove_circle_outline,
    _ => Icons.more_horiz,
  };
}

Color _timelineStatusColor(ColorScheme colorScheme, String status) {
  return switch (status) {
    'completed' => colorScheme.tertiary,
    'failed' => colorScheme.error,
    'skipped' => colorScheme.secondary,
    _ => colorScheme.primary,
  };
}
