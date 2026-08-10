import 'dart:math' as math;

import '../../../core/database/app_database.dart';
import '../../../core/utils/ledger_date.dart';

/// 统计页的时间维度。
enum StatisticsPeriod {
  day('日'),
  week('周'),
  month('月'),
  year('年'),
  custom('自定义');

  const StatisticsPeriod(this.label);

  /// 分段选择器上的短标签。
  final String label;
}

/// 统计页当前「看哪一段时间」的完整取值，以及由它派生的全部展示文案。
///
/// 从页面里抽出来的原因：原先区间计算、标题文案、环比区间、对比柱区间
/// 全部挤在 `_StatisticsScreenState` 里，和 UI 代码交错，读一段布局要跳过
/// 上百行日期运算。抽成不可变值对象后，页面只负责「拿窗口 → 渲染」，
/// 日期语义可以独立推理，也方便以后单测。
///
/// 计算口径与原实现逐条保持一致，没有改变任何业务语义。
class StatisticsWindow {
  const StatisticsWindow({
    required this.period,
    required this.anchor,
    this.customRange,
  });

  StatisticsWindow.now()
    : period = StatisticsPeriod.month,
      anchor = DateTime.now(),
      customRange = null;

  final StatisticsPeriod period;

  /// 当前锚点：日/周/月/年模式下用它推出区间。
  final DateTime anchor;

  /// 自定义模式下用户选定的区间；为空时回落到锚点所在自然月。
  final LedgerDateRange? customRange;

  StatisticsWindow copyWith({
    StatisticsPeriod? period,
    DateTime? anchor,
    LedgerDateRange? customRange,
  }) => StatisticsWindow(
    period: period ?? this.period,
    anchor: anchor ?? this.anchor,
    customRange: customRange ?? this.customRange,
  );

  /// 当前统计区间。
  LedgerDateRange get range => switch (period) {
    StatisticsPeriod.day => dayRange(anchor),
    StatisticsPeriod.week => weekRange(anchor),
    StatisticsPeriod.month => monthRange(anchor),
    StatisticsPeriod.year => yearRange(anchor),
    StatisticsPeriod.custom => customRange ?? monthRange(anchor),
  };

  /// 上一周期区间，用于环比（本期 vs 上期）。
  LedgerDateRange get previousRange => switch (period) {
    StatisticsPeriod.day => dayRange(anchor.subtract(const Duration(days: 1))),
    StatisticsPeriod.week => weekRange(
      anchor.subtract(const Duration(days: 7)),
    ),
    StatisticsPeriod.month => monthRange(
      DateTime(anchor.year, anchor.month - 1, 1),
    ),
    StatisticsPeriod.year => yearRange(DateTime(anchor.year - 1, 1, 1)),
    StatisticsPeriod.custom => () {
      final current = range;
      final shift = Duration(days: math.max(1, current.dayCount));
      return LedgerDateRange(
        current.start.subtract(shift),
        current.endExclusive.subtract(shift),
      );
    }(),
  };

  /// 趋势图是否按月聚合：年视图，或跨度超过 62 天的自定义区间。
  bool get groupByMonth =>
      period == StatisticsPeriod.year ||
      (period == StatisticsPeriod.custom && range.dayCount > 62);

  /// 「周期支出对比」的近 6 个周期（升序，末位为当前周期）。
  List<PeriodSpan> get comparisonSpans {
    const count = 6;
    final spans = <PeriodSpan>[];
    for (var offset = count - 1; offset >= 0; offset--) {
      final (spanRange, label) = _spanAt(offset);
      spans.add(PeriodSpan(range: spanRange, label: label));
    }
    return spans;
  }

