import 'package:flutter/material.dart';

import 'workbench_models.dart';

class ActivityRail extends StatelessWidget {
  const ActivityRail({
    super.key,
    required this.destination,
    this.onDestinationChanged,
  });

  final WorkbenchDestination destination;
  final ValueChanged<WorkbenchDestination>? onDestinationChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('activity-rail'),
      width: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            const Icon(Icons.terminal, size: 24),
            const SizedBox(height: 18),
            _RailButton(
              icon: Icons.chat_bubble_outline,
              label: 'Chat',
              selected: destination == WorkbenchDestination.chat,
              onPressed: () =>
                  onDestinationChanged?.call(WorkbenchDestination.chat),
            ),
            _RailButton(
              icon: Icons.account_tree_outlined,
              label: 'Context',
              selected: destination == WorkbenchDestination.context,
              onPressed: () =>
                  onDestinationChanged?.call(WorkbenchDestination.context),
            ),
            _RailButton(
              icon: Icons.handyman_outlined,
              label: 'Tools',
              selected: destination == WorkbenchDestination.tools,
              onPressed: () =>
                  onDestinationChanged?.call(WorkbenchDestination.tools),
            ),
            _RailButton(
              icon: Icons.extension_outlined,
              label: 'Extensions',
              selected: destination == WorkbenchDestination.extensions,
              onPressed: () =>
                  onDestinationChanged?.call(WorkbenchDestination.extensions),
            ),
            _RailButton(
              icon: Icons.monitor_heart_outlined,
              label: 'Diagnostics',
              selected: destination == WorkbenchDestination.diagnostics,
              onPressed: () =>
                  onDestinationChanged?.call(WorkbenchDestination.diagnostics),
            ),
            _RailButton(
              icon: Icons.hub_outlined,
              label: 'Providers',
              selected: destination == WorkbenchDestination.providers,
              onPressed: () =>
                  onDestinationChanged?.call(WorkbenchDestination.providers),
            ),
            const Spacer(),
            _RailButton(
              icon: Icons.settings_outlined,
              label: 'Settings',
              selected: destination == WorkbenchDestination.settings,
              onPressed: () =>
                  onDestinationChanged?.call(WorkbenchDestination.settings),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Tooltip(
        message: label,
        child: IconButton(
          isSelected: selected,
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          selectedIcon: Icon(icon),
          icon: Icon(icon),
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: selected ? colorScheme.primaryContainer : null,
          ),
        ),
      ),
    );
  }
}
