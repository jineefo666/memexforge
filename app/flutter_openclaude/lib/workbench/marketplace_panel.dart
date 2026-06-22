import 'package:flutter/material.dart';

import 'workbench_models.dart';

class MarketplacePanel extends StatefulWidget {
  const MarketplacePanel({
    super.key,
    required this.state,
    this.onSkillImported,
    this.onMcpServerSaved,
  });

  final ExtensionsState state;
  final ValueChanged<String>? onSkillImported;
  final ValueChanged<McpServerDraft>? onMcpServerSaved;

  @override
  State<MarketplacePanel> createState() => _MarketplacePanelState();
}

class _MarketplacePanelState extends State<MarketplacePanel> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems();
    return ListView(
      key: const ValueKey('marketplace-panel'),
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          key: const ValueKey('marketplace-search-input'),
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: 'Search marketplace',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _CategoryChip(label: 'Skills'),
            _CategoryChip(label: 'MCP'),
            _CategoryChip(label: 'Local'),
          ],
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          const _EmptyMarketplace()
        else
          for (final item in items)
            _MarketplaceTile(
              item: item,
              onAction: () => _runMarketplaceAction(item),
            ),
      ],
    );
  }

  List<MarketplaceExtension> _filteredItems() {
    final query = _searchController.text.trim().toLowerCase();
    final items = _marketplaceItems(widget.state);
    if (query.isEmpty) return items;
    return [
      for (final item in items)
        if (item.name.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query) ||
            item.category.toLowerCase().contains(query) ||
            item.source.toLowerCase().contains(query))
          item,
    ];
  }

  void _runMarketplaceAction(MarketplaceExtension item) {
    if (item.installed) return;
    if (item.id == 'curated:workspace-memory') {
      widget.onSkillImported?.call('skills/workspace-memory');
      return;
    }
    if (item.id == 'curated:filesystem-mcp') {
      widget.onMcpServerSaved?.call(
        const McpServerDraft(
          name: 'filesystem-mcp',
          transport: 'stdio',
          scope: 'project',
          command: 'npx',
          args: ['--yes', '@modelcontextprotocol/server-filesystem'],
          enabled: true,
        ),
      );
    }
  }
}

class _MarketplaceTile extends StatelessWidget {
  const _MarketplaceTile({required this.item, required this.onAction});

  final MarketplaceExtension item;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconForCategory(item.category), color: colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _StatusChip(label: item.category),
                        if (item.installed) ...[
                          const SizedBox(width: 6),
                          const _StatusChip(label: 'Installed'),
                        ],
                        if (item.enabled) ...[
                          const SizedBox(width: 6),
                          const _StatusChip(label: 'Enabled'),
                        ],
                        if (!item.installed) ...[
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            key: ValueKey(_actionKeyFor(item)),
                            onPressed: onAction,
                            icon: Icon(_actionIconFor(item.category)),
                            label: Text(
                              item.category == 'MCP'
                                  ? 'Use template'
                                  : 'Install',
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(item.description),
                    const SizedBox(height: 8),
                    Text(item.source, style: theme.textTheme.bodySmall),
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

String _actionKeyFor(MarketplaceExtension item) {
  return 'marketplace-action-${item.id.replaceAll(':', '-')}';
}

IconData _actionIconFor(String category) {
  return category == 'MCP' ? Icons.add_circle_outline : Icons.download_outlined;
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(_iconForCategory(label), size: 16),
      label: Text(label),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surfaceContainerHighest,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _EmptyMarketplace extends StatelessWidget {
  const _EmptyMarketplace();

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
        child: Text('No marketplace items match'),
      ),
    );
  }
}

List<MarketplaceExtension> _marketplaceItems(ExtensionsState state) {
  return [
    for (final skill in state.skills)
      MarketplaceExtension(
        id: 'skill:${skill.id}',
        name: skill.name,
        description: skill.description.isEmpty
            ? 'Local skill package'
            : skill.description,
        category: 'Skill',
        source: skill.path ?? skill.source,
        installed: true,
        enabled: skill.status == 'enabled',
      ),
    for (final server in state.mcpServers)
      MarketplaceExtension(
        id: 'mcp:${server.id}',
        name: server.name,
        description:
            'MCP server with ${server.toolCount} tools and ${server.skillCount} skills.',
        category: 'MCP',
        source: '${server.scope} · ${server.transport}',
        installed: true,
        enabled: server.enabled,
      ),
    const MarketplaceExtension(
      id: 'curated:workspace-memory',
      name: 'workspace-memory',
      description:
          'Profile, habit, and graph memory bundle for Agent Workbench.',
      category: 'Skill',
      source: 'Curated',
      installed: false,
      enabled: false,
    ),
    const MarketplaceExtension(
      id: 'curated:filesystem-mcp',
      name: 'filesystem-mcp',
      description: 'Filesystem MCP template for local project tools.',
      category: 'MCP',
      source: 'Curated',
      installed: false,
      enabled: false,
    ),
  ];
}

IconData _iconForCategory(String category) {
  return switch (category) {
    'MCP' => Icons.hub_outlined,
    'Local' => Icons.folder_outlined,
    _ => Icons.extension_outlined,
  };
}