  /// offset=0 表示当前周期，offset=1 表示上一周期，以此类推。
  (LedgerDateRange, String) _spanAt(int offset) {
    switch (period) {
      case StatisticsPeriod.day:
        final day = anchor.subtract(Duration(days: offset));
        return (dayRange(day), '${day.month}/${day.day}');
      case StatisticsPeriod.week:
        final shifted = anchor.subtract(Duration(days: 7 * offset));
        final weekly = weekRange(shifted);
        return (weekly, '${weekly.start.month}/${weekly.start.day}');
      case StatisticsPeriod.year:
        final year = anchor.year - offset;
        return (yearRange(DateTime(year, 1, 1)), '$year');
      case StatisticsPeriod.month:
      case StatisticsPeriod.custom:
        final month = DateTime(anchor.year, anchor.month - offset, 1);
        return (monthRange(month), '${month.month}月');
    }
  }

  /// 趋势卡标题。
  String get trendTitle => switch (period) {
    StatisticsPeriod.day => '当日支出趋势',
    StatisticsPeriod.week => '本周支出趋势',
    StatisticsPeriod.year => '年度支出趋势',
    _ => '本期支出趋势',
  };

  /// 对比卡标题。
  String get comparisonTitle => switch (period) {
    StatisticsPeriod.day => '日支出对比',
    StatisticsPeriod.week => '周支出对比',
    StatisticsPeriod.year => '年支出对比',
    _ => '月支出对比',
  };

  /// 趋势卡副标题：说明聚合粒度，省得用户猜横轴是天还是月。
  String get trendCaption => groupByMonth ? '按月聚合' : '按天聚合';

  /// 对比卡副标题。
  String get comparisonCaption => switch (period) {
    StatisticsPeriod.day => '最近 6 天',
    StatisticsPeriod.week => '最近 6 周',
    StatisticsPeriod.year => '最近 6 年',
    _ => '最近 6 个月',
  };

  /// 环比说明里对「上一周期」的称呼。
  String get previousLabel => switch (period) {
    StatisticsPeriod.day => '较昨日',
    StatisticsPeriod.week => '较上周',
    StatisticsPeriod.month => '较上月',
    StatisticsPeriod.year => '较去年',
    StatisticsPeriod.custom => '较上期',
  };

  /// 区间切换器中间显示的文案。
  String get rangeLabel {
    final current = range;
    final lastDay = current.endExclusive.subtract(const Duration(days: 1));
    return switch (period) {
      StatisticsPeriod.day =>
        '${current.start.year} 年 ${current.start.month} 月 ${current.start.day} 日',
      StatisticsPeriod.week =>
        '${current.start.month}/${current.start.day} - ${lastDay.month}/${lastDay.day}',
      StatisticsPeriod.month => formatMonth(current.start),
      StatisticsPeriod.year => '${current.start.year} 年',
      StatisticsPeriod.custom =>
        '${dateKey(current.start)} - ${dateKey(lastDay)}',
    };
  }

  /// 区间是否已经包含今天——包含时禁用「下一周期」，
  /// 避免用户一路翻到没有数据的未来区间。
  bool get includesToday {
    final today = dateOnly(DateTime.now());
    final current = range;
    return !today.isBefore(current.start) &&
        today.isBefore(current.endExclusive);
  }

  /// 按 [direction]（-1 上一段/ +1 下一段）平移当前窗口。
  StatisticsWindow shifted(int direction) {
    switch (period) {
      case StatisticsPeriod.day:
        return copyWith(anchor: anchor.add(Duration(days: direction)));
      case StatisticsPeriod.week:
        return copyWith(anchor: anchor.add(Duration(days: 7 * direction)));
      case StatisticsPeriod.month:
        return copyWith(
          anchor: DateTime(anchor.year, anchor.month + direction),
        );
      case StatisticsPeriod.year:
        return copyWith(anchor: DateTime(anchor.year + direction, 1, 1));
      case StatisticsPeriod.custom:
        final current = range;
        final shift = Duration(days: current.dayCount * direction);
        return StatisticsWindow(
          period: period,
          anchor: anchor,
          customRange: LedgerDateRange(
            current.start.add(shift),
            current.endExclusive.add(shift),
          ),
        );
    }
  }
}
