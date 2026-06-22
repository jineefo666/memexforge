import 'package:flutter/material.dart';

import 'workbench_models.dart';

class PersonalSettingsPanel extends StatefulWidget {
  const PersonalSettingsPanel({
    super.key,
    required this.settings,
    this.onChanged,
    this.onClearCache,
  });

  final PersonalSettings settings;
  final ValueChanged<PersonalSettings>? onChanged;
  final VoidCallback? onClearCache;

  @override
  State<PersonalSettingsPanel> createState() => _PersonalSettingsPanelState();
}

class _PersonalSettingsPanelState extends State<PersonalSettingsPanel> {
  late final TextEditingController _displayNameController;
  late ThemePreference _themePreference;
  late double _fontScale;
  late bool _autoConnect;
  late bool _agentEvalTraceEnabled;
  late bool _fullRecentTranscriptContext;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.settings.displayName,
    );
    _themePreference = widget.settings.themePreference;
    _fontScale = widget.settings.fontScale;
    _autoConnect = widget.settings.autoConnectBridge;
    _agentEvalTraceEnabled = widget.settings.agentEvalTraceEnabled;
    _fullRecentTranscriptContext = widget.settings.fullRecentTranscriptContext;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Personal settings', style: theme.textTheme.titleLarge),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('display-name-field'),
          controller: _displayNameController,
          decoration: const InputDecoration(labelText: 'Display name'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            _emit(widget.settings.copyWith(displayName: value.trim()));
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<ThemePreference>(
          initialValue: _themePreference,
          decoration: const InputDecoration(labelText: 'Theme'),
          items: const [
            DropdownMenuItem(
              value: ThemePreference.system,
              child: Text('System'),
            ),
            DropdownMenuItem(
              value: ThemePreference.light,
              child: Text('Light'),
            ),
            DropdownMenuItem(value: ThemePreference.dark, child: Text('Dark')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _themePreference = value);
            _emit(widget.settings.copyWith(themePreference: value));
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<double>(
          initialValue: _fontScale,
          decoration: const InputDecoration(labelText: 'Font size'),
          items: const [
            DropdownMenuItem(value: 0.9, child: Text('Compact')),
            DropdownMenuItem(value: 1, child: Text('Default')),
            DropdownMenuItem(value: 1.1, child: Text('Comfortable')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _fontScale = value);
            _emit(widget.settings.copyWith(fontScale: value));
          },
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-connect app bridge'),
          value: _autoConnect,
          onChanged: (value) {
            setState(() => _autoConnect = value);
            _emit(widget.settings.copyWith(autoConnectBridge: value));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Full recent conversation context'),
          subtitle: const Text('Higher recall, higher token usage'),
          value: _fullRecentTranscriptContext,
          onChanged: (value) {
            setState(() => _fullRecentTranscriptContext = value);
            _emit(widget.settings.copyWith(fullRecentTranscriptContext: value));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Agent eval trace'),
          subtitle: const Text('Record real turns for evaluation reports'),
          value: _agentEvalTraceEnabled,
          onChanged: (value) {
            setState(() => _agentEvalTraceEnabled = value);
            _emit(widget.settings.copyWith(agentEvalTraceEnabled: value));
          },
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clear UI cache'),
            onPressed: widget.onClearCache,
          ),
        ),
      ],
    );
  }

  void _emit(PersonalSettings settings) {
    widget.onChanged?.call(settings);
  }
}
