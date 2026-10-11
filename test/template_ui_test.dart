import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/features/ledger/presentation/template_sheet.dart';
import 'package:ligy_tally/features/ledger/presentation/transaction_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模板编辑复用记一笔页：金额 / 分类 / 备注照旧，属于「某一次记账」的
/// 日期、时刻、位置、图片收起，保存进模板表而不是账单表。
///
/// 记账面板：点一行立即记一笔、面板不关、可撤销。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHome(
    WidgetTester tester,
    AppDatabase database,
    Widget home,
  ) async {
    tester.view.physicalSize = const Size(1200, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final forui = buildForuiTheme();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: forui.toApproximateMaterialTheme(),
          builder: (context, child) => FTheme(
            data: forui,
            child: FToaster(child: child!),
          ),
          home: home,
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> pump(WidgetTester tester, AppDatabase database) =>
      pumpHome(tester, database, const TransactionEditor.template());

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('收起日期、位置、图片，只留金额分类备注', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await pump(tester, database);

    expect(find.text('新建模板'), findsOneWidget);
    expect(find.text('今天'), findsNothing);
    expect(find.text('位置'), findsNothing);
    expect(find.text('再建一个'), findsOneWidget);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('保存进模板表，不产生账单', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await pump(tester, database);

    await tester.tap(find.text('5'));
    await tester.tap(find.text('9'));
    await tester.tap(find.text('餐饮'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '午饭');
    await tester.tap(find.text('¥'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    final templates = await tester.runAsync(database.exportTemplates);
    expect(templates, hasLength(1));
    expect(templates!.single.amountCents, 5900);
    expect(templates.single.note, '午饭');
    expect(await tester.runAsync(database.exportTransactions), isEmpty);

    await teardown(tester);
  });

  testWidgets('记账面板点一行就记一笔，面板不关，可撤销', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.runAsync(() async {
      final category = (await database.exportCategories()).firstWhere(
        (row) => row.kind == 0 && row.level == 2,
      );
      await database.saveTemplate(
        newId: 'rent',
        kind: 0,
        amountCents: 300000,
        categoryId: category.id,
        note: '房租',
      );
    });
    await pumpHome(
      tester,
      database,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showTemplateSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    Future<void> settle() async {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.tap(find.text('open'));
    await settle();
    expect(find.text('模板记账'), findsOneWidget);

    await tester.tap(find.text('房租'));
    await settle();
    final recorded = await tester.runAsync(database.exportTransactions);
    expect(recorded, hasLength(1));
    expect(recorded!.single.amountCents, 300000);
    expect(find.text('模板记账'), findsOneWidget, reason: '记完面板要留着，方便连记几笔');
    const badge = ValueKey('template-recorded-rent');
    expect(find.byKey(badge), findsOneWidget);
    expect(find.text('已记入今天'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await settle();
    expect(await tester.runAsync(database.exportTransactions), isEmpty);
    expect(find.byKey(badge), findsNothing, reason: '撤销后角标要退掉');

    // 等 toast 的自动消失计时器走完再拆树。
    await tester.pump(const Duration(seconds: 5));
    await teardown(tester);
  });
}
