import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/ledger_date.dart';
import 'stats_design.dart';

/// 收支趋势折线图。
///
/// [kind] 为 0 支出 / 1 收入。相比原实现的改动都围绕「别让人猜数值」和
/// 「别糊成一团」：
/// - 补左侧纵轴刻度（原来完全没有轴标签，只能靠点按tooltip 猜量级）
/// - 网格线改虚线 + 更淡的颜色，从「格子纸」退回背景
/// - 描边改渐变 + 下方加面积填充，单条细线在浅色卡片上太单薄
/// - 横轴标签按可用宽度动态抽稀，并首尾对齐，杜绝文字重叠
/// - 触摸时画竖向指示线 + 实心圆点，tooltip 带日期与金额两行
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({super.key, required this.points, this.kind = 0});

  final List<TrendPoint> points;

  /// 0 = 支出，1 = 收入。
  final int kind;

  int _valueOf(TrendPoint point) =>
      kind == 0 ? point.expenseCents : point.incomeCents;

  String get _kindLabel => kind == 0 ? '支出' : '收入';

  /// 把 `2026-08-09` / `2026-08` 转成轴标签。
  ///
  /// 粒度直接由 bucket 长度判断（7 = 按月，10 = 按天），
  /// 不额外传 groupByMonth 标志——数据自己已经说明了粒度，
  /// 多传一个参数只会多一个「和数据不一致」的出错机会。
  String _axisLabel(String bucket) {
    if (bucket.length == 7) return '${int.parse(bucket.substring(5))}月';
    final month = bucket.substring(5, 7);
    final day = bucket.substring(8, 10);
    return '${int.parse(month)}/${int.parse(day)}';
  }

  /// tooltip 里的完整日期。
  String _tooltipLabel(String bucket) {
    if (bucket.length == 7) {
      return '${bucket.substring(0, 4)} 年 ${int.parse(bucket.substring(5))} 月';
    }
    return '${int.parse(bucket.substring(5, 7))} 月 ${int.parse(bucket.substring(8, 10))} 日';
  }

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final lineColor = kind == 0 ? stats.expense : stats.income;
    final lineGradient = LinearGradient(
      colors: [
        Color.lerp(lineColor, Colors.white, 0.28)!,
        lineColor,
      ],
    );
    final areaGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        lineColor.withValues(alpha: 0.22),
        lineColor.withValues(alpha: 0),
      ],
    );
    final maxCents = points.fold<int>(
      0,
      (value, point) => math.max(value, _valueOf(point)),
    );
    // 顶部留 22% 余量：曲线峰值贴到卡片上沿会显得被「切掉」。
    // maxCents 为 0 时给一个最小刻度，避免除零。
    final maxY = maxCents == 0 ? 100.0 : maxCents / 100 * 1.22;
    final step = maxY / 3;

    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), _valueOf(points[i]) / 100),
    ];

    // 单点区间（例如「日」视图只有一天）无法构成折线，
    // 左右各补一个同值虚拟点，让它渲染成一条短横线而不是空白。
    final singlePoint = spots.length == 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 按可用宽度算能放几个标签：每个标签预留 44px。
        final slots = math.max(2, (constraints.maxWidth / 44).floor());
        final labelEvery = math.max(1, (points.length / slots).ceil());

        return LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            minX: singlePoint ? -0.5 : 0,
            maxX: singlePoint ? 0.5 : (points.length - 1).toDouble(),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: step,
              getDrawingHorizontalLine: (_) => FlLine(
                color: stats.gridLine,
                strokeWidth: 1,
                dashArray: const [4, 4],
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 38,
                  interval: step,
                  // 顶部刻度紧贴卡片上沿，省掉它更干净。
                  maxIncluded: false,
                  getTitlesWidget: (value, meta) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      formatAxisMoney((value * 100).round()),
                      textAlign: TextAlign.right,
                      style: stats.axisLabel,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index < 0 || index >= points.length) {
                      return const SizedBox.shrink();
                    }
                    // 抽稀规则：从末位（当期）倒着数，保证「最新」一定有标签，
                    // 正着数会让最右侧的关键数据点反而没有刻度。
                    final fromEnd = points.length - 1 - index;
                    if (fromEnd % labelEvery != 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _axisLabel(points[index].bucket),
                        style: stats.axisLabel,
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchSpotThreshold: 24,
              getTouchedSpotIndicator: (barData, indexes) => [
                for (final _ in indexes)
                  TouchedSpotIndicatorData(
                    FlLine(
                      color: lineColor,
                      strokeWidth: 1.5,
                      dashArray: const [3, 3],
                    ),
                    FlDotData(
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                            radius: 5,
                            // 圆点填的是卡面色而不是纯白：它要看起来像从卡片上
                            // 「挖」出来的空心点，深色卡上填白会比数据本身更抢眼。
                            color: stats.surface,
                            strokeWidth: 3,
                            strokeColor: lineColor,
                          ),
                    ),
                  ),
              ],
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => stats.tooltip,
                tooltipBorderRadius: BorderRadius.circular(stats.radiusChip),
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                maxContentWidth: 180,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (touched) => [
                  for (final spot in touched)
                    LineTooltipItem(
                      '$_kindLabel ${formatMoney((spot.y * 100).round())}',
                      stats.tooltipText,
                      children: [
                        TextSpan(
                          text:
                              '\n${_tooltipLabel(points[spot.x.round().clamp(0, points.length - 1)].bucket)}',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                            color: stats.onTooltip.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: singlePoint
                    ? [
                        FlSpot(-0.5, spots.first.y),
                        spots.first,
                        FlSpot(0.5, spots.first.y),
                      ]
                    : spots,
                isCurved: true,
                curveSmoothness: 0.28,
                preventCurveOverShooting: true,
                gradient: lineGradient,
                barWidth: 2.5,
                isStrokeCapRound: true,
                isStrokeJoinRound: true,
                // 数据点少时显式画点：只有3-5 个点的折线不画点会显得很空，
                // 点多时（>14）画点则会连成一串糊在一起，所以按数量切换。
                dotData: FlDotData(
                  show: points.length <= 14,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: 3,
                        color: stats.surface,
                        strokeWidth: 2,
                        strokeColor: lineColor,
                      ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: areaGradient,
                ),
              ),
            ],
          ),
          duration: StatsTokens.durChart,
          curve: StatsTokens.curveEnter,
        );
      },
    );
  }
}

