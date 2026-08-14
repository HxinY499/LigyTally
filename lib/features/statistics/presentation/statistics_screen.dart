import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/preferences/money_grouped.dart';
import '../../../features/ledger/application/providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'stats_card.dart';
import 'stats_category.dart';
import 'stats_category_delta.dart';
import 'stats_charts.dart';
import 'stats_design.dart';
import 'stats_overview.dart';
import 'stats_states.dart';
import 'statistics_window.dart';

/// 收支统计页。
///
/// 结构：页头 → 周期选择器 → 概览 Hero 卡 → 趋势 → 分类构成 → 周期对比。
/// 页面本身只做「组合 + 状态派发」，日期语义在 [StatisticsWindow]，
/// 样式令牌在 [StatsTokens]，图表在 stats_charts.dart，
/// 加载/空/异常态在 stats_states.dart。
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  StatisticsWindow _window = StatisticsWindow.now();
  int _categoryKind = 0;

  void _shift(int direction) {
    setState(() => _window = _window.shifted(direction));
  }

  /// 选周期。自定义模式需要先弹日期区间选择器，用户取消则不改变当前状态。
  Future<void> _selectPeriod(StatisticsPeriod value) async {
    if (value != StatisticsPeriod.custom) {
      setState(() => _window = _window.copyWith(period: value));
      return;
    }
    await _pickCustomRange();
  }

  Future<void> _pickCustomRange() async {
    final selected = await showAppDateRangePicker(
      context,
      initial: _window.range,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _window = StatisticsWindow(
        period: StatisticsPeriod.custom,
        anchor: _window.anchor,
        customRange: selected,
      );
    });
  }

  /// 中间区间文案的点击：仅自定义模式可改区间。
  void _onRangeTap() {
    if (_window.period == StatisticsPeriod.custom) _pickCustomRange();
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    final grouped = ref.watch(moneyGroupedProvider);
    final range = _window.range;

    return SafeArea(
      bottom: false,
      child: AppPageHeader(
        title: '统计',
        body: ListView(
          // 导航栏已贴底固定、本页无 FAB，底部只留收尾留白。
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                StatsTokens.gutter,
                4,
                StatsTokens.gutter,
                0,
              ),
              child: StatsPeriodSelector(
                selected: _window.period,
                onChanged: _selectPeriod,
              ),
            ),

            // ---------------------------------------------- 概览 Hero 卡
            _Slot(
              index: 0,
              child: _OverviewSlot(
                window: _window,
                grouped: grouped,
                onShift: _shift,
                onPickRange: _onRangeTap,
              ),
            ),

            // ---------------------------------------------- 支出趋势
            _Slot(
              index: 1,
              child: StatsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatsSectionHeader(
                      title: _window.trendTitle,
                      caption: _window.trendCaption,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 176,
                      child: StatsStreamBuilder<List<TrendPoint>>(
                        stream: database.watchTrend(
                          range,
                          groupByMonth: _window.groupByMonth,
                        ),
                        loading: const StatsChartSkeleton(height: 176),
                        builder: (context, points) {
                          // 区间内只有收入、没有任何支出时，趋势图画出来
                          // 是一条贴底的直线，不如直接说明。
                          final hasExpense = points.any(
                            (point) => point.expenseCents > 0,
                          );
                          if (!hasExpense) {
                            return const StatsEmpty(
                              title: '本期还没有支出',
                              body: '记一笔支出后，这里会显示金额随时间的变化趋势',
                              height: 176,
                            );
                          }
                          return TrendLineChart(points: points);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ---------------------------------------------- 分类构成
            _Slot(
              index: 2,
              child: StatsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatsSectionHeader(
                      title: '分类构成',
                      caption: '点扇区看占比，点排行看明细',
                      trailing: _KindToggle(
                        selected: _categoryKind,
                        onChanged: (value) =>
                            setState(() => _categoryKind = value),
                      ),
                    ),
                    const SizedBox(height: 14),
                    StatsStreamBuilder<List<CategoryTotal>>(
                      stream: database.watchCategoryTotals(
                        range,
                        _categoryKind,
                      ),
                      loading: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: StatsDonutSkeleton(),
                      ),
                      builder: (context, totals) {
                        if (totals.isEmpty) {
                          return StatsEmpty(
                            icon: FLucideIcons.chartPie,
                            title: '本期没有${_categoryKind == 0 ? '支出' : '收入'}记录',
                            body: '换一个时间范围，或先记录一笔账单',
                          );
                        }
                        return CategoryComposition(
                          // kind 变化时强制重建，让内部选中态跟着复位。
                          key: ValueKey(_categoryKind),
                          totals: totals,
                          kind: _categoryKind,
                          grouped: grouped,
                          range: range,
                          rangeLabel: _window.rangeLabel,
                          trendSpans: _window.comparisonSpans,
                          trendCaption: _window.comparisonCaption,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ---------------------------------------------- 分类环比
            _Slot(
              index: 3,
              child: StatsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatsSectionHeader(
                      title: '分类变化',
                      caption: '${_window.previousLabel}的增减',
                    ),
                    const SizedBox(height: 14),
                    StatsStreamBuilder<List<CategoryDelta>>(
                      // 跟随分类构成卡的支出/收入切换：两张卡讲的是同一批分类，
                      // 各带一个切换开关会让「哪张卡现在是收入」变得要猜。
                      stream: database.watchCategoryDeltas(
                        current: range,
                        comparison: _window.comparisonRange,
                        kind: _categoryKind,
                      ),
                      loading: const StatsDeltaSkeleton(),
                      errorHeight: 148,
                      builder: (context, deltas) => CategoryDeltaList(
                        deltas: deltas,
                        kind: _categoryKind,
                        grouped: grouped,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ---------------------------------------------- 周期对比
            _Slot(
              index: 4,
              child: StatsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatsSectionHeader(
                      title: _window.comparisonTitle,
                      caption: _window.comparisonCaption,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 196,
                      child: StatsStreamBuilder<List<PeriodBar>>(
                        stream: database.watchPeriodBars(
                          _window.comparisonSpans,
                        ),
                        loading: const StatsChartSkeleton(height: 196, bars: 6),
                        builder: (context, bars) {
                          final hasData = bars.any(
                            (bar) => bar.expenseCents > 0,
                          );
                          if (!hasData) {
                            return const StatsEmpty(
                              icon: FLucideIcons.chartColumn,
                              title: '近期没有可对比的支出',
                              body: '积累几个周期的记录后即可看到横向对比',
                              height: 196,
                            );
                          }
                          return PeriodBarChart(bars: bars);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片槽位：统一左右边距、卡间距与入场动画。
class _Slot extends StatelessWidget {
  const _Slot({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        StatsTokens.gutter,
        StatsTokens.gapCard,
        StatsTokens.gutter,
        0,
      ),
      child: StatsEntrance(index: index, child: child),
    );
  }
}

/// 概览卡的数据装配：把本期与上期两条 Stream 合到一处。
///
/// 用两层 StreamBuilder 而不是 combineLatest：上期数据只影响一个环比徽章，
/// 它慢一帧到达时徽章缺席即可，不该拖住主数字的首帧。
class _OverviewSlot extends ConsumerWidget {
  const _OverviewSlot({
    required this.window,
    required this.grouped,
    required this.onShift,
    required this.onPickRange,
  });

  final StatisticsWindow window;
  final bool grouped;
  final ValueChanged<int> onShift;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(databaseProvider);
    return StreamBuilder<LedgerSummary>(
      stream: database.watchSummary(window.range),
      builder: (context, currentSnap) {
        return StreamBuilder<LedgerSummary>(
          // 对照区间而不是完整上一周期：当期没走完时两者长度不同，
          // 直接比会让徽章长期误报。口径见 [StatisticsWindow.comparisonRange]。
          stream: database.watchSummary(window.comparisonRange),
          builder: (context, prevSnap) {
            return StatsOverviewCard(
              window: window,
              current: currentSnap.data,
              previous: prevSnap.data,
              grouped: grouped,
              onShift: onShift,
              onPickRange: onPickRange,
            );
          },
        );
      },
    );
  }
}

/// 支出 / 收入切换：小号胶囊分段器，放在卡片标题右侧。
///
/// 单独实现而不复用 [AppSegmentedControl]：后者是 44px 高的表单级按钮，
/// 放进卡片标题行会把标题挤下去。这里需要 28px 的紧凑版。
class _KindToggle extends StatelessWidget {
  const _KindToggle({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: stats.fillMuted,
        borderRadius: BorderRadius.circular(StatsTokens.radiusPill),
      ),
      child: Row(
        children: [
          _KindChip(
            label: '支出',
            active: selected == 0,
            onTap: () => onChanged(0),
          ),
          _KindChip(
            label: '收入',
            active: selected == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: StatsTokens.durTap,
        curve: StatsTokens.curveEnter,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? stats.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(StatsTokens.radiusPill),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x14101828),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? stats.primary : stats.textMuted,
          ),
        ),
      ),
    );
  }
}
