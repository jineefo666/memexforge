import 'package:flutter/material.dart';

import 'marketplace_panel.dart';
import 'mcp_panel.dart';
import 'skills_panel.dart';
import 'workbench_models.dart';

class ExtensionsPanel extends StatelessWidget {
  const ExtensionsPanel({
    super.key,
    required this.state,
    this.onRefresh,
    this.onSkillImported,
    this.onSkillEnabledChanged,
    this.onSkillsRefresh,
    this.onMcpServerSaved,
    this.onMcpServerTested,
    this.onMcpServerEnabledChanged,
    this.onMcpServerDeleted,
  });

  final WorkbenchState state;
  final VoidCallback? onRefresh;
  final ValueChanged<String>? onSkillImported;
  final void Function(String skillId, bool enabled)? onSkillEnabledChanged;
  final VoidCallback? onSkillsRefresh;
  final ValueChanged<McpServerDraft>? onMcpServerSaved;
  final ValueChanged<McpServerDraft>? onMcpServerTested;
  final void Function(String serverId, bool enabled)? onMcpServerEnabledChanged;
  final ValueChanged<String>? onMcpServerDeleted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: ColoredBox(
        key: const ValueKey('extensions-panel'),
        color: colorScheme.surface,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 18, 10),
                child: Row(
                  children: [
                    Text(
                      'Extensions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    Tooltip(
                      message: 'Refresh',
                      child: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: onRefresh,
                      ),
                    ),
                  ],
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Skills'),
                  Tab(text: 'MCP'),
                  Tab(text: 'Marketplace'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    SkillsPanel(
                      state: state.extensions,
                      onSkillImported: onSkillImported,
                      onSkillEnabledChanged: onSkillEnabledChanged,
                      onRefresh: onSkillsRefresh,
                    ),
                    McpPanel(
                      state: state.extensions,
                      onServerSaved: onMcpServerSaved,
                      onServerTested: onMcpServerTested,
                      onServerEnabledChanged: onMcpServerEnabledChanged,
                      onServerDeleted: onMcpServerDeleted,
                    ),
                    MarketplacePanel(
                      state: state.extensions,
                      onSkillImported: onSkillImported,
                      onMcpServerSaved: onMcpServerSaved,
                    ),
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
