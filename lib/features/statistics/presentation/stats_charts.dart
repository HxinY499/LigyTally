import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/ledger_date.dart';
import 'stats_design.dart';

/// 支出趋势折线图。
///
/// 相比原实现的改动都围绕「别让人猜数值」和「别糊成一团」：
/// - 补左侧纵轴刻度（原来完全没有轴标签，只能靠点按tooltip 猜量级）
/// - 网格线改虚线 + 更淡的颜色，从「格子纸」退回背景
/// - 描边改渐变 + 下方加面积填充，单条细线在浅色卡片上太单薄
/// - 横轴标签按可用宽度动态抽稀，并首尾对齐，杜绝文字重叠
/// - 触摸时画竖向指示线 + 实心圆点，tooltip 带日期与金额两行
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({super.key, required this.points});

  final List<TrendPoint> points;

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
    final maxCents = points.fold<int>(
      0,
      (value, point) => math.max(value, point.expenseCents),
    );
    // 顶部留 22% 余量：曲线峰值贴到卡片上沿会显得被「切掉」。
    // maxCents 为 0（区间内全是收入）时给一个最小刻度，避免除零。
    final maxY = maxCents == 0 ? 100.0 : maxCents / 100 * 1.22;
    final step = maxY / 3;

    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].expenseCents / 100),
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
              getDrawingHorizontalLine: (_) => const FlLine(
                color: StatsTokens.gridLine,
                strokeWidth: 1,
                dashArray: [4, 4],
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
                      style: StatsTokens.axisLabel,
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
                        style: StatsTokens.axisLabel,
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
                    const FlLine(
                      color: StatsTokens.primary,
                      strokeWidth: 1.5,
                      dashArray: [3, 3],
                    ),
                    FlDotData(
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                            radius: 5,
                            color: Colors.white,
                            strokeWidth: 3,
                            strokeColor: StatsTokens.primary,
                          ),
                    ),
                  ),
              ],
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => StatsTokens.tooltip,
                tooltipBorderRadius: BorderRadius.circular(10),
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
                      formatMoney((spot.y * 100).round()),
                      StatsTokens.tooltipText,
                      children: [
                        TextSpan(
                          text:
                              '\n${_tooltipLabel(points[spot.x.round().clamp(0, points.length - 1)].bucket)}',
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                            color: Color(0xB3FFFFFF),
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
                gradient: StatsTokens.trendLineGradient,
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
                        color: Colors.white,
                        strokeWidth: 2,
                        strokeColor: StatsTokens.primary,
                      ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: StatsTokens.trendAreaGradient,
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

/// 「周期支出对比」柱状图：当期高亮，附均值参考线。
///
/// 相比原实现：
/// - 每根柱加浅色背景轨道，金额为 0 时也有位置感，不再「凭空消失」
/// - 当期柱用渐变 + 更大圆角，与历史柱形成明确主次
/// - 加均值虚线，一眼看出本期高于还是低于近期平均
/// - 柱顶直接标金额（紧凑格式），不必点按也能读数
class PeriodBarChart extends StatelessWidget {
  const PeriodBarChart({super.key, required this.bars});

  final List<PeriodBar> bars;

  @override
  Widget build(BuildContext context) {
    final maxCents = bars.fold<int>(
      0,
      (value, bar) => math.max(value, bar.expenseCents),
    );
    // 顶部留 28% 给柱顶金额标签，否则最高柱的标签会被裁掉。
    final maxY = maxCents == 0 ? 100.0 : maxCents / 100 * 1.28;

    // 均值只统计有支出的周期：把「还没记账的月份」算进分母会把均值拉得毫无意义。
    final nonZero = bars.where((bar) => bar.expenseCents > 0).toList();
    final averageCents = nonZero.isEmpty
        ? 0
        : nonZero.fold<int>(0, (sum, bar) => sum + bar.expenseCents) ~/
              nonZero.length;

    final lastIndex = bars.length - 1;

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxY / 3,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: StatsTokens.gridLine,
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        // 均值参考线：只在有两个以上有效周期时才画，
        // 单个周期的「均值」等于它自己，画出来是噪音。
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (nonZero.length >= 2)
              HorizontalLine(
                y: averageCents / 100,
                color: StatsTokens.textFaint.withValues(alpha: 0.55),
                strokeWidth: 1,
                dashArray: const [5, 5],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(right: 2, bottom: 3),
                  style: StatsTokens.axisLabel,
                  labelResolver: (_) => '均值 ${formatAxisMoney(averageCents)}',
                ),
              ),
          ],
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => StatsTokens.tooltip,
            tooltipBorderRadius: BorderRadius.circular(10),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final bar = bars[groupIndex.clamp(0, lastIndex)];
              return BarTooltipItem(
                formatMoney(bar.expenseCents),
                StatsTokens.tooltipText,
                children: [
                  TextSpan(
                    text: '\n${groupIndex == lastIndex ? '本期' : bar.label}',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      fontWeight: FontWeight.w400,
                      color: Color(0xB3FFFFFF),
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
              reservedSize: 38,
              interval: maxY / 3,
              maxIncluded: false,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  formatAxisMoney((value * 100).round()),
                  textAlign: TextAlign.right,
                  style: StatsTokens.axisLabel,
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
                        ? StatsTokens.axisLabelActive
                        : StatsTokens.axisLabel,
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
                  width: 18,
                  gradient: i == lastIndex
                      ? StatsTokens.barActiveGradient
                      : null,
                  color: i == lastIndex ? null : StatsTokens.barIdle,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  // 背景轨道铺满整个 Y 轴，给每个周期一个「槽位」。
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: StatsTokens.barTrack,
                  ),
                  label: BarChartRodLabel(
                    // 金额为 0 时不标（标个「0」纯属噪音）。
                    show: bars[i].expenseCents > 0,
                    text: formatAxisMoney(bars[i].expenseCents),
                    style: i == lastIndex
                        ? StatsTokens.axisLabelActive
                        : StatsTokens.axisLabel,
                    offset: const Offset(0, -6),
                  ),
                ),
              ],
            ),
        ],
      ),
      duration: StatsTokens.durChart,
      curve: StatsTokens.curveEnter,
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
                  if (!event.isInterestedForInteractions) return;
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
                    borderSide: const BorderSide(
                      color: StatsTokens.surface,
                      width: 1.5,
                    ),
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
                    style: StatsTokens.captionSection.copyWith(
                      fontWeight: FontWeight.w500,
                      color: selected == null
                          ? StatsTokens.textFaint
                          : selected.color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(centerCents),
                      style: StatsTokens.donutCenterAmount,
                    ),
                  ),
                  if (centerRatio != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '占比 ${centerRatio.toStringAsFixed(1)}%',
                      style: StatsTokens.rowMeta,
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
