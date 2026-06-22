import 'package:flutter/material.dart';

import 'workbench_models.dart';

class McpPanel extends StatefulWidget {
  const McpPanel({
    super.key,
    required this.state,
    this.onServerSaved,
    this.onServerTested,
    this.onServerEnabledChanged,
    this.onServerDeleted,
  });

  final ExtensionsState state;
  final ValueChanged<McpServerDraft>? onServerSaved;
  final ValueChanged<McpServerDraft>? onServerTested;
  final void Function(String serverId, bool enabled)? onServerEnabledChanged;
  final ValueChanged<String>? onServerDeleted;

  @override
  State<McpPanel> createState() => _McpPanelState();
}

class _McpPanelState extends State<McpPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final servers = _filteredServers();
    return Padding(
      key: const ValueKey('extensions-mcp-panel'),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('extensions-mcp-search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search MCP servers',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Add MCP server',
                child: IconButton.filled(
                  key: const ValueKey('mcp-add-server-button'),
                  icon: const Icon(Icons.add),
                  onPressed: () => _openEditor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildBody(context, servers)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<McpServerSummary> servers) {
    return switch (widget.state.mcpStatus) {
      ExtensionInventoryStatus.loading => const _PanelStateMessage(
        icon: Icons.sync,
        title: 'Loading MCP servers',
      ),
      ExtensionInventoryStatus.failed => _PanelStateMessage(
        icon: Icons.error_outline,
        title: 'MCP unavailable',
        detail: widget.state.mcpErrorMessage,
      ),
      _ when servers.isEmpty => const _PanelStateMessage(
        icon: Icons.hub_outlined,
        title: 'No MCP servers found',
      ),
      _ => _McpInventory(
        servers: servers,
        testResults: widget.state.mcpTestResults,
        onEdit: (server) => _openEditor(context, server: server),
        onTested: widget.onServerTested,
        onEnabledChanged: widget.onServerEnabledChanged,
        onDeleted: widget.onServerDeleted,
      ),
    };
  }

  List<McpServerSummary> _filteredServers() {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.state.mcpServers;
    return [
      for (final server in widget.state.mcpServers)
        if (server.name.toLowerCase().contains(query) ||
            server.transport.toLowerCase().contains(query) ||
            server.scope.toLowerCase().contains(query))
          server,
    ];
  }

  Future<void> _openEditor(
    BuildContext context, {
    McpServerSummary? server,
  }) async {
    final draft = await showDialog<McpServerDraft>(
      context: context,
      builder: (_) => _McpServerEditorDialog(server: server),
    );
    if (draft != null) widget.onServerSaved?.call(draft);
  }
}

class _McpInventory extends StatefulWidget {
  const _McpInventory({
    required this.servers,
    required this.testResults,
    this.onEdit,
    this.onTested,
    this.onEnabledChanged,
    this.onDeleted,
  });

  final List<McpServerSummary> servers;
  final Map<String, McpConnectionTestResult> testResults;
  final ValueChanged<McpServerSummary>? onEdit;
  final ValueChanged<McpServerDraft>? onTested;
  final void Function(String serverId, bool enabled)? onEnabledChanged;
  final ValueChanged<String>? onDeleted;

  @override
  State<_McpInventory> createState() => _McpInventoryState();
}

class _McpInventoryState extends State<_McpInventory> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedServer();
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: ListView.separated(
            itemCount: widget.servers.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final server = widget.servers[index];
              final selected =
                  server.id == (_selectedId ?? widget.servers.first.id);
              return _McpServerRow(
                server: server,
                selected: selected,
                onTap: () => setState(() => _selectedId = server.id),
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: _McpServerDetail(
            server: selected,
            testResult: widget.testResults[selected.id],
            onEdit: widget.onEdit,
            onTested: widget.onTested,
            onEnabledChanged: widget.onEnabledChanged,
            onDeleted: widget.onDeleted,
          ),
        ),
      ],
    );
  }

  McpServerSummary _selectedServer() {
    final selectedId = _selectedId;
    if (selectedId != null) {
      for (final server in widget.servers) {
        if (server.id == selectedId) return server;
      }
    }
    return widget.servers.first;
  }
}

class _McpServerRow extends StatelessWidget {
  const _McpServerRow({
    required this.server,
    required this.selected,
    required this.onTap,
  });

