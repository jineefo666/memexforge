import 'package:flutter/material.dart';
import 'package:flutter_openclaude/workbench/personal_settings_panel.dart';
import 'package:flutter_openclaude/workbench/provider_settings_panel.dart';
import 'package:flutter_openclaude/workbench/workbench_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('provider settings binds latest provider presets to base URLs', (
    tester,
  ) async {
    ProviderSettings? changed;
    ProviderConnectionRequest? connectionRequest;
    final settings = createInitialWorkbenchState().provider;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProviderSettingsPanel(
            settings: settings,
            onChanged: (value) => changed = value,
            onTestConnection: (request) => connectionRequest = request,
          ),
        ),
      ),
    );

    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.byKey(const ValueKey('model-dropdown')), findsOneWidget);
    expect(find.text('API key'), findsOneWidget);
    expect(find.text('Bridge URL'), findsNothing);
    expect(find.byKey(const ValueKey('bridge-url-field')), findsNothing);
    expect(find.text('Custom base URL'), findsOneWidget);
    expect(find.text('gpt-5.5'), findsOneWidget);
    expect(find.text('gpt-4.1'), findsNothing);
    expect(find.text('gpt-4o'), findsNothing);
    expect(find.text('glm-5.1'), findsNothing);
    expect(find.text('qwen2.5-coder:7b'), findsNothing);
    expect(find.text('google/gemini-3.1-flash-lite-preview'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('API key not configured'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('provider-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Qwen / DashScope'), findsOneWidget);
    expect(find.text('Z.AI GLM'), findsOneWidget);
    expect(find.text('Google Gemini'), findsOneWidget);
    await tester.tap(find.text('Qwen / DashScope'));
    await tester.pumpAndSettle();

    expect(changed?.providerName, 'Qwen / DashScope');
    expect(changed?.modelName, 'qwen3-max');
    expect(
      changed?.baseUrl,
      'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
    );

    await tester.tap(find.byKey(const ValueKey('model-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('qwen3-coder-plus'), findsOneWidget);
    expect(find.text('qwen2.5-coder:7b'), findsNothing);
    await tester.tap(find.text('qwen3-coder-plus'));
    await tester.pumpAndSettle();

    expect(changed?.providerName, 'Qwen / DashScope');
    expect(changed?.modelName, 'qwen3-coder-plus');
    expect(
      changed?.baseUrl,
      'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
    );

    await tester.tap(find.byKey(const ValueKey('provider-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Z.AI GLM'));
    await tester.pumpAndSettle();

    expect(changed?.providerName, 'Z.AI GLM');
    expect(changed?.modelName, 'glm-5.2');
    expect(changed?.baseUrl, 'https://api.z.ai/api/coding/paas/v4');

    await tester.tap(find.byKey(const ValueKey('provider-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Gemini'));
    await tester.pumpAndSettle();

    expect(changed?.providerName, 'Google Gemini');
    expect(changed?.modelName, 'gemini-3.5-flash');
    expect(
      changed?.baseUrl,
      'https://generativelanguage.googleapis.com/v1beta/openai/',
    );

    final apiKeyField = find.byKey(const ValueKey('api-key-field'));
    expect(tester.widget<TextField>(apiKeyField).obscureText, isTrue);

    await tester.enterText(apiKeyField, 'sk-test-secret');
    await tester.tap(find.byTooltip('Test connection'));
    await tester.pumpAndSettle();

    expect(connectionRequest?.apiKey, 'sk-test-secret');
    expect(connectionRequest?.providerName, 'Google Gemini');
    expect(connectionRequest?.modelName, 'gemini-3.5-flash');
    expect(
      connectionRequest?.baseUrl,
      'https://generativelanguage.googleapis.com/v1beta/openai/',
    );
    expect(changed?.apiKeyConfigured, isTrue);
    expect(find.text('sk-test-secret'), findsNothing);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    expect(find.text('配置成功'), findsOneWidget);
  });

  testWidgets('provider settings supports custom model and base URL', (
    tester,
  ) async {
    ProviderSettings? changed;
    ProviderConnectionRequest? connectionRequest;
    final settings = createInitialWorkbenchState().provider;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProviderSettingsPanel(
            settings: settings,
            onChanged: (value) => changed = value,
            onTestConnection: (request) => connectionRequest = request,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('custom-model-field')),
      'provider-latest-agent',
    );
    await tester.enterText(
      find.byKey(const ValueKey('custom-base-url-field')),
      'https://provider.example/v1',
    );
    await tester.tap(find.byTooltip('Use custom endpoint'));
    await tester.pumpAndSettle();

    expect(changed?.providerName, 'Custom OpenAI Compatible');
    expect(changed?.modelName, 'provider-latest-agent');
    expect(changed?.baseUrl, 'https://provider.example/v1');

    await tester.enterText(
      find.byKey(const ValueKey('api-key-field')),
      'sk-custom-secret',
    );
    await tester.tap(find.byTooltip('Test connection'));
    await tester.pumpAndSettle();

    expect(connectionRequest?.providerName, 'Custom OpenAI Compatible');
    expect(connectionRequest?.modelName, 'provider-latest-agent');
    expect(connectionRequest?.baseUrl, 'https://provider.example/v1');
    expect(connectionRequest?.apiKey, 'sk-custom-secret');
  });

  testWidgets('personal settings exposes profile and preference controls', (
    tester,
  ) async {
    PersonalSettings? changed;
    final settings = createInitialWorkbenchState().personal;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalSettingsPanel(
            settings: settings,
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );

    expect(find.text('Personal settings'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Default working directory'), findsNothing);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Full recent conversation context'), findsOneWidget);
    expect(find.text('Agent eval trace'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('display-name-field')),
      'Jinee',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(changed?.displayName, 'Jinee');

    await tester.tap(find.text('Agent eval trace'));
    await tester.pump();

    expect(changed?.agentEvalTraceEnabled, isTrue);

    await tester.tap(find.text('Full recent conversation context'));
    await tester.pump();

    expect(changed?.fullRecentTranscriptContext, isTrue);
  });
}
