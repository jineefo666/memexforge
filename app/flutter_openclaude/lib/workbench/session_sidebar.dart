import 'package:flutter/material.dart';

import 'app_branding.dart';
import 'workbench_models.dart';

class SessionSidebar extends StatefulWidget {
  const SessionSidebar({
    super.key,
    required this.state,
    this.onSessionSelected,
    this.onSearchChanged,
    this.onNewSession,
    this.onSessionDeleted,
    this.onProjectDirectorySelected,
  });

  final WorkbenchState state;
  final ValueChanged<String>? onSessionSelected;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onNewSession;
  final ValueChanged<String>? onSessionDeleted;
  final VoidCallback? onProjectDirectorySelected;

  @override
  State<SessionSidebar> createState() => _SessionSidebarState();
}

class _SessionSidebarState extends State<SessionSidebar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.state.sessionSearchQuery,
    );
  }

  @override
  void didUpdateWidget(covariant SessionSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.sessionSearchQuery != _searchController.text) {
      _searchController.text = widget.state.sessionSearchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = widget.state.filteredSessions;
    return Container(
      key: const ValueKey('session-sidebar'),
      width: 280,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.terminal, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      appDisplayName,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Tooltip(
                    message: 'New session',
                    child: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: widget.onNewSession,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ConnectionChip(status: widget.state.connectionStatus),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('open-project-button'),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Open project'),
                  onPressed: widget.onProjectDirectorySelected,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('session-search'),
                controller: _searchController,
                onChanged: widget.onSearchChanged,
                decoration: const InputDecoration(
                  labelText: 'Search sessions',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 16),
              Text('Sessions', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Expanded(
                child: sessions.isEmpty
                    ? Center(
                        child: Text(
                          'No matching sessions',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : ListView.separated(
                        itemCount: sessions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          return _SessionTile(
                            session: session,
                            selected:
                                session.id == widget.state.activeSessionId,
                            onTap: () =>
                                widget.onSessionSelected?.call(session.id),
                            onDelete: () =>
                                widget.onSessionDeleted?.call(session.id),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Text('Provider', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              _ProviderSummary(provider: widget.state.provider),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ConnectionStatus.connected => ('Connected', Colors.green),
      ConnectionStatus.connecting => ('Connecting', Colors.amber),
      ConnectionStatus.error => ('Connection error', Colors.red),
      ConnectionStatus.disconnected => ('Disconnected', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: color, size: 9),
          const SizedBox(width: 6),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final SessionSummary session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusDot(status: session.status),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Delete session',
                    child: SizedBox.square(
                      dimension: 32,
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        onPressed: onDelete,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                session.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(session.updatedLabel, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SessionStatus.running => Colors.blue,
      SessionStatus.waitingForPermission => Colors.amber,
      SessionStatus.failed => Colors.red,
      SessionStatus.idle => Colors.green,
    };
    return Icon(Icons.circle, color: color, size: 9);
  }
}

class _ProviderSummary extends StatelessWidget {
  const _ProviderSummary({required this.provider});

  final ProviderSettings provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(provider.providerName, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(provider.modelName, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
