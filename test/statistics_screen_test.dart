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
import 'package:ligy_tally/features/statistics/application/stats_exclusion.dart';
import 'package:ligy_tally/features/statistics/presentation/stats_exclusion.dart';
import 'package:ligy_tally/features/statistics/presentation/statistics_screen.dart';
import 'package:ligy_tally/features/statistics/presentation/statistics_window.dart';
import 'package:ligy_tally/features/statistics/presentation/stats_card.dart';
import 'package:ligy_tally/features/statistics/presentation/stats_category.dart';
import 'package:ligy_tally/features/statistics/presentation/stats_charts.dart';
import 'package:ligy_tally/features/statistics/presentation/stats_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 统计页回归测试。
///
/// 这一屏图表多、状态多（加载 / 空 / 有数据），纯靠肉眼回归很容易漏。
/// 这里锁三件事：
/// 1. [StatisticsWindow] 的日期口径（区间、环比、对比区间、聚合粒度）
/// 2. 轴刻度金额的紧凑格式
/// 3. 页面在「空库」与「有账单」两种情况下都能渲染出关键文案，不抛异常
Future<StatsExclusion> _waitExclusionReady(ProviderContainer container) async {
  for (var i = 0; i < 40; i++) {
    final value = container.read(statsExclusionProvider);
    if (value.ready) return value;
    await Future<void>.delayed(Duration.zero);
  }
  fail('排除名单没有从 prefs 读完');
}

