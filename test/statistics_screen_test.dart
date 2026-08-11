import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/utils/ledger_date.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/features/statistics/presentation/statistics_screen.dart';
import 'package:ligy_tally/features/statistics/presentation/statistics_window.dart';
import 'package:ligy_tally/features/statistics/presentation/stats_category.dart';
import 'package:ligy_tally/features/statistics/presentation/stats_design.dart';

/// 统计页回归测试。
///
/// 这一屏图表多、状态多（加载 / 空 / 有数据），纯靠肉眼回归很容易漏。
/// 这里锁三件事：
/// 1. [StatisticsWindow] 的日期口径（区间、环比、对比区间、聚合粒度）
/// 2. 轴刻度金额的紧凑格式
/// 3. 页面在「空库」与「有账单」两种情况下都能渲染出关键文案，不抛异常
void main() {
  group('StatisticsWindow 日期口径', () {
    test('月视图：区间为自然月，上一周期为上个自然月', () {
      final window = StatisticsWindow(
        period: StatisticsPeriod.month,
        anchor: DateTime(2026, 8, 15),
      );

      expect(window.range.start, DateTime(2026, 8));
      expect(window.range.endExclusive, DateTime(2026, 9));
      expect(window.previousRange.start, DateTime(2026, 7));
      expect(window.previousRange.endExclusive, DateTime(2026, 8));
      expect(window.rangeLabel, '2026 年 8 月');
      expect(window.previousLabel, '较上月');
      // 月视图按天聚合。
      expect(window.groupByMonth, isFalse);
    });

    test('年视图：按月聚合，上一周期为去年', () {
      final window = StatisticsWindow(
        period: StatisticsPeriod.year,
        anchor: DateTime(2026, 8, 15),
      );

      expect(window.range.start, DateTime(2026));
      expect(window.range.endExclusive, DateTime(2027));
      expect(window.previousRange.start, DateTime(2025));
      expect(window.groupByMonth, isTrue);
      expect(window.rangeLabel, '2026 年');
    });

    test('周视图：周一为起点，上一周期为前七天', () {
      // 2026-08-15 是周六，所在周应为 08-10(周一) ~ 08-17(次周一，开区间)。
      final window = StatisticsWindow(
        period: StatisticsPeriod.week,
        anchor: DateTime(2026, 8, 15),
      );

      expect(window.range.start, DateTime(2026, 8, 10));
      expect(window.range.endExclusive, DateTime(2026, 8, 17));
      expect(window.range.dayCount, 7);
      expect(window.previousRange.start, DateTime(2026, 8, 3));
    });

    test('自定义区间：环比整体平移一个等长区间；超 62 天才按月聚合', () {
      final short = StatisticsWindow(
        period: StatisticsPeriod.custom,
        anchor: DateTime(2026, 8, 15),
        customRange: LedgerDateRange(
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 11),
        ),
      );

      expect(short.range.dayCount, 10);
      // 上期= 往前平移 10 天。
      expect(short.previousRange.start, DateTime(2026, 7, 22));
      expect(short.previousRange.endExclusive, DateTime(2026, 8, 1));
      expect(short.groupByMonth, isFalse);

      final long = StatisticsWindow(
        period: StatisticsPeriod.custom,
        anchor: DateTime(2026, 8, 15),
        customRange: LedgerDateRange(
          DateTime(2026, 1, 1),
          DateTime(2026, 8, 1),
        ),
      );
      expect(long.groupByMonth, isTrue, reason: '跨度> 62 天应改按月聚合');
    });

    test('对比区间恒为 6 段且末位是当前周期', () {
      final window = StatisticsWindow(
        period: StatisticsPeriod.month,
        anchor: DateTime(2026, 8, 15),
      );

      final spans = window.comparisonSpans;
      expect(spans, hasLength(6));
      // 升序：3月 → 8月。
      expect(spans.first.range.start, DateTime(2026, 3));
      expect(spans.last.range.start, DateTime(2026, 8));
      expect(spans.last.label, '8月');
    });

    test('shifted 前后平移不改变周期类型', () {
      final window = StatisticsWindow(
        period: StatisticsPeriod.month,
        anchor: DateTime(2026, 8, 15),
      );

      final next = window.shifted(1);
      expect(next.period, StatisticsPeriod.month);
      expect(next.range.start, DateTime(2026, 9));
      expect(window.shifted(-1).range.start, DateTime(2026, 7));
    });

    test('includesToday 用于禁用「下一周期」', () {
      final now = DateTime.now();
      final current = StatisticsWindow(
        period: StatisticsPeriod.month,
        anchor: now,
      );
      expect(current.includesToday, isTrue);
      // 往前翻一个月后就不再包含今天。
      expect(current.shifted(-1).includesToday, isFalse);
    });
  });

  group('轴刻度金额格式', () {
    test('按量级收敛并去掉多余小数', () {
      expect(formatAxisMoney(0), '0');
      // 888.00 元。
      expect(formatAxisMoney(88800), '888');
      // 1200 元 → 1.2千。
      expect(formatAxisMoney(120000), '1.2千');
      // 整千不留 .0。
      expect(formatAxisMoney(100000), '1千');
      // 3.5万。
      expect(formatAxisMoney(3500000), '3.5万');
      // 1.2 亿。
      expect(formatAxisMoney(12000000000), '1.2亿');
    });
  });

  group('统计页渲染', () {
    /// 用内存库跑真实页面，避免 mock 与真实 SQL 口径脱节。
    Future<Widget> host(AppDatabase database) async {
      final forui = buildForuiTheme();
      return ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: forui.toApproximateMaterialTheme(),
          builder: (context, child) => FTheme(
            data: forui,
            child: FToaster(child: child!),
          ),
          home: const Scaffold(body: StatisticsScreen()),
        ),
      );
    }

    /// 把测试视口拉高。
    ///
    /// flutter_test 默认视口 800x600，而统计页四张卡纵向远超600；
    /// ListView 懒加载会导致靠下的「分类构成 / 周期对比」根本没被build，
    /// 断言自然找不到。拉到 2400高让整页一次性布局出来。
    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    /// 卸载页面并放掉 drift 的清理定时器。
    ///
    /// drift 取消查询订阅时会排一个 0ms 的markAsClosed 定时器；
    /// 若测试直接结束，flutter_test 会报「A Timer is still pending」。
    /// 先把页面换成空壳触发 dispose，再 pump 一帧让定时器执行完。
    Future<void> teardownTree(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }

    /// 推进到「数据已到位、入场动画已结束」。
    ///
    /// 不能用 pumpAndSettle：加载骨架的 shimmer 是 repeat() 无限动画，
    /// pumpAndSettle 会一直等不到静止帧而挂死。这里按固定时长推进，
    /// 覆盖 stream 首帧 + 卡片阶梯入场(最多 240ms) + 图表补间(520ms)。
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('空库：渲染页头与空状态，不抛异常', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await tester.pumpWidget(await host(database));
      await settle(tester);

      expect(find.text('统计'), findsOneWidget);
      expect(find.text('本期支出'), findsOneWidget);
      // 周期选择器五档齐全。
      for (final period in StatisticsPeriod.values) {
        expect(find.text(period.label), findsOneWidget);
      }
      // 无数据时给的是空状态文案，而不是空白或¥0.00 图表。
      // 三张图表卡各自给出针对性的空态文案，而不是共用一句「暂无数据」。
      expect(find.text('本期还没有支出'), findsOneWidget);
      expect(find.text('本期没有支出记录'), findsOneWidget);
      expect(find.text('近期没有可对比的支出'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('有账单：概览与分类排行显示真实金额', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final categories = await database.exportCategories();
      final expenseCategory = categories.firstWhere(
        (item) => item.kind == 0 && item.level == 1,
      );
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: 'stat-1',
          kind: 0,
          amountCents: 12345,
          categoryId: expenseCategory.id,
          accountingDate: today,
          occurredAt: now.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
        newImages: const [],
        removedImageIds: const {},
      );

      await tester.pumpWidget(await host(database));
      await settle(tester);

      // Hero 大数字不带 ¥（卡内已有「本期支出」语义）。
      expect(find.text('123.45'), findsOneWidget);
      // 分类排行里的金额带 ¥。
      expect(find.text('¥123.45'), findsWidgets);
      expect(find.text(expenseCategory.name), findsWidgets);
      // 唯一一个分类必然占 100%。
      expect(find.text('100%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('点排行行弹出明细面板：二级分类的账单归在一级分类下', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final categories = await database.exportCategories();
      // 挑一个二级分类：排行按一级分类聚合，明细必须把子分类的账单一起捞出来，
      // 否则从排行下钻会看到「合计 100 元、明细 0 笔」。
      final child = categories.firstWhere(
        (item) => item.kind == 0 && item.parentId != null,
      );
      final parent = categories.firstWhere((item) => item.id == child.parentId);
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: 'stat-child-1',
          kind: 0,
          amountCents: 5000,
          categoryId: child.id,
          accountingDate: today,
          occurredAt: now.millisecondsSinceEpoch,
          note: const Value('午餐外卖'),
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
        newImages: const [],
        removedImageIds: const {},
      );

      await tester.pumpWidget(await host(database));
      await settle(tester);

      // 排行只有一行，显示的是一级分类名。
      expect(find.byType(CategoryRankRow), findsOneWidget);
      expect(find.text(parent.name), findsWidgets);

      await tester.tap(find.byType(CategoryRankRow));
      await settle(tester);

      // 面板头给出区间与笔数，明细行给出二级分类名与备注。
      final rangeLabel = StatisticsWindow(
        period: StatisticsPeriod.month,
        anchor: now,
      ).rangeLabel;
      expect(find.text('$rangeLabel · 共 1 笔'), findsOneWidget);
      expect(find.text(child.name), findsOneWidget);
      expect(find.textContaining('午餐外卖'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('切到「收入」分类时给出对应空状态', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await tester.pumpWidget(await host(database));
      await settle(tester);

      await tester.tap(find.text('收入'));
      await settle(tester);

      expect(find.text('本期没有收入记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });
  });
}