/// 分类下钻面板里的近期走势：折线 + 面积填充，附均值虚线。
///
/// 不复用 [TrendLineChart]：那张卡有 176 的高度和左侧纵轴，这里嵌在明细列表
/// 上方只有约 80 可用高度，纵轴刻度和网格线必须让位给数据本身——需要读准确
/// 数值时点一下有 tooltip。
///
/// 描边与填充用**分类色**而不是 [StatsTokens.trendLineGradient] 的主色：
/// 这张图和面板头的色点、环形图里那一片讲的是同一个分类，换成主色就断了。
class CategoryTrendAreaChart extends StatelessWidget {
  const CategoryTrendAreaChart({
    super.key,
    required this.bars,
    required this.kind,
    required this.color,
    required this.averageCents,
  });

  final List<PeriodBar> bars;

  /// 0 = 支出，1 = 收入。
  final int kind;

  /// 分类色，与面板头、环形图扇区同一支。
  final Color color;

  /// 均值虚线的位置（分）。<= 0 时不画，口径（只算有金额的周期）由调用方决定。
  final int averageCents;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final values = [
      for (final bar in bars) kind == 0 ? bar.expenseCents : bar.incomeCents,
    ];
    final maxCents = values.fold<int>(0, math.max);
    // 顶部留 18% 余量：峰值贴到顶端会显得被截断。
    // 全为 0 时给一个最小刻度，避免除零，曲线贴底也仍然画得出来。
    final maxY = maxCents == 0 ? 100.0 : maxCents / 100 * 1.18;
    final lastIndex = values.length - 1;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        minX: 0,
        maxX: lastIndex.toDouble(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        // 均值线在这里替代网格线：唯一需要的横向参照就是「本期比常态高还是低」。
        // 数值已在标题行写明，线上不再重复标签。
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (averageCents > 0)
              HorizontalLine(
                y: averageCents / 100,
                color: stats.textFaint.withValues(alpha: 0.45),
                strokeWidth: 1,
                dashArray: const [4, 4],
              ),
          ],
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
              reservedSize: 20,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= bars.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    bars[index].label,
                    style: index == lastIndex
                        ? stats.axisLabelActive
                        : stats.axisLabel,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchSpotThreshold: 24,
          getTouchedSpotIndicator: (barData, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                FlLine(color: color, strokeWidth: 1.5, dashArray: const [3, 3]),
                FlDotData(
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: 4.5,
                        color: stats.surface,
                        strokeWidth: 3,
                        strokeColor: color,
                      ),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => stats.tooltip,
            tooltipBorderRadius: BorderRadius.circular(stats.radiusChip),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touched) => [
              for (final spot in touched)
                LineTooltipItem(
                  formatMoney((spot.y * 100).round()),
                  stats.tooltipText,
                  children: [
                    TextSpan(
                      text:
                          '\n${bars[spot.x.round().clamp(0, lastIndex)].label}',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        fontWeight: FontWeight.w400,
                        color: stats.onTooltip.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i] / 100),
            ],
            isCurved: true,
            curveSmoothness: 0.28,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2,
            isStrokeCapRound: true,
            isStrokeJoinRound: true,
            // 六个点全画：点少时不画点，「哪个月是 0」会被曲线糊过去。
            // 末位（当期）画大一档实心点，与柱状图高亮当期的规则一致。
            dotData: FlDotData(
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: index == lastIndex ? 3.5 : 2.5,
                color: index == lastIndex ? color : stats.surface,
                strokeWidth: 2,
                strokeColor: color,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.28),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: StatsTokens.durChart,
      curve: StatsTokens.curveEnter,
    );
  }
}

