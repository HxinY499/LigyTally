import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/ai/application/ai_settings.dart';
import 'package:ligy_tally/features/ai/data/deepseek_key_store.dart';
import 'package:ligy_tally/features/ai/presentation/ai_chat_screen.dart';
import 'package:ligy_tally/features/ai/presentation/ai_settings_screen.dart';
import 'package:ligy_tally/features/ledger/application/ledger_service.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/shared/widgets/app_widgets.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyKeyStore extends DeepSeekKeyStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> clear() async {}
}

class _ConfiguredKeyStore extends DeepSeekKeyStore {
  @override
  Future<String?> read() async => 'test-deepseek-key';

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> clear() async {}
}

class _ScriptProvider implements LlmProvider {
  @override
  Stream<AiStreamEvent> send(
    AiConversation conversation, {
    List<ToolDefinition>? tools,
    AiRequestOptions? options,
  }) async* {
    yield const MessageStarted(
      messageId: 'assistant-1',
      role: AiRole.assistant,
    );
    yield const TextDelta(messageId: 'assistant-1', delta: '本月支出 ¥100.00。');
    yield const MessageFinished(
      messageId: 'assistant-1',
      reason: FinishReason.stop,
    );
  }
}

Widget _host(Widget home) {
  const config = AppearanceConfig.initial;
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: const [
      FLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildMaterialTheme(Brightness.light, config),
    builder: (context, child) =>
        FTheme(data: foruiThemeFor(Brightness.light, config), child: child!),
    home: home,
  );
}

void main() {
  testWidgets('没有 Key 时 AI 页面显示配置引导，而不是崩溃或空白', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deepSeekKeyStoreProvider.overrideWithValue(_EmptyKeyStore()),
        ],
        child: _host(const AiChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 助手'), findsWidgets);
    expect(find.text('先配置 DeepSeek API Key'), findsOneWidget);
    expect(find.text('去配置'), findsOneWidget);
  });

  testWidgets('流式正文能在 AI 页面布局里渲染', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = UseChatController(provider: _ScriptProvider());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: AppTopBar(
            title: 'AI 助手',
            slivers: [
              SliverFillRemaining(
                hasScrollBody: true,
                child: AiChatView(controller: controller),
              ),
            ],
          ),
        ),
      ),
    );
    await controller.sendText('本月花了多少？');
    await tester.pumpAndSettle();

    expect(find.textContaining('本月支出'), findsOneWidget);
  });

  testWidgets('AI 设置页展示 Key 输入和两个模型', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deepSeekKeyStoreProvider.overrideWithValue(_EmptyKeyStore()),
        ],
        child: _host(const AiSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 助手设置'), findsWidgets);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('deepseek-flash'), findsOneWidget);
    expect(find.text('deepseek-v4-pro'), findsOneWidget);
  });

  testWidgets('配置 Key 后可以打开会话列表', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final mediaRoot = Directory.systemTemp.createTempSync('ligy_ai_screen_');
    addTearDown(() async {
      await database.close();
      mediaRoot.deleteSync(recursive: true);
    });
    await database.exportCategories();
    final ledger = LedgerService(database, ImageStorage.atRoot(mediaRoot.path));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deepSeekKeyStoreProvider.overrideWithValue(_ConfiguredKeyStore()),
          databaseProvider.overrideWithValue(database),
          ledgerServiceProvider.overrideWithValue(ledger),
        ],
        child: _host(const AiChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('问问你的账本'), findsOneWidget);
    await tester.tap(find.byTooltip('会话列表'));
    await tester.pumpAndSettle();

    expect(find.text('会话'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('新会话'), findsWidgets);
  });
}
