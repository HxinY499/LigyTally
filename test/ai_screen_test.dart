import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/ai/application/ai_settings.dart';
import 'package:ligy_tally/features/ai/application/ai_turn_format.dart';
import 'package:ligy_tally/features/ai/data/deepseek_key_store.dart';
import 'package:ligy_tally/features/ai/presentation/ai_chat_pane.dart';
import 'package:ligy_tally/features/ai/presentation/ai_chat_screen.dart';
import 'package:ligy_tally/features/ai/presentation/ai_settings_screen.dart';
import 'package:ligy_tally/features/ledger/application/ledger_service.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/shared/widgets/app_widgets.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyKeyStore extends DeepSeekKeyStore {
  @override
  Future<String?> readFor(AiPlatform platform) async => null;

  @override
  Future<void> writeFor(AiPlatform platform, String value) async {}

  @override
  Future<void> clearFor(AiPlatform platform) async {}
}

class _ConfiguredKeyStore extends DeepSeekKeyStore {
  @override
  Future<String?> readFor(AiPlatform platform) async =>
      platform == AiPlatform.deepseek ? 'test-deepseek-key' : null;

  @override
  Future<void> writeFor(AiPlatform platform, String value) async {}

  @override
  Future<void> clearFor(AiPlatform platform) async {}
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

Widget _chatHost(UseChatController controller) {
  return _host(
    Scaffold(
      body: AppTopBar(
        title: 'AI 助手',
        body: AiChatPane(controller: controller),
      ),
    ),
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
    expect(find.text('先配置 API Key'), findsOneWidget);
    expect(find.text('去配置'), findsOneWidget);
  });