  final McpServerSummary server;
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
        title: Text(server.name),
        subtitle: Text('${server.scope} · ${server.transport}'),
        leading: Icon(
          server.enabled ? Icons.hub_outlined : Icons.power_settings_new,
        ),
        trailing: _StatusPill(
          label: server.enabled ? server.status : 'disabled',
          enabled: server.enabled,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _McpServerDetail extends StatelessWidget {
  const _McpServerDetail({
    required this.server,
    this.testResult,
    this.onEdit,
    this.onTested,
    this.onEnabledChanged,
    this.onDeleted,
  });

  final McpServerSummary server;
  final McpConnectionTestResult? testResult;
  final ValueChanged<McpServerSummary>? onEdit;
  final ValueChanged<McpServerDraft>? onTested;
  final void Function(String serverId, bool enabled)? onEnabledChanged;
  final ValueChanged<String>? onDeleted;

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
          key: const ValueKey('mcp-server-detail-scroll'),
          children: [
            Text(server.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _DetailIconButton(
                  tooltip: 'Edit MCP server',
                  icon: Icons.edit_outlined,
                  onPressed: () => onEdit?.call(server),
                ),
                _DetailIconButton(
                  tooltip: 'Test MCP server',
                  icon: Icons.network_check,
                  onPressed: () => onTested?.call(_draftForServer(server)),
                ),
                _DetailIconButton(
                  tooltip: server.enabled
                      ? 'Disable MCP server'
                      : 'Enable MCP server',
                  icon: server.enabled
                      ? Icons.power_settings_new
                      : Icons.play_arrow_outlined,
                  onPressed: () =>
                      onEnabledChanged?.call(server.id, !server.enabled),
                ),
                _DetailIconButton(
                  tooltip: 'Delete MCP server',
                  icon: Icons.delete_outline,
                  onPressed: () => onDeleted?.call(server.id),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${server.scope} · ${server.transport}'),
            const SizedBox(height: 16),
            _DetailRow(label: 'Status', value: server.status),
            _DetailRow(label: 'Tools', value: server.toolCount.toString()),
            _DetailRow(
              label: 'Resources',
              value: server.resourceCount.toString(),
            ),
            _DetailRow(label: 'Skills', value: server.skillCount.toString()),
            if (testResult != null) _McpTestResultPreview(result: testResult!),
            if (server.command != null)
              _DetailRow(label: 'Command', value: server.command!),
            if (server.args != null && server.args!.isNotEmpty)
              _DetailRow(label: 'Args', value: server.args!.join(' ')),
            if (server.url != null)
              _DetailRow(label: 'URL', value: server.url!),
            for (final line in _recordLines('Header', server.headers))
              _DetailRow(label: line.label, value: line.value),
            for (final line in _recordLines('Env', server.env))
              _DetailRow(label: line.label, value: line.value),
            if (server.lastError != null)
              _DetailRow(label: 'Issue', value: server.lastError!),
          ],
        ),
      ),
    );
  }
}

class _McpTestResultPreview extends StatelessWidget {
  const _McpTestResultPreview({required this.result});

