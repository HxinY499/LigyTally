import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/utils/ledger_date.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/features/ledger/presentation/ledger_screen.dart';

/// 月历弹窗回归测试。
///
/// 它和统计页的趋势图吃同一批按天聚合数据，但职责是「按星期铺开 + 跳到某天」。
/// 这里锁两件事：
/// 1. 每格显示的是当天的支出/收入紧凑金额，而不是把月合计抄一遍
/// 2. 点有记录的那天会回到列表并高亮那张日卡（跳转链路不能哑掉）
/// 弹窗里的说明行，用来把断言锁在弹窗内——月份标题在吸顶条上也有一份。
const _calendarCaption = '点某天定位到当天账单，没记录的天直接记一笔';

void main() {
  Future<AppDatabase> seed({
    required int expenseCents,
    required int incomeCents,
  }) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final categories = await database.exportCategories();
    final expense = categories.firstWhere((item) => item.kind == 0);
    final income = categories.firstWhere((item) => item.kind == 1);
    final now = DateTime.now();
    Future<void> add(String id, int kind, int cents, String categoryId) {
      return database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: id,
          kind: kind,
          amountCents: cents,
          categoryId: categoryId,
          accountingDate: dateKey(now),
          occurredAt: now.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
        newImages: const [],
        removedImageIds: const {},
      );
    }

    await add('calendar-expense', 0, expenseCents, expense.id);
    await add('calendar-income', 1, incomeCents, income.id);
    return database;
  }

  Future<void> pumpLedger(WidgetTester tester, AppDatabase database) async {
    final forui = buildForuiTheme();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: buildMaterialTheme(Brightness.light),
          builder: (context, child) =>
              FTheme(data: forui, child: FToaster(child: child!)),
          // LedgerScreen 不自带 Scaffold，页头里的 InkResponse 需要 Material 祖先。
          home: const Scaffold(body: LedgerScreen()),
        ),
      ),
    );
    // 不用 pumpAndSettle：页面里有持续动画时它会等不到静止帧而挂死。
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> teardownTree(WidgetTester tester) async {
    // drift 取消订阅时会排一个 0ms 的清理定时器，测试结束前要放掉它。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('每格显示当天的支出与收入，而不是月合计', (tester) async {
    final database = await seed(expenseCents: 1200, incomeCents: 30000);
    await pumpLedger(tester, database);

    await tester.tap(find.byTooltip('月历'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    // 月份标题吸顶条上也有一份，所以用弹窗独有的说明行当锚点。
    expect(find.text(_calendarCaption), findsOneWidget);
    // 周一起始的星期表头。
    expect(find.text('一'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
    // 格子里是紧凑金额（轴刻度那一套），不是 ¥12.00。
    expect(find.text('-12'), findsOneWidget);
    expect(find.text('+300'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('点有记录的那天：弹窗关闭并高亮对应日卡', (tester) async {
    final database = await seed(expenseCents: 1200, incomeCents: 30000);
    await pumpLedger(tester, database);

    await tester.tap(find.byTooltip('月历'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    final now = DateTime.now();
    await tester.tap(find.text('${now.day}'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // 弹窗已经退场。
    expect(find.text(_calendarCaption), findsNothing);
    // 目标日卡挂上了主色前景描边（画在前景是为了不把卡片内容挤窄）。
    final highlighted = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where(
          (decoration) =>
              decoration.border?.top.color == AppColors.light.primary,
        );
    expect(highlighted, isNotEmpty);

    await teardownTree(tester);
  });
}
