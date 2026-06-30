import 'package:flutter/material.dart';

import 'workbench_models.dart';

class ProviderSettingsPanel extends StatefulWidget {
  const ProviderSettingsPanel({
    super.key,
    required this.settings,
    this.onChanged,
    this.onApiKeySubmitted,
    this.onTestConnection,
  });

  final ProviderSettings settings;
  final ValueChanged<ProviderSettings>? onChanged;
  final ValueChanged<String>? onApiKeySubmitted;
  final ValueChanged<ProviderConnectionRequest>? onTestConnection;

  @override
  State<ProviderSettingsPanel> createState() => _ProviderSettingsPanelState();
}

class _ProviderSettingsPanelState extends State<ProviderSettingsPanel> {
  late final TextEditingController _apiKeyController;
  late final TextEditingController _customModelController;
  late final TextEditingController _customBaseUrlController;
  late String _providerName;
  late String _modelName;
  late bool _apiKeyConfigured;
  String? _configuredApiKey;

  @override
  void initState() {
    super.initState();
    final knownOption = _presetModelOptionFor(
      widget.settings.providerName,
      widget.settings.modelName,
    );
    _providerName = knownOption?.providerName ?? _customProviderName;
    _modelName = knownOption?.model ?? widget.settings.modelName;
    _apiKeyConfigured = widget.settings.apiKeyConfigured;
    _apiKeyController = TextEditingController();
    _customModelController = TextEditingController(
      text: knownOption == null ? widget.settings.modelName : '',
    );
    _customBaseUrlController = TextEditingController(
      text: knownOption == null ? widget.settings.baseUrl : '',
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _customModelController.dispose();
    _customBaseUrlController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProviderSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.apiKeyConfigured !=
        widget.settings.apiKeyConfigured) {
      _apiKeyConfigured = widget.settings.apiKeyConfigured;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Provider settings', style: theme.textTheme.titleLarge),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: const ValueKey('provider-dropdown'),
          initialValue: _selectedProviderValue,
          decoration: const InputDecoration(labelText: 'Provider'),
          items: [
            for (final provider in _providerOptions)
              DropdownMenuItem(value: provider, child: Text(provider)),
          ],
          onChanged: (value) {
            if (value == null) return;
            final option = _modelOptionsForProvider(value).first;
            setState(() {
              _providerName = value;
              _modelName = option.model;
              _apiKeyConfigured = false;
            });
            _emit(
              widget.settings.copyWith(
                providerName: value,
                modelName: option.model,
                baseUrl: option.baseUrl,
                apiKeyConfigured: false,
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: const ValueKey('model-dropdown'),
          initialValue: _selectedModelValue,
          decoration: const InputDecoration(labelText: 'Model'),
          items: [
            for (final option in _modelOptionsForProvider(_providerName))
              DropdownMenuItem(value: option.model, child: Text(option.model)),
          ],
          onChanged: (value) {
            if (value == null) return;
            final option = _modelOptionFor(_providerName, value);
            setState(() {
              _providerName = option.providerName;
              _modelName = value;
              _apiKeyConfigured = false;
            });
            _emit(
              widget.settings.copyWith(
                providerName: option.providerName,
                modelName: value,
                baseUrl: option.baseUrl,
                apiKeyConfigured: false,
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('custom-model-field'),
          controller: _customModelController,
          decoration: const InputDecoration(
            labelText: 'Custom model',
            prefixIcon: Icon(Icons.tune_outlined),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('custom-base-url-field'),
          controller: _customBaseUrlController,
          decoration: InputDecoration(
            labelText: 'Custom base URL',
            prefixIcon: const Icon(Icons.link_outlined),
            suffixIcon: Tooltip(
              message: 'Use custom endpoint',
              child: IconButton(
                icon: const Icon(Icons.check_circle_outline),
                onPressed: _applyCustomEndpoint,
              ),
            ),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _applyCustomEndpoint(),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('api-key-field'),
          controller: _apiKeyController,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'API key',
            helperText: _apiKeyConfigured
                ? 'Configured. Enter a new key to replace it.'
                : 'Stored by the provider bridge when submitted.',
            suffixIcon: Icon(
              _apiKeyConfigured
                  ? Icons.verified_user_outlined
                  : Icons.key_outlined,
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: _submitApiKey,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(_apiKeyConfigured ? Icons.lock_open : Icons.lock_outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _apiKeyConfigured ? '配置成功' : 'API key not configured',
              ),
            ),
            Tooltip(
              message: 'Test connection',
              child: IconButton(
                icon: const Icon(Icons.network_check),
                onPressed: _testConnection,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _emit(ProviderSettings settings) {
    widget.onChanged?.call(settings);
  }

  void _submitApiKey(String value) {
    final apiKey = value.trim();
    if (apiKey.isEmpty) return;
    _testConnection();
  }

  void _applyCustomEndpoint() {
    final option = _customModelOptionFromFields();
    if (option == null) return;
    setState(() {
      _providerName = option.providerName;
      _modelName = option.model;
      _apiKeyConfigured = false;
    });
    _emit(
      widget.settings.copyWith(
        providerName: option.providerName,
        modelName: option.model,
        baseUrl: option.baseUrl,
        apiKeyConfigured: false,
      ),
    );
  }

  void _testConnection() {
    final enteredApiKey = _apiKeyController.text.trim();
    final apiKey = enteredApiKey.isNotEmpty ? enteredApiKey : _configuredApiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    final option = _providerName == _customProviderName
        ? _customModelOptionFromFields() ??
              _modelOptionFor(_providerName, _modelName)
        : _modelOptionFor(_providerName, _modelName);
    final request = ProviderConnectionRequest(
      providerName: option.providerName,
      modelName: option.model,
      baseUrl: option.baseUrl,
      apiKey: apiKey,
    );
    _configuredApiKey = apiKey;
    widget.onTestConnection?.call(request);
    _apiKeyController.clear();
  }

  List<String> get _providerOptions {
    final providers = {
      for (final option in _allModelOptions) option.providerName,
      _customProviderName,
    }.toList();
    if (providers.contains(_providerName)) return providers;
    return [_providerName, ...providers];
  }

  String get _selectedProviderValue {
    return _providerOptions.contains(_providerName)
        ? _providerName
        : _providerOptions.first;
  }

  String get _selectedModelValue {
    final options = _modelOptionsForProvider(_providerName);
    return options.any((option) => option.model == _modelName)
        ? _modelName
        : options.first.model;
  }

  List<_ModelOption> _modelOptionsForProvider(String providerName) {
    final options = [
      for (final option in _allModelOptions)
        if (option.providerName == providerName) option,
    ];
    if (providerName == _customProviderName) {
      return [
        _customModelOptionFromFields() ??
            _ModelOption(
              model: _modelName,
              providerName: _customProviderName,
              baseUrl: widget.settings.baseUrl,
            ),
      ];
    }
    if (options.any((option) => option.model == _modelName)) return options;
    if (providerName == widget.settings.providerName) {
      return [
        _ModelOption(
          model: _modelName,
          providerName: widget.settings.providerName,
          baseUrl: widget.settings.baseUrl,
        ),
        ...options,
      ];
    }
    return options.isEmpty
        ? [
            _ModelOption(
              model: _modelName,
              providerName: providerName,
              baseUrl: widget.settings.baseUrl,
            ),
          ]
        : options;
  }

  _ModelOption _modelOptionFor(String providerName, String modelName) {
    final presetOption = _presetModelOptionFor(providerName, modelName);
    if (presetOption != null) return presetOption;
    if (providerName == _customProviderName) {
      return _customModelOptionFromFields() ??
          _ModelOption(
            model: modelName,
            providerName: providerName,
            baseUrl: widget.settings.baseUrl,
          );
    }
    return _ModelOption(
      model: modelName,
      providerName: providerName,
      baseUrl: widget.settings.baseUrl,
    );
  }

  _ModelOption? _customModelOptionFromFields() {
    final model = _customModelController.text.trim();
    final baseUrl = _customBaseUrlController.text.trim();
    if (model.isEmpty || baseUrl.isEmpty) return null;
    return _ModelOption(
      model: model,
      providerName: _customProviderName,
      baseUrl: baseUrl,
    );
  }

  _ModelOption? _presetModelOptionFor(String providerName, String modelName) {
    for (final option in _allModelOptions) {
      if (option.providerName == providerName && option.model == modelName) {
        return option;
      }
    }
    return null;
  }
}

final class _ModelOption {
  const _ModelOption({
    required this.model,
    required this.providerName,
    required this.baseUrl,
  });

  final String model;
  final String providerName;
  final String baseUrl;
}

const _customProviderName = 'Custom OpenAI Compatible';

const _allModelOptions = [
  _ModelOption(
    model: 'gpt-5.5',
    providerName: 'OpenAI Compatible',
    baseUrl: 'https://api.openai.com/v1',
  ),
  _ModelOption(
    model: 'gpt-5.5-pro',
    providerName: 'OpenAI Compatible',
    baseUrl: 'https://api.openai.com/v1',
  ),
  _ModelOption(
    model: 'deepseek-v4-flash',
    providerName: 'OpenAI Compatible',
    baseUrl: 'https://api.deepseek.com/v1',
  ),
  _ModelOption(
    model: 'deepseek-v4-pro',
    providerName: 'OpenAI Compatible',
    baseUrl: 'https://api.deepseek.com/v1',
  ),
  _ModelOption(
    model: 'qwen3-max',
    providerName: 'Qwen / DashScope',
    baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  ),
  _ModelOption(
    model: 'qwen3-max-preview',
    providerName: 'Qwen / DashScope',
    baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  ),
  _ModelOption(
    model: 'qwen3-coder-plus',
    providerName: 'Qwen / DashScope',
    baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  ),
  _ModelOption(
    model: 'qwen3-coder-flash',
    providerName: 'Qwen / DashScope',
    baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  ),
  _ModelOption(
    model: 'qwen3.5-plus',
    providerName: 'Qwen / DashScope',
    baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  ),
  _ModelOption(
    model: 'qwen3.5-flash',
    providerName: 'Qwen / DashScope',
    baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  ),
  _ModelOption(
    model: 'qwen-plus-latest',
    providerName: 'Qwen / DashScope',
    baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  ),
  _ModelOption(
    model: 'glm-5.2',
    providerName: 'Z.AI GLM',
    baseUrl: 'https://api.z.ai/api/coding/paas/v4',
  ),
  _ModelOption(
    model: 'gemini-3.5-flash',
    providerName: 'Google Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
  ),
  _ModelOption(
    model: 'gemini-3.1-pro-preview',
    providerName: 'Google Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
  ),
  _ModelOption(
    model: 'gemini-3.1-flash-lite',
    providerName: 'Google Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
  ),
  _ModelOption(
    model: 'gemini-3-flash-preview',
    providerName: 'Google Gemini',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
  ),
  _ModelOption(
    model: 'claude-sonnet-4-6',
    providerName: 'Anthropic',
    baseUrl: 'https://api.anthropic.com',
  ),
  _ModelOption(
    model: 'claude-opus-4-8',
    providerName: 'Anthropic',
    baseUrl: 'https://api.anthropic.com',
  ),
  _ModelOption(
    model: 'claude-haiku-4-5',
    providerName: 'Anthropic',
    baseUrl: 'https://api.anthropic.com',
  ),
  _ModelOption(
    model: 'llama3.1:8b',
    providerName: 'Ollama',
    baseUrl: 'http://localhost:11434/v1',
  ),
];