/// 「周期对比」柱状图：当期高亮，附均值参考线。
///
/// 相比原实现：
/// - 每根柱加浅色背景轨道，金额为 0 时也有位置感，不再「凭空消失」
/// - 当期柱用渐变 + 更大圆角，与历史柱形成明确主次
/// - 加均值虚线，一眼看出本期高于还是低于近期平均
/// - 柱顶金额标在柱外上方（fl_chart 的 offset.dy 为正才是往上抬）
/// - 均值数字不绑在虚线上：靠近均值的柱顶金额会和它抢同一条高度
///
/// 柱色不随 [kind] 变成收入绿或结余发散色：这里的配色表达的是
/// 「当期 vs 历史」的主次，换成语义色会和「高亮渐变=当期」这条规则打架。
/// 算的是哪一边由卡片标题与切换器交代。
class PeriodBarChart extends StatelessWidget {
  const PeriodBarChart({super.key, required this.bars, this.kind = 0});

  final List<PeriodBar> bars;

  /// 0 支出 / 1 收入 / 2 结余（收入 − 支出，可负）。
  final int kind;

  int _valueOf(PeriodBar bar) => switch (kind) {
    1 => bar.incomeCents,
    2 => bar.incomeCents - bar.expenseCents,
    _ => bar.expenseCents,
  };

  bool _countsInAverage(PeriodBar bar) {
    if (kind == 2) return bar.expenseCents > 0 || bar.incomeCents > 0;
    return _valueOf(bar) > 0;
  }

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final maxCents = bars.fold<int>(
      0,
      (value, bar) => math.max(value, _valueOf(bar)),
    );
    final minCents = bars.fold<int>(
      0,
      (value, bar) => math.min(value, _valueOf(bar)),
    );
    // 柱端金额画在柱外，两端都要留空，不能和柱体或均值线抢同一条高度。
    final maxY = maxCents > 0
        ? maxCents / 100 * 1.38
        : (minCents < 0 ? 0.0 : 100.0);
    final minY = minCents < 0 ? minCents / 100 * 1.38 : 0.0;
    final axisSpan = maxY - minY;
    final axisInterval = axisSpan <= 0 ? 1.0 : axisSpan / 3;

    // 支出/收入：空月不算进均值。结余：有记账的月都算，包括净额为零或为负。
    final counted = bars.where(_countsInAverage).toList();
    final averageCents = counted.isEmpty
        ? 0
        : counted.fold<int>(0, (sum, bar) => sum + _valueOf(bar)) ~/
              counted.length;

    final lastIndex = bars.length - 1;
    final showAverage = counted.length >= 2;