void main() {
  group('StatisticsWindow 日期口径', () {
    test('月视图：区间为自然月，上一周期为上个自然月', () {
      final window = StatisticsWindow(
        period: StatisticsPeriod.month,
        anchor: DateTime(2026, 8, 15),
        // 固定「今天」，让 8 月是一个已经走完的区间——否则
        // previousLabel 会随运行日期在「较上月 / 较上月同期」之间摇摆。
        today: DateTime(2026, 9, 3),
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

  group('StatisticsWindow 环比对等口径', () {
    test('进行中的月：对照区间截成等长前缀，文案点明同期', () {
      final window = StatisticsWindow(
        period: StatisticsPeriod.month,
        anchor: DateTime(2026, 8, 15),
        today: DateTime(2026, 8, 13),
      );

      expect(window.elapsedDayCount, 13);
      expect(window.isPartial, isTrue);
      // 完整 7 月是 31 天，对照只取前 13 天。
      expect(window.previousRange.dayCount, 31);
      expect(window.comparisonRange.start, DateTime(2026, 7));
      expect(window.comparisonRange.endExclusive, DateTime(2026, 7, 14));
      expect(window.comparisonRange.dayCount, 13);
      expect(window.previousLabel, '较上月同期');
    });

    test('已走完的月：对照区间就是完整的上一周期', () {
      final window = StatisticsWindow(
        period: StatisticsPeriod.month,
        anchor: DateTime(2026, 7, 15),
        today: DateTime(2026, 8, 13),
      );

      expect(window.elapsedDayCount, 31);
      expect(window.isPartial, isFalse);
      expect(window.comparisonRange.start, DateTime(2026, 6));
      expect(window.comparisonRange.endExclusive, DateTime(2026, 7));
      expect(window.previousLabel, '较上月');
    });

    test('等长前缀不越过上一周期末尾', () {
      // 3 月 29 日：29 天的前缀超出只有 28 天的 2 月，退化为整个 2 月。
      final window = StatisticsWindow(
        period: StatisticsPeriod.month,
        anchor: DateTime(2026, 3, 29),
        today: DateTime(2026, 3, 29),
      );

      expect(window.elapsedDayCount, 29);
      expect(window.comparisonRange.start, DateTime(2026, 2));
      expect(window.comparisonRange.endExclusive, DateTime(2026, 3));
    });

    test('整段落在未来的区间：已过 0 天', () {
      final window = StatisticsWindow(
        period: StatisticsPeriod.month,
        anchor: DateTime(2026, 12, 5),
        today: DateTime(2026, 8, 13),
      );

      expect(window.elapsedDayCount, 0);
      expect(window.includesToday, isFalse);
    });

    test('日视图不存在「同期」：当天区间本身就是走完的', () {
      final window = StatisticsWindow(
        period: StatisticsPeriod.day,
        anchor: DateTime(2026, 8, 13),
        today: DateTime(2026, 8, 13),
      );

      expect(window.elapsedDayCount, 1);
      expect(window.isPartial, isFalse);
      expect(window.previousLabel, '较昨日');
    });

    test('进行中的周：对照上周同样的天数', () {
      // 2026-08-13 是周四，本周为 08-10 ~ 08-17（开区间），已过 4 天。
      final window = StatisticsWindow(
        period: StatisticsPeriod.week,
        anchor: DateTime(2026, 8, 13),
        today: DateTime(2026, 8, 13),
      );

      expect(window.elapsedDayCount, 4);
      expect(window.comparisonRange.start, DateTime(2026, 8, 3));
      expect(window.comparisonRange.endExclusive, DateTime(2026, 8, 7));
      expect(window.previousLabel, '较上周同期');
    });

    test('对比卡标题随口径写成支出、收入或结余', () {
      final month = StatisticsWindow(
        period: StatisticsPeriod.month,
        anchor: DateTime(2026, 8, 15),
        today: DateTime(2026, 9, 3),
      );
      expect(month.comparisonTitle(0), '月支出对比');
      expect(month.comparisonTitle(1), '月收入对比');
      expect(month.comparisonTitle(2), '月结余对比');

      final year = StatisticsWindow(
        period: StatisticsPeriod.year,
        anchor: DateTime(2026, 8, 15),
      );
      expect(year.comparisonTitle(2), '年结余对比');
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
      // 结余柱可为负，符号跟金额走。
      expect(formatAxisMoney(-120000), '-1.2千');
      expect(formatAxisMoney(-88800), '-888');
    });
  });

  group('分类环比查询', () {
    test('两期金额按一级分类对照；子分类归入父级，另一侧缺席算减少', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final categories = await database.exportCategories();
      final child = categories.firstWhere(
        (item) => item.kind == 0 && item.parentId != null,
      );
      final root = categories.firstWhere((item) => item.id == child.parentId);
      final other = categories.firstWhere(
        (item) => item.kind == 0 && item.level == 1 && item.id != root.id,
      );
      final income = categories.firstWhere(
        (item) => item.kind == 1 && item.level == 1,
      );

      var seq = 0;
      Future<void> add({
        required String categoryId,
        required int cents,
        required String date,
        int kind = 0,
      }) {
        seq++;
        return database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: 'delta-$seq',
            kind: kind,
            amountCents: cents,
            categoryId: categoryId,
            accountingDate: date,
            occurredAt: seq,
            createdAt: seq,
            updatedAt: seq,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }

      // 本期：父级 100 元 + 子级 20 元，合计应归到父级的 120 元。
      await add(categoryId: root.id, cents: 10000, date: '2026-08-05');
      await add(categoryId: child.id, cents: 2000, date: '2026-08-06');
      // 上期：同一父级 60 元；另一分类 30 元且本期没有。
      await add(categoryId: root.id, cents: 6000, date: '2026-07-05');
      await add(categoryId: other.id, cents: 3000, date: '2026-07-06');
      // 两个区间之外，以及另一种收支类型，都不该进入结果。
      await add(categoryId: root.id, cents: 50000, date: '2026-06-01');
      await add(
        categoryId: income.id,
        cents: 90000,
        date: '2026-08-07',
        kind: 1,
      );

      final deltas = await database
          .watchCategoryDeltas(
            current: LedgerDateRange(DateTime(2026, 8), DateTime(2026, 9)),
            comparison: LedgerDateRange(DateTime(2026, 7), DateTime(2026, 8)),
            kind: 0,
          )
          .first;

      expect(deltas, hasLength(2));
      final rootDelta = deltas.firstWhere((item) => item.categoryId == root.id);
      expect(rootDelta.currentCents, 12000);
      expect(rootDelta.comparisonCents, 6000);
      expect(rootDelta.deltaCents, 6000);
      expect(rootDelta.ratio, 1.0);

      final otherDelta = deltas.firstWhere(
        (item) => item.categoryId == other.id,
      );
      expect(otherDelta.currentCents, 0);
      expect(otherDelta.comparisonCents, 3000);
      expect(otherDelta.deltaCents, -3000);
    });

    test('上期为 0 时算不出比例', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final categories = await database.exportCategories();
      final root = categories.firstWhere(
        (item) => item.kind == 0 && item.level == 1,
      );
      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: 'delta-new',
          kind: 0,
          amountCents: 8800,
          categoryId: root.id,
          accountingDate: '2026-08-05',
          occurredAt: 1,
          createdAt: 1,
          updatedAt: 1,
        ),
        newImages: const [],
        removedImageIds: const {},
      );

      final deltas = await database
          .watchCategoryDeltas(
            current: LedgerDateRange(DateTime(2026, 8), DateTime(2026, 9)),
            comparison: LedgerDateRange(DateTime(2026, 7), DateTime(2026, 8)),
            kind: 0,
          )
          .first;

      expect(deltas, hasLength(1));
      expect(deltas.single.comparisonCents, 0);
      expect(deltas.single.ratio, isNull);
    });
  });

  group('分类走势查询', () {
    test('按一级分类过滤，子分类计入父级，其他分类不计入', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final categories = await database.exportCategories();
      final child = categories.firstWhere(
        (item) => item.kind == 0 && item.parentId != null,
      );
      final root = categories.firstWhere((item) => item.id == child.parentId);
      final other = categories.firstWhere(
        (item) => item.kind == 0 && item.level == 1 && item.id != root.id,
      );

      var seq = 0;
      Future<void> add(String categoryId, int cents, String date) {
        seq++;
        return database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: 'span-$seq',
            kind: 0,
            amountCents: cents,
            categoryId: categoryId,
            accountingDate: date,
            occurredAt: seq,
            createdAt: seq,
            updatedAt: seq,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }

      await add(root.id, 10000, '2026-07-05');
      await add(child.id, 2000, '2026-08-05');
      await add(other.id, 90000, '2026-08-06');

      final spans = [
        PeriodSpan(
          range: LedgerDateRange(DateTime(2026, 7), DateTime(2026, 8)),
          label: '7月',
        ),
        PeriodSpan(
          range: LedgerDateRange(DateTime(2026, 8), DateTime(2026, 9)),
          label: '8月',
        ),
      ];

      final scoped = await database
          .watchPeriodBars(spans, rootCategoryId: root.id)
          .first;
      expect(scoped.map((bar) => bar.expenseCents), [10000, 2000]);

      // 不传分类时仍是全局口径，另一个分类的 900 元要算进来。
      final all = await database.watchPeriodBars(spans).first;
      expect(all.map((bar) => bar.expenseCents), [10000, 92000]);
    });
  });

  group('支出分类排除', () {
    Future<void> addTx(
      AppDatabase database, {
      required String id,
      required int kind,
      required int cents,
      required String categoryId,
      required String date,
    }) {
      return database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: id,
          kind: kind,
          amountCents: cents,
          categoryId: categoryId,
          accountingDate: date,
          occurredAt: 1,
          createdAt: 1,
          updatedAt: 1,
        ),
        newImages: const [],
        removedImageIds: const {},
      );
    }

    Future<AppDatabase> seedAugust() async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await addTx(
        database,
        id: 'ex-food',
        kind: 0,
        cents: 10000,
        categoryId: 'expense_food',
        date: '2026-08-05',
      );
      await addTx(
        database,
        id: 'ex-rent',
        kind: 0,
        cents: 20000,
        categoryId: 'expense_housing_rent',
        date: '2026-08-06',
      );
      await addTx(
        database,
        id: 'ex-housing',
        kind: 0,
        cents: 30000,
        categoryId: 'expense_housing',
        date: '2026-08-07',
      );
      await addTx(
        database,
        id: 'ex-salary',
        kind: 1,
        cents: 80000,
        categoryId: 'income_salary',
        date: '2026-08-08',
      );
      return database;
    }

    test('文案：1 类直出名称，3 类起收成「等 N 类」', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final categories = await database.exportCategories();
      final food = categories.firstWhere((item) => item.id == 'expense_food');
      final housing = categories.firstWhere(
        (item) => item.id == 'expense_housing',
      );
      final medical = categories.firstWhere(
        (item) => item.id == 'expense_medical',
      );
      expect(statsExclusionCaption(const []), '');
      expect(statsExclusionCaption([food]), '不含餐饮');
      expect(statsExclusionCaption([food, housing]), '不含餐饮、居住');
      expect(
        statsExclusionCaption([food, housing, medical]),
        '不含餐饮、居住等 3 类',
      );
    });

    test('排除居住：支出与笔数去掉该类及其二级，收入不动', () async {
      final database = await seedAugust();
      final august = LedgerDateRange(DateTime(2026, 8), DateTime(2026, 9));
      const excluded = {'expense_housing'};

      final full = await database.watchSummary(august).first;
      expect(full.expenseCents, 60000);
      expect(full.incomeCents, 80000);
      expect(full.entryCount, 4);
      expect(full.activeDayCount, 4);

      final filtered = await database
          .watchSummary(august, excludedCategoryIds: excluded)
          .first;
      expect(filtered.expenseCents, 10000);
      expect(filtered.incomeCents, 80000);
      expect(filtered.entryCount, 2);
      expect(filtered.activeDayCount, 2);
    });

    test('只排除房租：居住一级仍在，只拿掉该二级', () async {
      final database = await seedAugust();
      final august = LedgerDateRange(DateTime(2026, 8), DateTime(2026, 9));
      const excluded = {'expense_housing_rent'};

      final filtered = await database
          .watchSummary(august, excludedCategoryIds: excluded)
          .first;
      expect(filtered.expenseCents, 40000);
      expect(filtered.incomeCents, 80000);
      expect(filtered.entryCount, 3);

      final totals = await database
          .watchCategoryTotals(august, 0, excludedCategoryIds: excluded)
          .first;
      expect(
        totals.map((item) => (item.categoryId, item.totalCents)),
        [
          ('expense_housing', 30000),
          ('expense_food', 10000),
        ],
      );
    });

    test('点一级会清掉已勾的二级；点二级会把一级从名单拿掉', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final categories = await database.exportCategories();

      final onlyChild = toggleExcludedCategory(
        categories: categories,
        selected: const {},
        id: 'expense_housing_rent',
      );
      expect(onlyChild, {'expense_housing_rent'});

      final parentOverrides = toggleExcludedCategory(
        categories: categories,
        selected: onlyChild,
        id: 'expense_housing',
      );
      expect(parentOverrides, {'expense_housing'});

      final refine = toggleExcludedCategory(
        categories: categories,
        selected: parentOverrides,
        id: 'expense_housing_rent',
      );
      expect(refine, {'expense_housing_rent'});
    });

    test('分类构成与环比都拿掉被排除的一级分类', () async {
      final database = await seedAugust();
      final august = LedgerDateRange(DateTime(2026, 8), DateTime(2026, 9));
      final july = LedgerDateRange(DateTime(2026, 7), DateTime(2026, 8));
      const excluded = {'expense_housing'};

      final totals = await database
          .watchCategoryTotals(august, 0, excludedCategoryIds: excluded)
          .first;
      expect(totals.map((item) => item.categoryId), ['expense_food']);
      expect(totals.single.totalCents, 10000);

      final deltas = await database
          .watchCategoryDeltas(
            current: august,
            comparison: july,
            kind: 0,
            excludedCategoryIds: excluded,
          )
          .first;
      expect(deltas.map((item) => item.categoryId), ['expense_food']);
    });

    test('趋势与周期对比：排掉的是支出分类时，收入柱不受牵连', () async {
      final database = await seedAugust();
      final august = LedgerDateRange(DateTime(2026, 8), DateTime(2026, 9));
      const excluded = {'expense_housing'};

      final trend = await database
          .watchTrend(august, groupByMonth: false, excludedCategoryIds: excluded)
          .first;
      expect(
        trend.map((point) => (point.bucket, point.expenseCents, point.incomeCents)),
        [
          ('2026-08-05', 10000, 0),
          ('2026-08-08', 0, 80000),
        ],
      );

      final spans = [
        PeriodSpan(
          range: LedgerDateRange(DateTime(2026, 7), DateTime(2026, 8)),
          label: '7月',
        ),
        PeriodSpan(range: august, label: '8月'),
      ];
      final bars = await database
          .watchPeriodBars(spans, excludedCategoryIds: excluded)
          .first;
      expect(bars.map((bar) => bar.expenseCents), [0, 10000]);
      expect(bars.map((bar) => bar.incomeCents), [0, 80000]);
    });

    test('收入分类也能排：工资进名单后，收入与笔数一起减', () async {
      final database = await seedAugust();
      final august = LedgerDateRange(DateTime(2026, 8), DateTime(2026, 9));
      const excluded = {'income_salary'};

      final filtered = await database
          .watchSummary(august, excludedCategoryIds: excluded)
          .first;
      // 支出侧一分没动，收入整个清空——排除的是分类，不是某一侧。
      expect(filtered.expenseCents, 60000);
      expect(filtered.incomeCents, 0);
      expect(filtered.entryCount, 3);
      expect(filtered.activeDayCount, 3);

      final trend = await database
          .watchTrend(august, groupByMonth: false, excludedCategoryIds: excluded)
          .first;
      expect(trend.map((point) => point.bucket), [
        '2026-08-05',
        '2026-08-06',
        '2026-08-07',
      ]);

      final totals = await database
          .watchCategoryTotals(august, 1, excludedCategoryIds: excluded)
          .first;
      expect(totals, isEmpty);
    });

    test('排除名单写入 prefs 后，新的容器能读回来', () async {
      SharedPreferences.setMockInitialValues({});
      final first = ProviderContainer();
      await _waitExclusionReady(first);
      await first
          .read(statsExclusionProvider.notifier)
          .setIds({'expense_housing'});
      first.dispose();

      final second = ProviderContainer();
      addTearDown(second.dispose);
      final loaded = await _waitExclusionReady(second);
      expect(loaded.ids, {'expense_housing'});
    });
  });

  group('统计页渲染', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

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
    /// flutter_test 默认视口 800x600，而统计页五张卡纵向远超600；
    /// ListView 懒加载会导致靠下的「分类构成 / 分类变化 / 周期对比」
    /// 根本没被 build，断言自然找不到。拉高让整页一次性布局出来。
    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1000, 3000);
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

    /// 推进到「数据已到位、图表补间已结束」。
    ///
    /// 不能用 pumpAndSettle：加载骨架的 shimmer 是 repeat() 无限动画，
    /// pumpAndSettle 会一直等不到静止帧而挂死。这里按固定时长推进，
    /// 覆盖 stream 首帧 + 图表补间(520ms)。
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
      // 每张图表卡各自给出针对性的空态文案，而不是共用一句「暂无数据」。
      expect(find.text('本期还没有支出'), findsOneWidget);
      expect(find.text('本期没有支出记录'), findsOneWidget);
      expect(find.text('本期与对照期都没有支出'), findsOneWidget);
      expect(find.text('近期没有可对比的支出'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('趋势卡：可切换查看收入趋势', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final categories = await database.exportCategories();
      final incomeCategory = categories.firstWhere(
        (item) => item.kind == 1 && item.level == 1,
      );
      final now = DateTime.now();

      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: 'trend-income',
          kind: 1,
          amountCents: 88000,
          categoryId: incomeCategory.id,
          accountingDate: dateKey(now),
          occurredAt: now.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
        newImages: const [],
        removedImageIds: const {},
      );

      await tester.pumpWidget(await host(database));
      await settle(tester);

      expect(find.text('本期还没有支出'), findsOneWidget);

      final incomeChip = find.descendant(
        of: find.byKey(const ValueKey('trend-kind-toggle')),
        matching: find.text('收入'),
      );
      await tester.tap(incomeChip);
      await settle(tester);

      expect(find.text('本期还没有支出'), findsNothing);
      expect(find.text('880.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('周期对比卡可切到结余，柱上是收入减支出', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final categories = await database.exportCategories();
      final expenseCategory = categories.firstWhere(
        (item) => item.kind == 0 && item.level == 1,
      );
      final incomeCategory = categories.firstWhere(
        (item) => item.kind == 1 && item.level == 1,
      );
      final now = DateTime.now();
      final lastMonth = DateTime(now.year, now.month - 1, 1);

      Future<void> add(
        String id,
        int kind,
        String categoryId,
        int cents,
        DateTime day,
      ) {
        return database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: id,
            kind: kind,
            amountCents: cents,
            categoryId: categoryId,
            accountingDate: dateKey(day),
            occurredAt: day.millisecondsSinceEpoch,
            createdAt: day.millisecondsSinceEpoch,
            updatedAt: day.millisecondsSinceEpoch,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }

      await add('cmp-expense', 0, expenseCategory.id, 680000, now);
      await add('cmp-income', 1, incomeCategory.id, 1200000, now);
      await add('cmp-expense-prev', 0, expenseCategory.id, 680000, lastMonth);
      await add('cmp-income-prev', 1, incomeCategory.id, 1200000, lastMonth);

      await tester.pumpWidget(await host(database));
      await settle(tester);

      expect(find.text('月支出对比'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('comparison-kind-toggle')),
          matching: find.text('结余'),
        ),
      );
      await settle(tester);

      expect(find.text('月结余对比'), findsOneWidget);
      // 两期结余都是 5200 元，均值是 Text，柱顶金额画在 canvas 上测不到。
      expect(find.text('均值 5.2千'), findsOneWidget);
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

    testWidgets('排除居住后本期支出只剩其他分类，清除后恢复全量', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final now = DateTime.now();
      final today = dateKey(now);
      Future<void> add(String id, String categoryId, int cents) {
        return database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: id,
            kind: 0,
            amountCents: cents,
            categoryId: categoryId,
            accountingDate: today,
            occurredAt: now.millisecondsSinceEpoch,
            createdAt: now.millisecondsSinceEpoch,
            updatedAt: now.millisecondsSinceEpoch,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }

      await add('food-1', 'expense_food', 10000);
      await add('rent-1', 'expense_housing_rent', 50000);

      await tester.pumpWidget(await host(database));
      await settle(tester);

      expect(find.text('600.00'), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-exclusion-action')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('stats-exclusion-action')));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('category-expense_housing')));
      await tester.pump();
      await tester.tap(find.text('确定'));
      await settle(tester);

      expect(find.text('100.00'), findsWidgets);
      expect(find.text('不含居住'), findsWidgets);
      expect(find.text('600.00'), findsNothing);
      expect(find.text('¥500.00'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('stats-exclusion-action')));
      await settle(tester);
      await tester.tap(find.text('清除全部'));
      await tester.tap(find.text('确定'));
      await settle(tester);

      expect(find.text('600.00'), findsOneWidget);
      expect(find.text('不含居住'), findsNothing);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('排除浮层一次列出收支两组，收入分类也能排掉', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final now = DateTime.now();
      final today = dateKey(now);
      Future<void> add(String id, int kind, String categoryId, int cents) {
        return database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: id,
            kind: kind,
            amountCents: cents,
            categoryId: categoryId,
            accountingDate: today,
            occurredAt: now.millisecondsSinceEpoch,
            createdAt: now.millisecondsSinceEpoch,
            updatedAt: now.millisecondsSinceEpoch,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }

      await add('food-1', 0, 'expense_food', 10000);
      await add('salary-1', 1, 'income_salary', 80000);

      await tester.pumpWidget(await host(database));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('stats-exclusion-action')));
      await settle(tester);

      // 两侧同在一份列表里。收入那组在下面，要滑才看得见，但 Column 会把
      // 它一起建出来，所以这里不滚也能断言它在树上。
      expect(
        find.byKey(const ValueKey('category-expense_food')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('category-income_salary')),
        findsOneWidget,
      );

      final salary = find.byKey(const ValueKey('category-income_salary'));
      await tester.ensureVisible(salary);
      await tester.pump();
      await tester.tap(salary);
      await tester.pump();
      await tester.tap(find.text('确定'));
      await settle(tester);

      expect(find.text('不含工资'), findsWidgets);
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

    testWidgets('概览卡：标出本期有多少天没有任何记录', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final expenseCategory = (await database.exportCategories()).firstWhere(
        (item) => item.kind == 0 && item.level == 1,
      );
      final now = DateTime.now();
      // 只在本月 1 号记一笔，于是「有记录的天数」恒为 1，
      // 空白天数 = 本月已过天数 - 1，与运行日期无关地可推算。
      final firstOfMonth = DateTime(now.year, now.month, 1);
      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: 'coverage-1',
          kind: 0,
          amountCents: 3000,
          categoryId: expenseCategory.id,
          accountingDate: dateKey(firstOfMonth),
          occurredAt: firstOfMonth.millisecondsSinceEpoch,
          createdAt: firstOfMonth.millisecondsSinceEpoch,
          updatedAt: firstOfMonth.millisecondsSinceEpoch,
        ),
        newImages: const [],
        removedImageIds: const {},
      );

      await tester.pumpWidget(await host(database));
      await settle(tester);

      // 月视图下「已过天数」就是今天的日号；今天是月末最后一天时
      // 区间正好走完，文案从「已过」变成「跨」。
      final monthDays = DateTime(now.year, now.month + 1, 0).day;
      final expected = StringBuffer(
        '共 1 笔 · ${now.day < monthDays ? '已过' : '跨'} ${now.day} 天',
      );
      if (now.day > 1) expected.write(' · ${now.day - 1} 天无记录');
      expect(find.text(expected.toString()), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('下钻面板：给出该分类近 6 个周期的走势与均值', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final expenseCategory = (await database.exportCategories()).firstWhere(
        (item) => item.kind == 0 && item.level == 1,
      );
      final now = DateTime.now();
      final lastMonthFirst = DateTime(now.year, now.month - 1, 1);
      var seq = 0;
      Future<void> add(int cents, DateTime date) {
        seq++;
        return database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: 'trend-$seq',
            kind: 0,
            amountCents: cents,
            categoryId: expenseCategory.id,
            accountingDate: dateKey(date),
            occurredAt: date.millisecondsSinceEpoch,
            createdAt: date.millisecondsSinceEpoch,
            updatedAt: date.millisecondsSinceEpoch,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }

      await add(4000, now);
      await add(10000, lastMonthFirst);

      await tester.pumpWidget(await host(database));
      await settle(tester);

      await tester.tap(find.byType(CategoryRankRow));
      await settle(tester);

      // 面板里的范围说明与统计页「周期对比」卡共用一句文案，
      // 所以此时页面上有两处——两者本就该指同一组周期。
      expect(find.text('最近 6 个月'), findsNWidgets(2));
      // 只有两个月有金额，均值 =（100 + 40）/ 2。
      expect(find.text('均值 ¥70.00'), findsOneWidget);
      // 走势图本身要占到实际尺寸：曾经这里的图形宽度被压成 0，
      // 只剩均值文字，卡片看起来是空的。
      final chart = find.byType(CategoryTrendAreaChart);
      expect(chart, findsOneWidget);
      final chartSize = tester.getSize(chart);
      expect(chartSize.width, greaterThan(0));
      expect(chartSize.height, greaterThan(0));
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('分类变化卡：给出与上月同期的差额和幅度', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final categories = await database.exportCategories();
      final expenseCategory = categories.firstWhere(
        (item) => item.kind == 0 && item.level == 1,
      );
      final now = DateTime.now();
      // 上月 1 号：不论今天是几号，它都落在「上月同期」的前缀里。
      final lastMonthFirst = DateTime(now.year, now.month - 1, 1);

      Future<void> add(String id, int cents, DateTime date) {
        return database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: id,
            kind: 0,
            amountCents: cents,
            categoryId: expenseCategory.id,
            accountingDate: dateKey(date),
            occurredAt: date.millisecondsSinceEpoch,
            createdAt: date.millisecondsSinceEpoch,
            updatedAt: date.millisecondsSinceEpoch,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }

      await add('delta-current', 10000, now);
      await add('delta-previous', 4000, lastMonthFirst);

      await tester.pumpWidget(await host(database));
      await settle(tester);

      expect(find.text('分类变化'), findsOneWidget);
      expect(find.text('支出增加'), findsOneWidget);
      // 100 - 40 = +60 元，相对 40 元涨了 150%。
      expect(find.text('+¥60.00'), findsOneWidget);
      expect(find.text('¥40.00 → ¥100.00'), findsOneWidget);
      // 只有一个分类时，它的变化幅度必然等于概览卡的总额环比，
      // 所以「150%」应当同时出现在 Hero 徽章和这一行上——
      // 两处对不上就说明两张卡用了不同的对照区间。
      expect(find.text('150%'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('分类变化行下钻：本期与对照期都能在面板里看', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final expenseCategory = (await database.exportCategories()).firstWhere(
        (item) => item.kind == 0 && item.level == 1,
      );
      final now = DateTime.now();
      final lastMonthFirst = DateTime(now.year, now.month - 1, 1);

      Future<void> add(String id, int cents, DateTime date) {
        return database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: id,
            kind: 0,
            amountCents: cents,
            categoryId: expenseCategory.id,
            accountingDate: dateKey(date),
            occurredAt: date.millisecondsSinceEpoch,
            createdAt: date.millisecondsSinceEpoch,
            updatedAt: date.millisecondsSinceEpoch,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }

      await add('drill-current', 10000, now);
      await add('drill-previous', 4000, lastMonthFirst);

      await tester.pumpWidget(await host(database));
      await settle(tester);

      // 点的是变化行，不是上面那张分类构成卡的排行行。
      await tester.tap(find.text('¥40.00 → ¥100.00'));
      await settle(tester);

      // 「本期」在页面上不止一处：周期对比柱图的最后一根也这么标。
      // 断言收进切换器里，锁的是面板上那两档。
      final periodToggle = find.ancestor(
        of: find.text('对照期'),
        matching: find.byType(StatsPillToggle),
      );
      expect(periodToggle, findsOneWidget);
      final current = find.descendant(
        of: periodToggle,
        matching: find.text('本期'),
      );
      expect(current, findsOneWidget);

      // 轨道按内容收宽，不该被面板拉满整行——滑块是按半宽定位的，
      // 轨道一旦撑满，白色滑块就会盖出去大半屏。
      final toggleWidth = tester.getSize(periodToggle).width;
      final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
      expect(toggleWidth, lessThan(screenWidth * 0.6));
      // 两档等宽，滑块才盖得准：字数不同的两个标签不能各按内容排，
      // 否则两档中心相对轨道中心不对称。
      final currentCenter = tester.getCenter(current).dx;
      final comparisonCenter = tester.getCenter(find.text('对照期')).dx;
      final toggleCenter = tester.getCenter(periodToggle).dx;
      expect(
        (toggleCenter - currentCenter).abs(),
        closeTo((comparisonCenter - toggleCenter).abs(), 0.5),
      );
      // 默认停在本期：面板合计是本期那一笔。
      expect(find.text('¥100.00'), findsWidgets);

      // 切到对照期，不用回页顶换月份就能看到上期那一笔。
      await tester.tap(find.text('对照期'));
      await settle(tester);
      expect(find.text('¥40.00'), findsWidgets);

      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('概览卡：点击环比徽章展开对照说明', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final categories = await database.exportCategories();
      final expenseCategory = categories.firstWhere(
        (item) => item.kind == 0 && item.level == 1,
      );
      final now = DateTime.now();
      final lastMonthFirst = DateTime(now.year, now.month - 1, 1);

      Future<void> add(String id, int cents, DateTime date) {
        return database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: id,
            kind: 0,
            amountCents: cents,
            categoryId: expenseCategory.id,
            accountingDate: dateKey(date),
            occurredAt: date.millisecondsSinceEpoch,
            createdAt: date.millisecondsSinceEpoch,
            updatedAt: date.millisecondsSinceEpoch,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }

      await add('explain-current', 10000, now);
      await add('explain-previous', 4000, lastMonthFirst);

      await tester.pumpWidget(await host(database));
      await settle(tester);

      await tester.tap(find.text('150%').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('本期（'), findsOneWidget);
      expect(find.textContaining('对照（'), findsOneWidget);
      expect(find.textContaining('多出 ¥60.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('分类变化卡：超出 3 项时折叠，且能展开全部', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final roots = (await database.exportCategories())
          .where((item) => item.kind == 0 && item.level == 1)
          .take(4)
          .toList();
      expect(roots, hasLength(4));

      final now = DateTime.now();
      final lastMonthFirst = DateTime(now.year, now.month - 1, 1);
      var seq = 0;
      Future<void> add(String categoryId, int cents, DateTime date) {
        seq++;
        return database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: 'fold-$seq',
            kind: 0,
            amountCents: cents,
            categoryId: categoryId,
            accountingDate: dateKey(date),
            occurredAt: date.millisecondsSinceEpoch,
            createdAt: date.millisecondsSinceEpoch,
            updatedAt: date.millisecondsSinceEpoch,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }

      // 四个分类上期都是 10 元，本期分别 100 / 90 / 80 / 70 元，
      // 于是差额是 +90 / +80 / +70 / +60，第四名在折叠态下应当看不到。
      const currentCents = [10000, 9000, 8000, 7000];
      for (var i = 0; i < roots.length; i++) {
        await add(roots[i].id, currentCents[i], now);
        await add(roots[i].id, 1000, lastMonthFirst);
      }

      await tester.pumpWidget(await host(database));
      await settle(tester);

      // 折叠态：只显示前三名，但必须告知一共有几项变化。
      expect(find.text('+¥90.00'), findsOneWidget);
      expect(find.text('+¥70.00'), findsOneWidget);
      expect(find.text('+¥60.00'), findsNothing);
      expect(find.text('展开全部 4 项变化'), findsOneWidget);

      await tester.tap(find.text('展开全部 4 项变化'));
      await settle(tester);

      expect(find.text('+¥60.00'), findsOneWidget);
      expect(find.text('收起'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('窄屏真机宽度下整页不横向溢出', (tester) async {
      // 其余用例都用 1000 宽的视口，横向溢出在那种宽度下永远暴露不出来。
      // 这里用真机宽度 390，高度仍拉高以便一次布局出全部卡片
      //（横向溢出只取决于宽度）。
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final roots = (await database.exportCategories())
          .where((item) => item.kind == 0 && item.level == 1)
          .take(7)
          .toList();
      final now = DateTime.now();
      final lastMonthFirst = DateTime(now.year, now.month - 1, 1);
      final thisMonthFirst = DateTime(now.year, now.month, 1);
      var seq = 0;
      Future<void> add(String categoryId, int cents, DateTime date) {
        seq++;
        return database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: 'narrow-$seq',
            kind: 0,
            amountCents: cents,
            categoryId: categoryId,
            accountingDate: dateKey(date),
            occurredAt: date.millisecondsSinceEpoch + seq,
            createdAt: date.millisecondsSinceEpoch,
            updatedAt: date.millisecondsSinceEpoch,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }

      // 金额取到百万级，让 Hero 大数字、排行金额、环比差额都是长串；
      // 只在本月 1 号与今天记账，概览卡底部那行才会凑齐三段
      //（笔数 · 已过天数 · 空白天数）——它正是最容易顶破宽度的一行。
      for (final root in roots) {
        await add(root.id, 123456789, now);
        await add(root.id, 98765432, thisMonthFirst);
        await add(root.id, 87654321, lastMonthFirst);
      }

      await tester.pumpWidget(await host(database));
      await settle(tester);

      expect(find.text('统计'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });

    testWidgets('切到「收入」分类时给出对应空状态', (tester) async {
      useTallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await tester.pumpWidget(await host(database));
      await settle(tester);

      // 支出/收入切换器不止一处（趋势、分类构成、周期对比），
      // 必须按卡片限定范围，否则 find.text('收入') 会撞上多个。
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('分类构成'),
            matching: find.byType(StatsCard),
          ),
          matching: find.text('收入'),
        ),
      );
      await settle(tester);

      expect(find.text('本期没有收入记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await teardownTree(tester);
    });
  });
}