  testWidgets('流式正文能在 AI 页面布局里渲染', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = UseChatController(provider: _ScriptProvider());
    addTearDown(controller.dispose);
    await tester.pumpWidget(_chatHost(controller));
    await controller.sendText('本月花了多少？');
    await tester.pumpAndSettle();

    expect(find.textContaining('本月支出'), findsOneWidget);
    final answer = tester.getRect(find.textContaining('本月支出'));
    final field = tester.getRect(find.byType(TextField));
    expect(
      field.top - answer.bottom,
      inInclusiveRange(16, 88),
      reason: '短回复也该贴在输入框上方，而不是悬在标题下面。answer=$answer field=$field',
    );
    expect(
      find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(CustomScrollView),
      ),
      findsNothing,
      reason: '输入框不能再挂在页头的滚动体上',
    );
  });

  testWidgets('键盘弹起后，新消息贴在输入框上方，不被标题挡住', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);

    final longText = List.filled(14, '上一轮回答用来把对话撑出一屏。').join();
    final initial = AiConversation(
      id: 'c',
      messages: [
        for (var i = 0; i < 4; i++) ...[
          AiMessage(
            id: 'u$i',
            role: AiRole.user,
            parts: [TextPart('更早的问题 $i')],
          ),
          AiMessage(
            id: 'a$i',
            role: AiRole.assistant,
            parts: [TextPart(longText)],
            status: AiMessageStatus.complete,
          ),
        ],
      ],
    );
    final controller = UseChatController(
      provider: _ScriptProvider(),
      initial: initial,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_chatHost(controller));
    await tester.pump();

    const headerBottom = 47.0 + kAppHeaderHeight;
    final listTop = tester.getTopLeft(find.byType(ListView)).dy;
    expect(listTop, greaterThanOrEqualTo(headerBottom - 0.5));
    expect(find.text('更早的问题 0'), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '午饭花了多少');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final question = tester.getRect(find.text('午饭花了多少'));
    final answer = tester.getRect(find.textContaining('本月支出'));
    final field = tester.getRect(find.byType(TextField));
    final distToField = field.top - answer.bottom;
    final distToHeader = question.top - headerBottom;

    expect(
      tester.getTopLeft(find.byType(ListView)).dy,
      greaterThanOrEqualTo(headerBottom - 0.5),
    );
    expect(question.top, greaterThanOrEqualTo(headerBottom));
    expect(answer.top, greaterThanOrEqualTo(question.bottom - 1));
    expect(distToField, inInclusiveRange(16, 88));
    expect(
      distToField,
      lessThan(distToHeader),
      reason:
          '新消息应留在输入框附近，而不是钉到标题下。'
          ' question=$question answer=$answer field=$field',
    );
    expect(field.bottom, lessThanOrEqualTo(844 - 320 + 1));
  });

  testWidgets('AI 设置页展示三个平台，没配 Key 时不列出模型', (tester) async {
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
    expect(find.text('申请 Key'), findsNWidgets(3));
    expect(find.text('DeepSeek'), findsWidgets);
    expect(find.text('智谱'), findsWidgets);
    expect(find.text('Kimi'), findsWidgets);
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(find.text('配好 Key 后，对应平台的模型会出现在这里。'), findsOneWidget);
    expect(find.text('deepseek-flash'), findsNothing);
    expect(find.text('glm-5.3'), findsNothing);
    expect(find.text('kimi-k3.1-pro'), findsNothing);
    expect(find.text('关'), findsOneWidget);
    expect(find.text('低'), findsOneWidget);
    expect(find.text('高'), findsOneWidget);
    expect(find.text('最高'), findsOneWidget);
    expect(find.textContaining('日常查账'), findsNothing);
    expect(find.textContaining('复杂分析'), findsNothing);
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
    expect(find.byTooltip('会话列表'), findsNothing);
    expect(find.byTooltip('新建会话'), findsOneWidget);
    expect(find.text('新会话'), findsOneWidget);

    await tester.tap(find.byTooltip('切换会话'));
    await tester.pumpAndSettle();

    expect(find.text('会话'), findsOneWidget);
    expect(find.text('新建'), findsNothing);
    expect(find.text('新会话'), findsWidgets);

    Navigator.of(tester.element(find.text('会话'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换模型'));
    await tester.pumpAndSettle();
    expect(find.text('deepseek-flash'), findsWidgets);
    expect(find.text('deepseek-v4-pro'), findsOneWidget);
    expect(find.text('glm-5.3'), findsNothing);
    expect(find.text('kimi-k3.1-pro'), findsNothing);
    expect(find.textContaining('可以看图'), findsNothing);
    expect(find.textContaining('不能看图'), findsNothing);

    Navigator.of(tester.element(find.text('模型'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('思考强度'));
    await tester.pumpAndSettle();
    expect(find.text('关'), findsOneWidget);
    expect(find.text('低'), findsOneWidget);
    expect(find.text('高'), findsWidgets);
    expect(find.text('最高'), findsOneWidget);
  });

  testWidgets('工具显示说明，思考默认收起，回复顶部有用时', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = UseChatController(
      provider: _ScriptProvider(),
      initial: AiConversation(
        id: 'c',
        messages: [
          AiMessage.text(id: 'u', role: AiRole.user, text: '这个月花了多少'),
          AiMessage(
            id: 'a',
            role: AiRole.assistant,
            parts: [
              const DataPart(dataType: kTurnTimingDataType, data: {'ms': 1200}),
              const ReasoningPart('先对一下这个月的范围'),
              const ToolCallPart(
                toolCallId: 'c1',
                toolName: 'get_cashflow_summary',
                args: {
                  'desc': '查询这个月的收支',
                  'from': '2026-11-01',
                  'to': '2026-11-14',
                },
                state: ToolCallState.outputAvailable,
              ),
              const TextPart('本月支出不多。'),
            ],
          ),
          const AiMessage(
            id: 'tool',
            role: AiRole.tool,
            parts: [
              ToolResultPart(toolCallId: 'c1', result: {'expenseCents': 10000}),
            ],
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_chatHost(controller));
    await tester.pumpAndSettle();

    expect(find.text('用时 1.2 秒'), findsOneWidget);
    expect(find.textContaining('本月支出不多'), findsOneWidget);
    expect(find.text('思考 · 1 个工具'), findsOneWidget);
    expect(find.textContaining('先对一下'), findsNothing);
    expect(find.text('查询这个月的收支'), findsNothing);

    await tester.tap(find.text('思考 · 1 个工具'));
    await tester.pumpAndSettle();
    expect(find.text('思考'), findsOneWidget);
    expect(find.textContaining('先对一下'), findsNothing);
    expect(find.text('查询这个月的收支'), findsOneWidget);
    expect(find.text('get_cashflow_summary'), findsNothing);

    await tester.tap(find.text('思考'));
    await tester.pumpAndSettle();
    expect(find.textContaining('先对一下'), findsOneWidget);

    await tester.tap(find.text('查询这个月的收支'));
    await tester.pumpAndSettle();
    expect(find.text('get_cashflow_summary'), findsOneWidget);
    expect(find.textContaining('expenseCents'), findsOneWidget);
  });

  testWidgets('正文中包含 <chart> 标记时实时查库渲染内嵌图表卡', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final mediaRoot = Directory.systemTemp.createTempSync('ligy_ai_chart_');
    addTearDown(() async {
      await database.close();
      mediaRoot.deleteSync(recursive: true);
    });
    await database.exportCategories();
    final ledger = LedgerService(database, ImageStorage.atRoot(mediaRoot.path));

    await ledger.save(
      kind: 0,
      amountCents: 6000,
      categoryId: 'expense_food_meals',
      accountingDate: DateTime(2026, 10, 12),
      occurredAt: DateTime(2026, 10, 12, 12),
      note: '午饭',
      pendingImages: const [],
      existingImages: const [],
      removedImageIds: const {},
    );
    await ledger.save(
      kind: 0,
      amountCents: 4000,
      categoryId: 'expense_transport_taxi',
      accountingDate: DateTime(2026, 10, 15),
      occurredAt: DateTime(2026, 10, 15, 19),
      note: '打车',
      pendingImages: const [],
      existingImages: const [],
      removedImageIds: const {},
    );

    final controller = UseChatController(
      provider: _ScriptProvider(),
      initial: AiConversation(
        id: 'c-chart',
        messages: [
          AiMessage.text(id: 'u1', role: AiRole.user, text: '10月分类占比'),
          AiMessage.text(
            id: 'a1',
            role: AiRole.assistant,
            text:
                '10 月共支出 ¥100.00，分类构成如下：\n'
                '<chart>{"type":"category","from":"2026-10-01","to":"2026-10-31","kind":"expense"}</chart>',
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          ledgerServiceProvider.overrideWithValue(ledger),
        ],
        child: _chatHost(controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('支出分类构成'), findsOneWidget);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('交通'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.textContaining('<chart>'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('AI 回答底部复制按钮保留原文包含标签', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final mediaRoot = Directory.systemTemp.createTempSync('ligy_ai_copy_');
    addTearDown(() async {
      await database.close();
      mediaRoot.deleteSync(recursive: true);
    });
    await database.exportCategories();
    final ledger = LedgerService(database, ImageStorage.atRoot(mediaRoot.path));

    const rawAnswer = '找到了这笔：\n<bills>["missing-id"]</bills>\n共 ¥28.00。';
    final controller = UseChatController(
      provider: _ScriptProvider(),
      initial: AiConversation(
        id: 'c-copy',
        messages: [
          AiMessage.text(id: 'u1', role: AiRole.user, text: '查一下'),
          AiMessage.text(
            id: 'a1',
            role: AiRole.assistant,
            text: rawAnswer,
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          ledgerServiceProvider.overrideWithValue(ledger),
        ],
        child: _chatHost(controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('复制'), findsOneWidget);
    await tester.tap(find.byTooltip('复制'));
    await tester.pump();

    expect(copiedText, rawAnswer);
    expect(find.text('已复制'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1700));
    expect(find.text('已复制'), findsNothing);
    expect(find.byTooltip('复制'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
