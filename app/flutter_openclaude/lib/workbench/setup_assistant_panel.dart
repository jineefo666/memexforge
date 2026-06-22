import 'package:flutter/material.dart';

import 'workbench_models.dart';

class SetupAssistantPanel extends StatelessWidget {
  const SetupAssistantPanel({
    super.key,
    required this.state,
    this.onStartBridge,
    this.onReconnectBridge,
    this.onOpenProviderSettings,
    this.onOpenDiagnostics,
    this.onDismiss,
  });

  final WorkbenchState state;
  final VoidCallback? onStartBridge;
  final VoidCallback? onReconnectBridge;
  final VoidCallback? onOpenProviderSettings;
  final VoidCallback? onOpenDiagnostics;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      key: const ValueKey('setup-assistant-panel'),
      color: colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.rocket_launch_outlined,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Setup assistant',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Tooltip(
                    message: 'Dismiss setup assistant',
                    child: IconButton(
                      key: const ValueKey('setup-dismiss-button'),
                      icon: const Icon(Icons.close),
                      onPressed: onDismiss,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusChip(
                    label: state.connectionStatus == ConnectionStatus.connected
                        ? 'Bridge connected'
                        : 'Bridge disconnected',
                    icon: state.connectionStatus == ConnectionStatus.connected
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    complete:
                        state.connectionStatus == ConnectionStatus.connected,
                  ),
                  _StatusChip(
                    label: state.provider.apiKeyConfigured
                        ? 'API key configured'
                        : 'API key missing',
                    icon: state.provider.apiKeyConfigured
                        ? Icons.check_circle_outline
                        : Icons.key_off_outlined,
                    complete: state.provider.apiKeyConfigured,
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('setup-start-bridge-button'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start bridge'),
                    onPressed: onStartBridge,
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('setup-reconnect-button'),
                    icon: const Icon(Icons.sync),
                    label: const Text('Reconnect'),
                    onPressed: onReconnectBridge,
                  ),
                  FilledButton.icon(
                    key: const ValueKey('setup-provider-button'),
                    icon: const Icon(Icons.hub_outlined),
                    label: const Text('Provider settings'),
                    onPressed: onOpenProviderSettings,
                  ),
                  TextButton.icon(
                    key: const ValueKey('setup-diagnostics-button'),
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: const Text('Diagnostics'),
                    onPressed: onOpenDiagnostics,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.icon,
    required this.complete,
  });

  final String label;
  final IconData icon;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = complete ? colorScheme.primary : colorScheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.32)),
        color: color.withValues(alpha: 0.08),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