    return Column(
      children: [
        if (showAverage)
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '均值 ${formatAxisMoney(averageCents)}',
              style: stats.axisLabel,
            ),
          ),
        Expanded(
          child: BarChart(
            BarChartData(
              minY: minY,
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: axisInterval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: stats.gridLine,
                  strokeWidth: 1,
                  dashArray: const [4, 4],
                ),
              ),
              borderData: FlBorderData(show: false),
              // 只画虚线，不在线上写字：3 月接近均值时，线上的「均值 xx」
              // 会和柱顶金额叠成一团。数字改到图外右上角。
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (minY < 0)
                    HorizontalLine(
                      y: 0,
                      color: stats.textFaint.withValues(alpha: 0.4),
                      strokeWidth: 1,
                    ),
                  if (showAverage)
                    HorizontalLine(
                      y: averageCents / 100,
                      color: stats.textFaint.withValues(alpha: 0.55),
                      strokeWidth: 1,
                      dashArray: const [5, 5],
                    ),
                ],
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => stats.tooltip,
                  tooltipBorderRadius: BorderRadius.circular(stats.radiusChip),
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final bar = bars[groupIndex.clamp(0, lastIndex)];
                    return BarTooltipItem(
                      formatMoney(_valueOf(bar)),
                      stats.tooltipText,
                      children: [
                        TextSpan(
                          text:
                              '\n${groupIndex == lastIndex ? '本期' : bar.label}',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                            color: stats.onTooltip.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: minY < 0 ? 44 : 38,
                    interval: axisInterval,
                    maxIncluded: false,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        formatAxisMoney((value * 100).round()),
                        textAlign: TextAlign.right,
                        style: stats.axisLabel,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= bars.length) {
                        return const SizedBox.shrink();
                      }
                      final isLast = index == lastIndex;
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          isLast ? '本期' : bars[index].label,
                          style: isLast
                              ? stats.axisLabelActive
                              : stats.axisLabel,
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
                        toY: _valueOf(bars[i]) / 100,
                        width: 18,
                        gradient: i == lastIndex
                            ? stats.barActiveGradient
                            : null,
                        color: i == lastIndex ? null : stats.barIdle,
                        borderRadius: _valueOf(bars[i]) >= 0
                            ? const BorderRadius.vertical(
                                top: Radius.circular(6),
                              )
                            : const BorderRadius.vertical(
                                bottom: Radius.circular(6),
                              ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          fromY: minY,
                          toY: maxY,
                          color: stats.barTrack,
                        ),
                        label: BarChartRodLabel(
                          show: _valueOf(bars[i]) != 0,
                          text: formatAxisMoney(_valueOf(bars[i])),
                          style: i == lastIndex
                              ? stats.axisLabelActive
                              : stats.axisLabel,
                          // fl_chart：正 dy 把字从柱端往外推。负柱同样适用。
                          offset: const Offset(0, 8),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            duration: StatsTokens.durChart,
            curve: StatsTokens.curveEnter,
          ),
        ),
      ],
    );
  }
}

/// 分类环形图的一片扇区。
class CategorySlice {
  const CategorySlice({
    required this.label,
    required this.cents,
    required this.color,
  });

  final String label;
  final int cents;
  final Color color;
}

/// 分类构成环形图：可点选扇区，中心联动显示选中项。
///
/// 相比原实现：
/// - 扇区加圆角与白色描边，相邻色块之间有呼吸，不再糊成一整圈
/// - 支持点选：选中扇区外扩、其余降透明度，中心同步显示该分类名与金额
/// - 中心默认显示总额，选中后显示分项，避免另开一块区域放选中信息
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    super.key,
    required this.slices,
    required this.totalCents,
    required this.centerLabel,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<CategorySlice> slices;
  final int totalCents;

  /// 未选中任何扇区时中心的标题（如「总支出」）。
  final String centerLabel;

  /// 当前选中扇区下标；-1 表示未选中。
  final int selectedIndex;

  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final hasSelection = selectedIndex >= 0 && selectedIndex < slices.length;
    final selected = hasSelection ? slices[selectedIndex] : null;
    final centerTitle = selected?.label ?? centerLabel;
    final centerCents = selected?.cents ?? totalCents;
    final centerRatio = totalCents == 0 || selected == null
        ? null
        : selected.cents / totalCents * 100;

    return SizedBox(
      height: 172,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              // 3px 间隙 + 白描边：两层「留白」叠加，色块边界最清晰。
              sectionsSpace: 3,
              centerSpaceRadius: 52,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  // 只认抬手：按下会连发 FlPanDown + FlTapDown，选中立刻被
                  // 再切回去，体感就是「点了没反应，长按才高亮」。
                  if (event is! FlTapUpEvent) return;
                  final index = response?.touchedSection?.touchedSectionIndex;
                  if (index == null || index < 0) return;
                  // 再点一次已选中的扇区 = 取消选中，回到总额视图。
                  onSelect(index == selectedIndex ? -1 : index);
                },
              ),
              sections: [
                for (var i = 0; i < slices.length; i++)
                  PieChartSectionData(
                    value: slices[i].cents.toDouble(),
                    // 未选中项降透明度而不是换灰色：保留色相，
                    // 用户仍能把它和图例对上。
                    color: hasSelection && i != selectedIndex
                        ? slices[i].color.withValues(alpha: 0.32)
                        : slices[i].color,
                    radius: i == selectedIndex ? 26 : 20,
                    showTitle: false,
                    borderSide: BorderSide(color: stats.surface, width: 1.5),
                  ),
              ],
            ),
            duration: StatsTokens.durTap,
            curve: StatsTokens.curveEnter,
          ),
          // 中心信息：点击也能取消选中，命中区域比扇区更好按。
          GestureDetector(
            onTap: hasSelection ? () => onSelect(-1) : null,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 92,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    centerTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: stats.captionSection.copyWith(
                      fontWeight: FontWeight.w500,
                      color: selected == null
                          ? stats.textFaint
                          : selected.color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(centerCents),
                      style: stats.donutCenterAmount,
                    ),
                  ),
                  if (centerRatio != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '占比 ${centerRatio.toStringAsFixed(1)}%',
                      style: stats.rowMeta,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
