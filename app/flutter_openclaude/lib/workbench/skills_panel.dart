import 'package:flutter/material.dart';

import 'workbench_models.dart';

class SkillsPanel extends StatefulWidget {
  const SkillsPanel({
    super.key,
    required this.state,
    this.onSkillImported,
    this.onSkillEnabledChanged,
    this.onRefresh,
  });

  final ExtensionsState state;
  final ValueChanged<String>? onSkillImported;
  final void Function(String skillId, bool enabled)? onSkillEnabledChanged;
  final VoidCallback? onRefresh;

  @override
  State<SkillsPanel> createState() => _SkillsPanelState();
}

class _SkillsPanelState extends State<SkillsPanel> {
  late final TextEditingController _importPathController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _importPathController = TextEditingController();
  }

  @override
  void dispose() {
    _importPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skills = _filteredSkills();
    return Padding(
      key: const ValueKey('extensions-skills-panel'),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('skill-import-path-input'),
                  controller: _importPathController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.folder_open_outlined),
                    labelText: 'Import skill directory',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _importSkill(),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Import skill',
                child: IconButton.filled(
                  key: const ValueKey('skill-import-button'),
                  icon: const Icon(Icons.add),
                  onPressed: _importSkill,
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Refresh skills',
                child: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: widget.onRefresh,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('extensions-skills-search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search skills',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildBody(context, skills)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<SkillSummary> skills) {
    return switch (widget.state.skillsStatus) {
      ExtensionInventoryStatus.loading => const _PanelStateMessage(
        icon: Icons.sync,
        title: 'Loading skills',
      ),
      ExtensionInventoryStatus.failed => _PanelStateMessage(
        icon: Icons.error_outline,
        title: 'Skills unavailable',
        detail: widget.state.skillsErrorMessage,
      ),
      _ when skills.isEmpty => const _PanelStateMessage(
        icon: Icons.extension_off_outlined,
        title: 'No skills found',
      ),
      _ => _SkillInventory(
        skills: skills,
        onSkillEnabledChanged: widget.onSkillEnabledChanged,
      ),
    };
  }

  void _importSkill() {
    final path = _importPathController.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a skill directory path first.')),
      );
      return;
    }
    widget.onSkillImported?.call(path);
  }

  List<SkillSummary> _filteredSkills() {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.state.skills;
    return [
      for (final skill in widget.state.skills)
        if (skill.name.toLowerCase().contains(query) ||
            skill.description.toLowerCase().contains(query) ||
            skill.source.toLowerCase().contains(query))
          skill,
    ];
  }
}

class _SkillInventory extends StatefulWidget {
  const _SkillInventory({required this.skills, this.onSkillEnabledChanged});

  final List<SkillSummary> skills;
  final void Function(String skillId, bool enabled)? onSkillEnabledChanged;

  @override
  State<_SkillInventory> createState() => _SkillInventoryState();
}

class _SkillInventoryState extends State<_SkillInventory> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedSkill();
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: ListView.separated(
            itemCount: widget.skills.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final skill = widget.skills[index];
              final selected =
                  skill.id == (_selectedId ?? widget.skills.first.id);
              return _SkillRow(
                skill: skill,
                selected: selected,
                onTap: () => setState(() => _selectedId = skill.id),
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: _SkillDetail(
            skill: selected,
            onSkillEnabledChanged: widget.onSkillEnabledChanged,
          ),
        ),
      ],
    );
  }

  SkillSummary _selectedSkill() {
    final selectedId = _selectedId;
    if (selectedId != null) {
      for (final skill in widget.skills) {
        if (skill.id == selectedId) return skill;
      }
    }
    return widget.skills.first;
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({
    required this.skill,
    required this.selected,
    required this.onTap,
  });

  final SkillSummary skill;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.secondaryContainer : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        title: Text(skill.name),
        subtitle: Text(
          skill.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        leading: const Icon(Icons.psychology_alt_outlined),
        trailing: _SourceChip(label: skill.source),
        onTap: onTap,
      ),
    );
  }
}

class _SkillDetail extends StatelessWidget {
  const _SkillDetail({required this.skill, this.onSkillEnabledChanged});

  final SkillSummary skill;
  final void Function(String skillId, bool enabled)? onSkillEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(skill.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _DetailIconButton(
                  tooltip: skill.status == 'disabled'
                      ? 'Enable skill'
                      : 'Disable skill',
                  icon: skill.status == 'disabled'
                      ? Icons.play_arrow_outlined
                      : Icons.power_settings_new,
                  onPressed: skill.status == 'unavailable'
                      ? null
                      : () => onSkillEnabledChanged?.call(
                          skill.id,
                          skill.status == 'disabled',
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(skill.description),
            const SizedBox(height: 16),
            _DetailRow(label: 'Source', value: skill.source),
            _DetailRow(label: 'Status', value: skill.status),
            if (skill.path != null)
              _DetailRow(label: 'Path', value: skill.path!),
            if (skill.unavailableReason != null)
              _DetailRow(label: 'Issue', value: skill.unavailableReason!),
          ],
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _DetailIconButton extends StatelessWidget {
  const _DetailIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        visualDensity: VisualDensity.compact,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}

class _PanelStateMessage extends StatelessWidget {
  const _PanelStateMessage({
    required this.icon,
    required this.title,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