  final McpConnectionTestResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isTesting = result.status == 'testing';
    final isConnected = result.status == 'connected';
    final icon = isTesting
        ? Icons.sync
        : isConnected
        ? Icons.check_circle_outline
        : Icons.error_outline;
    final color = isConnected
        ? colorScheme.primary
        : isTesting
        ? colorScheme.secondary
        : colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(8),
          color: color.withValues(alpha: 0.08),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.status,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  if (result.durationMs > 0)
                    Text(
                      '${result.durationMs}ms',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
              if (result.message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(result.message),
              ],
              for (final section in [
                _capabilitySection('Tools', result.tools),
                _capabilitySection('Resources', result.resources),
                _capabilitySection('Prompts', result.prompts),
              ])
                if (section.items.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    section.label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final item in section.items)
                        Chip(
                          label: Text(item.name),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              if (result.skills.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Skills', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final skill in result.skills)
                      Chip(
                        label: Text(skill.name),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

({String label, List<McpCapabilityItem> items}) _capabilitySection(
  String label,
  List<McpCapabilityItem> items,
) {
  return (label: label, items: items);
}

class _McpServerEditorDialog extends StatefulWidget {
  const _McpServerEditorDialog({this.server});

  final McpServerSummary? server;

  @override
  State<_McpServerEditorDialog> createState() => _McpServerEditorDialogState();
}

class _McpServerEditorDialogState extends State<_McpServerEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _commandController;
  late final TextEditingController _argsController;
  late final TextEditingController _urlController;
  late final TextEditingController _headersController;
  late final TextEditingController _envController;
  late String _transport;
  late String _scope;
  late bool _enabled;
  String? _keyValueError;

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    _transport = _editableTransport(server?.transport ?? 'stdio');
    _scope = _editableScope(server?.scope ?? 'project');
    _enabled = server?.enabled ?? true;
    _nameController = TextEditingController(text: server?.name ?? '');
    _commandController = TextEditingController(text: server?.command ?? '');
    _argsController = TextEditingController(
      text: server?.args?.join(' ') ?? '',
    );
    _urlController = TextEditingController(text: server?.url ?? '');
    _headersController = TextEditingController(
      text: _recordText(server?.headers),
    );
    _envController = TextEditingController(text: _recordText(server?.env));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    _urlController.dispose();
    _headersController.dispose();
    _envController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isStdio = _transport == 'stdio';
    return AlertDialog(
      key: const ValueKey('mcp-server-editor'),
      title: Text(widget.server == null ? 'Add MCP server' : 'Edit MCP server'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('mcp-server-name-input'),
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _transport,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Transport',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'stdio',
                            child: Text('stdio'),
                          ),
                          DropdownMenuItem(value: 'sse', child: Text('sse')),
                          DropdownMenuItem(
                            value: 'streamable_http',
                            child: Text('streamable_http'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _transport = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _scope,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Scope'),
                        items: const [
                          DropdownMenuItem(
                            value: 'project',
                            child: Text('project'),
                          ),
                          DropdownMenuItem(value: 'user', child: Text('user')),
                          DropdownMenuItem(
                            value: 'local',
                            child: Text('local'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _scope = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isStdio) ...[
                  TextFormField(
                    key: const ValueKey('mcp-server-command-input'),
                    controller: _commandController,
                    decoration: const InputDecoration(labelText: 'Command'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Command is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('mcp-server-args-input'),
                    controller: _argsController,
                    decoration: const InputDecoration(labelText: 'Args'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('mcp-server-env-input'),
                    controller: _envController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Environment',
                      hintText: 'TOKEN=value',
                    ),
                  ),
                ] else ...[
                  TextFormField(
                    key: const ValueKey('mcp-server-url-input'),
                    controller: _urlController,
                    decoration: const InputDecoration(labelText: 'URL'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'URL is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('mcp-server-headers-input'),
                    controller: _headersController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Headers',
                      hintText: 'Authorization=Bearer token',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _enabled,
                  title: const Text('Enabled'),
                  onChanged: (value) => setState(() => _enabled = value),
                ),
                if (_keyValueError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _keyValueError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('mcp-server-save-button'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _keyValueError = null);

    Map<String, String>? headers;
    Map<String, String>? env;
    try {
      headers = _transport == 'stdio'
          ? null
          : _parseKeyValueLines(_headersController.text);
      env = _transport == 'stdio'
          ? _parseKeyValueLines(_envController.text)
          : null;
    } on FormatException catch (error) {
      setState(() => _keyValueError = error.message);
      return;
    }

    Navigator.of(context).pop(
      McpServerDraft(
        id: widget.server?.id,
        name: _nameController.text.trim(),
        transport: _transport,
        scope: _scope,
        command: _transport == 'stdio' ? _commandController.text.trim() : null,
        args: _transport == 'stdio' ? _splitArgs(_argsController.text) : null,
        url: _transport == 'stdio' ? null : _urlController.text.trim(),
        headers: headers,
        env: env,
        enabled: _enabled,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: enabled
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
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

({String label, String value}) _recordLine(
  String prefix,
  String key,
  String value,
) {
  return (label: prefix, value: '$key=$value');
}

List<({String label, String value})> _recordLines(
  String prefix,
  Map<String, String>? value,
) {
  if (value == null || value.isEmpty) return const [];
  return [
    for (final entry in value.entries)
      _recordLine(prefix, entry.key, entry.value),
  ];
}

String _recordText(Map<String, String>? value) {
  if (value == null || value.isEmpty) return '';
  return value.entries.map((entry) => '${entry.key}=${entry.value}').join('\n');
}

String _editableTransport(String transport) {
  if (transport == 'sse' || transport == 'streamable_http') return transport;
  return 'stdio';
}

String _editableScope(String scope) {
  if (scope == 'local' || scope == 'user' || scope == 'project') return scope;
  return 'project';
}

List<String> _splitArgs(String value) {
  return [
    for (final part in value.trim().split(RegExp(r'\s+')))
      if (part.isNotEmpty) part,
  ];
}

Map<String, String>? _parseKeyValueLines(String value) {
  final result = <String, String>{};
  for (final rawLine in value.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) {
      throw const FormatException('Use KEY=value for environment and headers.');
    }
    final key = line.substring(0, separator).trim();
    final entryValue = line.substring(separator + 1).trim();
    if (key.isEmpty) {
      throw const FormatException('Keys cannot be empty.');
    }
    result[key] = entryValue;
  }
  return result.isEmpty ? null : result;
}

McpServerDraft _draftForServer(McpServerSummary server) {
  return McpServerDraft(
    id: server.id,
    name: server.name,
    transport: _editableTransport(server.transport),
    scope: _editableScope(server.scope),
    command: server.command,
    args: server.args,
    url: server.url,
    headers: server.headers,
    env: server.env,
    enabled: server.enabled,
  );
}
