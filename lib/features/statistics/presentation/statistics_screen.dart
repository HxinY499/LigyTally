import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../features/ledger/application/providers.dart';
import '../../../shared/widgets/summary_band.dart';

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

  bool get _groupByMonth =>
      _period == StatisticsPeriod.year ||
      (_period == StatisticsPeriod.custom && _range.dayCount > 62);

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
            child: SegmentedButton<StatisticsPeriod>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: StatisticsPeriod.day, label: Text('日')),
                ButtonSegment(value: StatisticsPeriod.week, label: Text('周')),
                ButtonSegment(value: StatisticsPeriod.month, label: Text('月')),
                ButtonSegment(value: StatisticsPeriod.year, label: Text('年')),
                ButtonSegment(
                  value: StatisticsPeriod.custom,
                  label: Text('自定义'),
                ),
              ],
              selected: {_period},
              onSelectionChanged: (values) => _selectPeriod(values.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => _move(-1),
                  tooltip: '上一个周期',
                  icon: const Icon(Icons.chevron_left_rounded),
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
                IconButton(
                  onPressed: () => _move(1),
                  tooltip: '下一个周期',
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          StreamBuilder<LedgerSummary>(
            stream: database.watchSummary(range),
            builder: (context, snapshot) {
              final summary =
                  snapshot.data ??
                  const LedgerSummary(
                    incomeCents: 0,
                    expenseCents: 0,
                    entryCount: 0,
                  );
              return Column(
                children: [
                  SummaryBand(summary: summary, compact: true),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                    child: Row(
                      children: [
                        Text(
                          '${summary.entryCount} 笔记录',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: AppColors.muted),
                        ),
                        const Spacer(),
                        Text(
                          '日均支出 ${formatMoney(summary.expenseCents ~/ math.max(1, range.dayCount))}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '收支趋势',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 210,
                      child: StreamBuilder<List<TrendPoint>>(
                        stream: database.watchTrend(
                          range,
                          groupByMonth: _groupByMonth,
                        ),
                        builder: (context, snapshot) =>
                            _TrendChart(points: snapshot.data ?? const []),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _LegendDot(color: AppColors.expense, label: '支出'),
                        SizedBox(width: 20),
                        _LegendDot(color: AppColors.income, label: '收入'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '分类排行',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('支出')),
                    ButtonSegment(value: 1, label: Text('收入')),
                  ],
                  selected: {_categoryKind},
                  onSelectionChanged: (value) {
                    setState(() => _categoryKind = value.first);
                  },
                ),
              ],
            ),
          ),
          StreamBuilder<List<CategoryTotal>>(
            stream: database.watchCategoryTotals(range, _categoryKind),
            builder: (context, snapshot) {
              final totals = snapshot.data ?? const <CategoryTotal>[];
              if (totals.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: SizedBox(
                      height: 104,
                      child: Center(
                        child: Text(
                          '当前周期没有${_categoryKind == 0 ? '支出' : '收入'}记录',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.muted),
                        ),
                      ),
                    ),
                  ),
                );
              }
              final total = totals.fold<int>(
                0,
                (sum, item) => sum + item.totalCents,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (final item in totals)
                          _CategoryRow(item: item, totalCents: total),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});

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
    final maxY = math.max(10.0, maxCents / 100 * 1.18);
    final labelEvery = math.max(1, (points.length / 6).ceil());
    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(enabled: true),
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
              reservedSize: 28,
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
        barGroups: [
          for (var index = 0; index < points.length; index++)
            BarChartGroupData(
              x: index,
              barsSpace: 2,
              barRods: [
                BarChartRodData(
                  toY: points[index].expenseCents / 100,
                  width: points.length > 16 ? 4 : 8,
                  color: AppColors.expense,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
                BarChartRodData(
                  toY: points[index].incomeCents / 100,
                  width: points.length > 16 ? 4 : 8,
                  color: AppColors.income,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.item, required this.totalCents});

  final CategoryTotal item;
  final int totalCents;

  @override
  Widget build(BuildContext context) {
    final ratio = totalCents == 0 ? 0.0 : item.totalCents / totalCents;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              categoryIcon(item.iconKey),
              size: 20,
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
                    color: AppColors.accent,
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
