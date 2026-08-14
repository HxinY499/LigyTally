import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../statistics/presentation/stats_design.dart';
import '../application/providers.dart';

/// 月历弹窗：按星期排布的当月每日收支。
///
/// 它和统计页的「本期支出趋势」用同一批按天聚合的数据，但回答的问题不同——
/// 折线读的是走势形状，答不上「上周六花了多少」；月历按星期对齐，能定位到
/// 具体某天，也能看出周内规律和哪几天压根没记账。所以这里刻意只做两件事：
/// **按星期铺开的密度视图** + **跳到某一天**，不做任何趋势/占比分析，
/// 那些是统计页的职责。
///
/// 返回用户点选的日期（当月内的任意一天，含没有记录的天）；
/// 点遮罩或「关闭」返回 null。调用方决定点中之后做什么。
Future<DateTime?> showMonthCalendar(
  BuildContext context, {
  required DateTime month,
}) {
  return showGeneralDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: context.colors.barrier,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => _MonthCalendarDialog(month: month),
    // 与月份选择器同一条入场：两个弹窗都从摘要条附近唤起，动效不该各走一套。
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 一格的高度。日期数字 18 + 金额区 24 + 上下各 2 的格间距。
const double _kCellHeight = 46;

/// 日期数字占的固定高度。金额区同样固定，两者都不随「这天有没有收入」
/// 变化——否则同一行里日期数字会上下错位，整张表看着在抖。
const double _kDateLineHeight = 18;
const double _kAmountAreaHeight = 24;

class _MonthCalendarDialog extends ConsumerWidget {
  const _MonthCalendarDialog({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final database = ref.watch(databaseProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          color: colors.surface,
          borderRadius: context.radii.sheetAll,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatMonth(month),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '点某天定位到当天账单，没记录的天直接记一笔',
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
                const SizedBox(height: 16),
                const _WeekdayHeader(),
                const SizedBox(height: 4),
                // 只订阅按天聚合，不订阅整月明细：这里要的是每格两个数字，
                // 拉全量账单再在内存里分组等于把首页的活儿重做一遍。
                StreamBuilder<List<TrendPoint>>(
                  stream: database.watchTrend(
                    monthRange(month),
                    groupByMonth: false,
                  ),
                  builder: (context, snapshot) {
                    // 首帧没数据时先把网格铺出来（日期格永远画得出），
                    // 金额随流到达后填进去，避免整块区域先塌一下再长出来。
                    final points = snapshot.data ?? const <TrendPoint>[];
                    return _CalendarGrid(
                      month: month,
                      byDay: {for (final point in points) point.bucket: point},
                    );
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.ink,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: context.radii.sheetAll,
                      ),
                    ),
                    child: const Text(
                      '关闭',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 星期表头。周一起始，与 [weekRange] 和 [formatWeekday] 同一套顺序。
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const _labels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++)
          Expanded(
            child: Center(
              child: Text(
                _labels[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  // 周末一档更淡的处理会让「周末花得多」这类判断更难，
                  // 所以七天同色，只靠列位置区分。
                  color: colors.inactive,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({required this.month, required this.byDay});

  final DateTime month;

  /// 日期 key（yyyy-MM-dd）→ 当天聚合。只有至少有一笔记录的天才在表里，
  /// 所以「在不在表里」就是「这天有没有记录」。
  final Map<String, TrendPoint> byDay;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final dayCount = monthRange(month).dayCount;
    // 首行左侧要空出的格数：周一起始，所以周一空 0 格、周日空 6 格。
    final leading = first.weekday - DateTime.monday;
    final rowCount = ((leading + dayCount) / 7).ceil();

    // 热力上限取当月单日支出峰值：跨月比较不是这张表的职责，
    // 用固定阈值反而会让低消费月份整月一片白。
    final maxExpense = byDay.values.fold<int>(
      0,
      (value, point) => math.max(value, point.expenseCents),
    );
    final today = dateOnly(DateTime.now());

    return Column(
      children: [
        for (var row = 0; row < rowCount; row++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: _buildCell(
                    dayNumber: row * 7 + column - leading + 1,
                    dayCount: dayCount,
                    maxExpense: maxExpense,
                    today: today,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCell({
    required int dayNumber,
    required int dayCount,
    required int maxExpense,
    required DateTime today,
  }) {
    if (dayNumber < 1 || dayNumber > dayCount) {
      return const SizedBox(height: _kCellHeight);
    }
    final day = DateTime(month.year, month.month, dayNumber);
    final point = byDay[dateKey(day)];
    return _DayCell(
      day: day,
      expenseCents: point?.expenseCents ?? 0,
      incomeCents: point?.incomeCents ?? 0,
      maxExpenseCents: maxExpense,
      isToday: day == today,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.expenseCents,
    required this.incomeCents,
    required this.maxExpenseCents,
    required this.isToday,
  });

  final DateTime day;
  final int expenseCents;
  final int incomeCents;

  /// 当月单日支出峰值，用来算热力深浅。
  final int maxExpenseCents;

  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: _kCellHeight,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          // 底色三层各管一件事，互不抢：热力=支出多少，描边=今天，
          // 水波=按下反馈。所以今天用描边而不是实底。
          color: _heatColor(colors),
          shape: RoundedRectangleBorder(
            borderRadius: context.radii.chipAll,
            side: isToday
                ? BorderSide(color: colors.primary, width: 1.2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).pop(day),
            highlightColor: colors.pressed,
            splashColor: colors.ripple,
            child: Column(
              children: [
                SizedBox(
                  height: _kDateLineHeight,
                  child: Center(
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                        color: isToday ? colors.primary : colors.ink,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: _kAmountAreaHeight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 支出走主行、收入才换行：多数日子收入是 0，
                      // 恒定两行会让整张表被一列「0」占满。
                      if (expenseCents > 0)
                        _Amount(
                          cents: expenseCents,
                          color: colors.expense,
                          prefix: '-',
                        ),
                      if (incomeCents > 0)
                        _Amount(
                          cents: incomeCents,
                          color: colors.income,
                          prefix: '+',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 支出热力：越高底色越浓。
  ///
  /// 用支出而不是净收支：这张表的用途是「找出花得凶的几天」，
  /// 净收支会让发工资那天变成最浅的一格。
  ///
  /// 开方压缩是因为日支出分布极偏——一个月里往往一两天几百、其余几十，
  /// 线性映射会让除了峰值以外的所有格子都近乎全白。
  Color? _heatColor(AppColors colors) {
    if (expenseCents <= 0 || maxExpenseCents <= 0) return null;
    final ratio = math.sqrt(expenseCents / maxExpenseCents);
    return colors.expenseSoft.withValues(alpha: 0.3 + 0.7 * ratio);
  }
}

class _Amount extends StatelessWidget {
  const _Amount({
    required this.cents,
    required this.color,
    required this.prefix,
  });

  final int cents;
  final Color color;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    // 一格才 40 出头的宽度，塞不下 `¥1,234.56`。复用坐标轴那套紧凑格式：
    // 这里要的是量级对比，精确到分要点进当天账单看。
    return Text(
      '$prefix${formatAxisMoney(cents)}',
      maxLines: 1,
      style: TextStyle(
        fontSize: 10,
        height: 1.1,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}
