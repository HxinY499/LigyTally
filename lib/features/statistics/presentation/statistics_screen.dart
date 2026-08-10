import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../features/ledger/application/providers.dart';
import '../../../shared/widgets/app_widgets.dart';

enum StatisticsPeriod { day, week, month, year, custom }

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  StatisticsPeriod _period = StatisticsPeriod.month;
  DateTime _anchor = DateTime.now();
  LedgerDateRange? _customRange;
  int _categoryKind = 0;

  LedgerDateRange get _range => switch (_period) {
    StatisticsPeriod.day => dayRange(_anchor),
    StatisticsPeriod.week => weekRange(_anchor),
    StatisticsPeriod.month => monthRange(_anchor),
    StatisticsPeriod.year => yearRange(_anchor),
    StatisticsPeriod.custom => _customRange ?? monthRange(_anchor),
  };

  /// 上一周期区间，用于环比（本期 vs 上期）。
  LedgerDateRange get _previousRange => switch (_period) {
    StatisticsPeriod.day => dayRange(_anchor.subtract(const Duration(days: 1))),
    StatisticsPeriod.week =>
      weekRange(_anchor.subtract(const Duration(days: 7))),
    StatisticsPeriod.month => monthRange(
      DateTime(_anchor.year, _anchor.month - 1, 1),
    ),
    StatisticsPeriod.year => yearRange(DateTime(_anchor.year - 1, 1, 1)),
    StatisticsPeriod.custom => () {
      final range = _range;
      final shift = Duration(days: math.max(1, range.dayCount));
      return LedgerDateRange(
        range.start.subtract(shift),
        range.endExclusive.subtract(shift),
      );
    }(),
  };

  /// 「周期支出对比」的近 6 个周期（升序，末位为当前周期）。
  List<PeriodSpan> get _comparisonSpans {
    const count = 6;
    final spans = <PeriodSpan>[];
    for (var offset = count - 1; offset >= 0; offset--) {
      final (range, label) = _spanAt(offset);
      spans.add(PeriodSpan(range: range, label: label));
    }
    return spans;
  }

  /// offset=0 表示当前周期，offset=1 表示上一周期，以此类推。
  (LedgerDateRange, String) _spanAt(int offset) {
    switch (_period) {
      case StatisticsPeriod.day:
        final day = _anchor.subtract(Duration(days: offset));
        return (dayRange(day), '${day.month}/${day.day}');
      case StatisticsPeriod.week:
        final anchor = _anchor.subtract(Duration(days: 7 * offset));
        final range = weekRange(anchor);
        return (range, '${range.start.month}/${range.start.day}');
      case StatisticsPeriod.year:
        final year = _anchor.year - offset;
        return (yearRange(DateTime(year, 1, 1)), '$year');
      case StatisticsPeriod.month:
      case StatisticsPeriod.custom:
        final month = DateTime(_anchor.year, _anchor.month - offset, 1);
        return (monthRange(month), '${month.month}月');
    }
  }

  bool get _groupByMonth =>
      _period == StatisticsPeriod.year ||
      (_period == StatisticsPeriod.custom && _range.dayCount > 62);

  String get _comparisonTitle => switch (_period) {
    StatisticsPeriod.day => '日支出对比',
    StatisticsPeriod.week => '周支出对比',
    StatisticsPeriod.year => '年支出对比',
    _ => '月支出对比',
  };

  String get _trendTitle => switch (_period) {
    StatisticsPeriod.day => '当日支出趋势',
    StatisticsPeriod.week => '本周支出趋势',
    StatisticsPeriod.year => '年度支出趋势',
    _ => '本期支出趋势',
  };

  String get _rangeLabel {
    final range = _range;
    return switch (_period) {
      StatisticsPeriod.day =>
        '${range.start.year} 年 ${range.start.month} 月 ${range.start.day} 日',
      StatisticsPeriod.week =>
        '${range.start.month}/${range.start.day} - ${range.endExclusive.subtract(const Duration(days: 1)).month}/${range.endExclusive.subtract(const Duration(days: 1)).day}',
      StatisticsPeriod.month => formatMonth(range.start),
      StatisticsPeriod.year => '${range.start.year} 年',
      StatisticsPeriod.custom =>
        '${dateKey(range.start)} - ${dateKey(range.endExclusive.subtract(const Duration(days: 1)))}',
    };
  }

  void _move(int direction) {
    setState(() {
      switch (_period) {
        case StatisticsPeriod.day:
          _anchor = _anchor.add(Duration(days: direction));
        case StatisticsPeriod.week:
          _anchor = _anchor.add(Duration(days: 7 * direction));
        case StatisticsPeriod.month:
          _anchor = DateTime(_anchor.year, _anchor.month + direction, 1);
        case StatisticsPeriod.year:
          _anchor = DateTime(_anchor.year + direction, 1, 1);
        case StatisticsPeriod.custom:
          final range = _range;
          final shift = Duration(days: range.dayCount * direction);
          _customRange = LedgerDateRange(
            range.start.add(shift),
            range.endExclusive.add(shift),
          );
      }
    });
  }

  Future<void> _selectPeriod(StatisticsPeriod value) async {
    if (value != StatisticsPeriod.custom) {
      setState(() => _period = value);
      return;
    }
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: _range.start,
        end: _range.endExclusive.subtract(const Duration(days: 1)),
      ),
    );
    if (selected != null) {
      setState(() {
        _period = StatisticsPeriod.custom;
        _customRange = LedgerDateRange(
          dateOnly(selected.start),
          dateOnly(selected.end).add(const Duration(days: 1)),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    final range = _range;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Text(
              '收支统计',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            child: AppSegmentedControl<StatisticsPeriod>(
              expanded: false,
              selected: _period,
              onChanged: _selectPeriod,
              segments: const [
                AppSegment(value: StatisticsPeriod.day, label: '日'),
                AppSegment(value: StatisticsPeriod.week, label: '周'),
                AppSegment(value: StatisticsPeriod.month, label: '月'),
                AppSegment(value: StatisticsPeriod.year, label: '年'),
                AppSegment(value: StatisticsPeriod.custom, label: '自定义'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIconButton(
                  onPress: () => _move(-1),
                  icon: const Icon(FLucideIcons.chevronLeft),
                ),
                SizedBox(
                  width: 210,
                  child: Text(
                    _rangeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                AppIconButton(
                  onPress: () => _move(1),
                  icon: const Icon(FLucideIcons.chevronRight),
                ),
              ],
            ),
          ),

          // 本期支出/收入 大数字对比（含与上一周期的环比）。
          _OverviewCard(
            currentStream: database.watchSummary(range),
            previousStream: database.watchSummary(_previousRange),
            dayCount: range.dayCount,
          ),

          // 支出趋势 折线图。
          _SectionCard(
            title: _trendTitle,
            child: SizedBox(
              height: 200,
              child: StreamBuilder<List<TrendPoint>>(
                stream: database.watchTrend(range, groupByMonth: _groupByMonth),
                builder: (context, snapshot) =>
                    _TrendLineChart(points: snapshot.data ?? const []),
              ),
            ),
          ),

          // 支出分类构成 环形图 + 排行。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: AppCard(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '分类构成',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        AppSegmentedControl<int>(
                          expanded: false,
                          selected: _categoryKind,
                          onChanged: (value) =>
                              setState(() => _categoryKind = value),
                          segments: const [
                            AppSegment(value: 0, label: '支出'),
                            AppSegment(value: 1, label: '收入'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<List<CategoryTotal>>(
                      stream: database.watchCategoryTotals(range, _categoryKind),
                      builder: (context, snapshot) => _CategoryComposition(
                        totals: snapshot.data ?? const <CategoryTotal>[],
                        kind: _categoryKind,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 周期支出对比 柱状图（末位高亮）。
          _SectionCard(
            title: _comparisonTitle,
            child: SizedBox(
              height: 190,
              child: StreamBuilder<List<PeriodBar>>(
                stream: database.watchPeriodBars(_comparisonSpans),
                builder: (context, snapshot) =>
                    _PeriodBarChart(bars: snapshot.data ?? const []),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用"标题 + 内容"卡片，统一各图表区块的外观。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 本期支出 / 本期收入 大数字对比块，底部各自带与上一周期的环比。
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.currentStream,
    required this.previousStream,
    required this.dayCount,
  });

  final Stream<LedgerSummary> currentStream;
  final Stream<LedgerSummary> previousStream;
  final int dayCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: StreamBuilder<LedgerSummary>(
            stream: currentStream,
            builder: (context, currentSnap) {
              final current =
                  currentSnap.data ??
                  const LedgerSummary(
                    incomeCents: 0,
                    expenseCents: 0,
                    entryCount: 0,
                  );
              return StreamBuilder<LedgerSummary>(
                stream: previousStream,
                builder: (context, prevSnap) {
                  final previous =
                      prevSnap.data ??
                      const LedgerSummary(
                        incomeCents: 0,
                        expenseCents: 0,
                        entryCount: 0,
                      );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _BigStat(
                              label: '本期支出',
                              cents: current.expenseCents,
                              accent: AppColors.expense,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            color: AppColors.line,
                          ),
                          Expanded(
                            child: _BigStat(
                              label: '本期收入',
                              cents: current.incomeCents,
                              accent: AppColors.income,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _DeltaStat(
                              label: '较上期支出',
                              current: current.expenseCents,
                              previous: previous.expenseCents,
                              upIsBad: true,
                            ),
                          ),
                          Expanded(
                            child: _DeltaStat(
                              label: '较上期收入',
                              current: current.incomeCents,
                              previous: previous.incomeCents,
                              upIsBad: false,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${current.entryCount} 笔记录 · 日均支出 ${formatMoney(current.expenseCents ~/ math.max(1, dayCount))}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.label,
    required this.cents,
    required this.accent,
  });

  final String label;
  final int cents;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatMoney(cents),
            maxLines: 1,
            style: TextStyle(
              fontSize: 26,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// 环比小指标：显示相对上一周期的涨跌百分比与箭头。
class _DeltaStat extends StatelessWidget {
  const _DeltaStat({
    required this.label,
    required this.current,
    required this.previous,
    required this.upIsBad,
  });

  final String label;
  final int current;
  final int previous;

  /// 支出上涨=偏负面（红），收入上涨=偏正面（绿）。
  final bool upIsBad;

  @override
  Widget build(BuildContext context) {
    final hasBase = previous != 0;
    final diff = current - previous;
    final up = diff > 0;
    final flat = diff == 0;
    final percent = hasBase ? (diff.abs() / previous * 100) : null;

    final Color color;
    if (flat) {
      color = AppColors.muted;
    } else if (up) {
      color = upIsBad ? AppColors.expense : AppColors.income;
    } else {
      color = upIsBad ? AppColors.income : AppColors.expense;
    }

    final String text;
    if (!hasBase) {
      text = current == 0 ? '—' : '新增';
    } else if (flat) {
      text = '持平';
    } else {
      text = '${up ? '↑' : '↓'} ${percent!.toStringAsFixed(1)}%';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 3),
        Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// 支出趋势折线图：支出用红线填充，收入用绿线，峰值标注气泡。
class _TrendLineChart extends StatelessWidget {
  const _TrendLineChart({required this.points});

  final List<TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
        child: Text(
          '暂无趋势数据',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
      );
    }

    final maxCents = points.fold<int>(
      0,
      (value, point) =>
          math.max(value, math.max(point.expenseCents, point.incomeCents)),
    );
    final maxY = math.max(10.0, maxCents / 100 * 1.28);
    final labelEvery = math.max(1, (points.length / 6).ceil());

    // 峰值气泡：定位到支出最大的那个点。
    var peakIndex = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].expenseCents > points[peakIndex].expenseCents) {
        peakIndex = i;
      }
    }
    final showPeak = points[peakIndex].expenseCents > 0;

    List<FlSpot> spots(int Function(TrendPoint) selector) => [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), selector(points[i]) / 100),
    ];

    LineChartBarData barData(Color color, List<FlSpot> data, bool fill) {
      return LineChartBarData(
        spots: data,
        isCurved: true,
        curveSmoothness: 0.28,
        color: color,
        barWidth: 2.4,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: points.length <= 16,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 2.6,
            color: color,
            strokeWidth: 0,
          ),
        ),
        belowBarData: BarAreaData(
          show: fill,
          color: color.withValues(alpha: 0.10),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 ||
                    index >= points.length ||
                    index % labelEvery != 0) {
                  return const SizedBox.shrink();
                }
                final bucket = points[index].bucket;
                final label = bucket.length == 7
                    ? '${int.parse(bucket.substring(5))}月'
                    : bucket.substring(5).replaceFirst('-', '/');
                return Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(label, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.ink,
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    formatMoney((s.y * 100).round()),
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        showingTooltipIndicators: showPeak
            ? [
                ShowingTooltipIndicators([
                  LineBarSpot(
                    barData(
                      AppColors.expense,
                      spots((p) => p.expenseCents),
                      true,
                    ),
                    1,
                    FlSpot(
                      peakIndex.toDouble(),
                      points[peakIndex].expenseCents / 100,
                    ),
                  ),
                ]),
              ]
            : const [],
        lineBarsData: [
          barData(AppColors.income, spots((p) => p.incomeCents), false),
          barData(AppColors.expense, spots((p) => p.expenseCents), true),
        ],
      ),
    );
  }
}

/// 分类构成：左侧环形甜甜圈（中心显示总额），右侧图例，下方排行列表。
class _CategoryComposition extends StatelessWidget {
  const _CategoryComposition({required this.totals, required this.kind});

  final List<CategoryTotal> totals;
  final int kind;

  // 甜甜圈配色：主蓝系为主，尾部渐次变浅/换色，与截图观感一致。
  static const _palette = [
    Color(0xFF5190F2),
    Color(0xFF7FB0F6),
    Color(0xFFE5A62E),
    Color(0xFF64B5A4),
    Color(0xFFB39DDB),
    Color(0xFFBFD3EC),
  ];

  Color _colorAt(int index) => _palette[index % _palette.length];

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) {
      return SizedBox(
        height: 96,
        child: Center(
          child: Text(
            '当前周期没有${kind == 0 ? '支出' : '收入'}记录',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ),
      );
    }

    final total = totals.fold<int>(0, (sum, item) => sum + item.totalCents);
    // 环形只画前若干项，其余合并为"其他"，避免细碎扇区。
    const maxSlices = 5;
    final slices = <_Slice>[];
    if (totals.length <= maxSlices) {
      for (var i = 0; i < totals.length; i++) {
        slices.add(
          _Slice(
            label: totals[i].name,
            cents: totals[i].totalCents,
            color: _colorAt(i),
          ),
        );
      }
    } else {
      for (var i = 0; i < maxSlices; i++) {
        slices.add(
          _Slice(
            label: totals[i].name,
            cents: totals[i].totalCents,
            color: _colorAt(i),
          ),
        );
      }
      final rest = totals
          .skip(maxSlices)
          .fold<int>(0, (sum, item) => sum + item.totalCents);
      slices.add(
        _Slice(label: '其他', cents: rest, color: _colorAt(maxSlices)),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 172,
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 46,
                        startDegreeOffset: -90,
                        sections: [
                          for (final slice in slices)
                            PieChartSectionData(
                              value: slice.cents.toDouble(),
                              color: slice.color,
                              radius: 20,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          kind == 0 ? '总支出' : '总收入',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatMoney(total),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final slice in slices)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: slice.color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                slice.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              total == 0
                                  ? '0%'
                                  : '${(slice.cents / total * 100).toStringAsFixed(0)}%',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 22),
        for (var i = 0; i < totals.length; i++)
          _CategoryRow(
            rank: i + 1,
            item: totals[i],
            totalCents: total,
            color: _colorAt(i),
          ),
      ],
    );
  }
}

class _Slice {
  const _Slice({
    required this.label,
    required this.cents,
    required this.color,
  });

  final String label;
  final int cents;
  final Color color;
}

/// 周期支出对比柱状图：末位（当前周期）高亮。
class _PeriodBarChart extends StatelessWidget {
  const _PeriodBarChart({required this.bars});

  final List<PeriodBar> bars;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return Center(
        child: Text(
          '暂无对比数据',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
      );
    }

    final maxCents = bars.fold<int>(
      0,
      (value, bar) => math.max(value, bar.expenseCents),
    );
    final maxY = math.max(10.0, maxCents / 100 * 1.25);

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.ink,
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              formatMoney((rod.toY * 100).round()),
              const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= bars.length) {
                  return const SizedBox.shrink();
                }
                final isLast = index == bars.length - 1;
                return Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    isLast ? '本期' : bars[index].label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isLast ? FontWeight.w700 : FontWeight.w400,
                      color: isLast ? AppColors.primary : AppColors.ink,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < bars.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: bars[i].expenseCents / 100,
                  width: 16,
                  color: i == bars.length - 1
                      ? AppColors.primary
                      : AppColors.primarySoft,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.rank,
    required this.item,
    required this.totalCents,
    required this.color,
  });

  final int rank;
  final CategoryTotal item;
  final int totalCents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = totalCents == 0 ? 0.0 : item.totalCents / totalCents;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              categoryIcon(item.iconKey),
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(item.totalCents),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 5,
                    backgroundColor: AppColors.line,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(ratio * 100).toStringAsFixed(1)}% · ${item.entryCount} 笔',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
