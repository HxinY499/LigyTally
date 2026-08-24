import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/app/home_shell.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/utils/ledger_date.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/features/ledger/presentation/calendar_screen.dart';

/// 日历页回归测试。
///
/// 日历是底栏一级页，和明细各管一份月份。这里锁：
/// 1. 月层级一格一天，格里是**当天**的紧凑金额，不是月合计
/// 2. 点某天在下方展开当天账单
/// 3. 横向翻月读到上个月的数
/// 4. 年层级一格一月，格里是**当月合计**
/// 5. 点年层级的某个月，落回那个月的月层级
/// 6. 口径 tab 只有收支 / 结余，格子和合计一起换
/// 7. 从底栏进日历翻月，回到明细时明细的月份不动
/// 8. 页头「今」能从其他月回到今天并展开当天
/// 9. 点当天面板标题行打开记一笔（与明细页日卡 header 同一手势）
/// 10. 空格日期更淡，和有账的格分开
/// 11. 点月份标题弹出和明细页同一套滚轮，确定后跳到该月
const _monthCaption = '点某天查看当天账单';
const _yearCaption = '点某个月进入当月月历';

void main() {
  final now = DateTime.now();
  final thisMonthDay = dateOnly(now);
  final thisMonth = DateTime(now.year, now.month);
  final lastMonth = DateTime(now.year, now.month - 1);

  /// 上个月里挑一天，刻意避开「和今天同号」——两个月各有一格同号时，
  /// PageView 翻页动画途中两页同时在树上，断言会撞车。
  final lastMonthDay = DateTime(
    lastMonth.year,
    lastMonth.month,
    now.day == 20 ? 21 : 20,
  );

  Future<AppDatabase> seed() async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final categories = await database.exportCategories();
    final expense = categories.firstWhere((item) => item.kind == 0);
    final income = categories.firstWhere((item) => item.kind == 1);
    Future<void> add(String id, int kind, int cents, DateTime day) {
      final stamp = day.millisecondsSinceEpoch;
      return database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: id,
          kind: kind,
          amountCents: cents,
          categoryId: kind == 0 ? expense.id : income.id,
          accountingDate: dateKey(day),
          occurredAt: stamp,
          createdAt: stamp,
          updatedAt: stamp,
        ),
        newImages: const [],
        removedImageIds: const {},
      );
    }

    await add('this-expense', 0, 1200, thisMonthDay);
    await add('this-income', 1, 30000, thisMonthDay);
    await add('last-expense', 0, 5600, lastMonthDay);
    return database;
  }

  /// 不用 pumpAndSettle：页面里有持续动画时它会等不到静止帧而挂死。
  Future<void> settle(WidgetTester tester, {int frames = 6}) async {
    await tester.pump();
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Widget wrap(AppDatabase database, Widget home) {
    final forui = buildForuiTheme();
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        theme: buildMaterialTheme(Brightness.light),
        builder: (context, child) =>
            FTheme(data: forui, child: FToaster(child: child!)),
        home: home,
      ),
    );
  }

  Future<void> pumpCalendar(WidgetTester tester, AppDatabase database) async {
    await tester.pumpWidget(
      wrap(database, Scaffold(body: CalendarScreen(initialMonth: thisMonth))),
    );
    await settle(tester);
  }

  Future<void> pumpShell(WidgetTester tester, AppDatabase database) async {
    await tester.pumpWidget(wrap(database, const HomeShell()));
    await settle(tester);
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('月层级：每格是当天的支出与收入，不是月合计', (tester) async {
    await pumpCalendar(tester, await seed());

    expect(find.text(_monthCaption), findsOneWidget);
    expect(find.text('一'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
    expect(find.text('-12'), findsOneWidget);
    expect(find.text('+300'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('点某天：在页内展开当天账单', (tester) async {
    await pumpCalendar(tester, await seed());

    await tester.tap(find.text('${thisMonthDay.day}'));
    await settle(tester);

    expect(find.text(_monthCaption), findsNothing);
    expect(find.text(formatDay(thisMonthDay)), findsOneWidget);
    expect(find.text('2 笔'), findsOneWidget);
    expect(find.text('-¥12.00'), findsOneWidget);
    expect(find.text('+¥300.00'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('月层级：横向翻月读到上个月的数', (tester) async {
    await pumpCalendar(tester, await seed());

    await tester.tap(find.byTooltip('上个月'));
    await settle(tester);

    expect(find.text('-56'), findsOneWidget);
    expect(find.text('-12'), findsNothing);

    await tester.tap(find.text('${lastMonthDay.day}'));
    await settle(tester);
    expect(find.text(formatDay(lastMonthDay)), findsOneWidget);
    expect(find.text('-¥56.00'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('年层级：一格一月，格里是当月合计', (tester) async {
    await pumpCalendar(tester, await seed());

    await tester.tap(find.byIcon(FLucideIcons.chevronUp));
    await settle(tester);

    expect(find.text(_yearCaption), findsOneWidget);
    expect(find.text('${now.year} 年'), findsOneWidget);
    for (var month = 1; month <= 12; month++) {
      expect(find.text('$month 月'), findsOneWidget);
    }
    expect(find.text('-12'), findsOneWidget);
    expect(find.text('+300'), findsOneWidget);
    expect(find.text('-56'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('年层级：点某个月落回该月的月层级', (tester) async {
    await pumpCalendar(tester, await seed());
    await tester.tap(find.byIcon(FLucideIcons.chevronUp));
    await settle(tester);

    await tester.tap(find.text('3 月'));
    await settle(tester);

    expect(find.text(_monthCaption), findsOneWidget);
    expect(find.text(formatMonth(DateTime(now.year, 3))), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('口径 tab：只有收支与结余两档，格子和合计一起换', (tester) async {
    await pumpCalendar(tester, await seed());

    expect(find.text('收支'), findsOneWidget);
    expect(find.text('结余'), findsOneWidget);

    expect(find.text('-12'), findsOneWidget);
    expect(find.text('+300'), findsOneWidget);

    await tester.tap(find.text('结余'));
    await settle(tester);
    expect(find.text('+288'), findsOneWidget);
    expect(find.text('-12'), findsNothing);
    expect(find.text('+300'), findsNothing);

    await tester.tap(find.text('${thisMonthDay.day}'));
    await settle(tester);
    expect(find.text('2 笔'), findsOneWidget);
    expect(find.text('-¥12.00'), findsOneWidget);
    expect(find.text('+¥300.00'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('底栏进入日历翻月，明细的月份不动', (tester) async {
    await pumpShell(tester, await seed());

    expect(find.text('明细'), findsOneWidget);
    expect(find.text('日历'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.text('日历'));
    await settle(tester);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.byTooltip('上个月'));
    await settle(tester);
    expect(find.text(formatMonth(lastMonth)), findsWidgets);

    await tester.tap(find.text('明细'));
    await settle(tester);
    expect(find.text(formatMonth(thisMonth)), findsOneWidget);
    expect(find.text(formatMonth(lastMonth)), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('页头「今」：从其他月回到今天并展开当天', (tester) async {
    await pumpCalendar(tester, await seed());

    await tester.tap(find.byTooltip('上个月'));
    await settle(tester);
    expect(find.text(formatMonth(lastMonth)), findsWidgets);

    await tester.tap(find.byTooltip('回到今天'));
    await settle(tester);

    expect(find.text(formatMonth(thisMonth)), findsWidgets);
    expect(find.text(formatDay(thisMonthDay)), findsOneWidget);
    expect(find.text(_monthCaption), findsNothing);

    await teardownTree(tester);
  });

  testWidgets('有账的天：点面板标题行打开记一笔', (tester) async {
    await pumpCalendar(tester, await seed());

    await tester.tap(find.text('${thisMonthDay.day}'));
    await settle(tester);
    expect(find.byTooltip('记一笔'), findsOneWidget);

    await tester.tap(find.byTooltip('记一笔'));
    await settle(tester);
    expect(find.text('记一笔'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('空格：日期更淡，点开后标题行仍能记一笔', (tester) async {
    await pumpCalendar(tester, await seed());

    final emptyDay = thisMonthDay.day == 1 ? 2 : 1;
    final dayText = tester.widget<Text>(find.text('$emptyDay'));
    expect(dayText.style!.color, AppColors.light.inactive);

    await tester.tap(find.text('$emptyDay'));
    await settle(tester);
    expect(find.text('这天没有记录'), findsOneWidget);
    expect(find.byTooltip('记一笔'), findsOneWidget);

    await teardownTree(tester);
  });

  testWidgets('点月份标题弹出选择器，确定后跳到邻月', (tester) async {
    await pumpCalendar(tester, await seed());

    await tester.tap(find.byTooltip('选择月份'));
    await settle(tester);
    expect(find.text('确定'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    final neighbor = thisMonth.month == 12 ? 11 : thisMonth.month + 1;
    await tester.tap(find.text('${neighbor.toString().padLeft(2, '0')}月'));
    await settle(tester);
    await tester.tap(find.text('确定'));
    await settle(tester);

    expect(
      find.text(formatMonth(DateTime(thisMonth.year, neighbor))),
      findsWidgets,
    );
    expect(find.text(_monthCaption), findsOneWidget);

    await teardownTree(tester);
  });
}
