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
    this.today,
  });

  StatisticsWindow.now()
    : period = StatisticsPeriod.month,
      anchor = DateTime.now(),
      customRange = null,
      today = null;

  final StatisticsPeriod period;

  /// 当前锚点：日/周/月/年模式下用它推出区间。
  final DateTime anchor;

  /// 自定义模式下用户选定的区间；为空时回落到锚点所在自然月。
  final LedgerDateRange? customRange;

  /// 判断「区间走到哪儿了」时所用的今天；为空取系统当天。
  ///
  /// 存在的唯一理由是让区间口径可断言：[elapsedDayCount] 与
  /// [comparisonRange] 的结果取决于今天是几号，直接读 [DateTime.now]
  /// 的话同一条断言在月初和月末会得到不同答案。
  final DateTime? today;

  StatisticsWindow copyWith({
    StatisticsPeriod? period,
    DateTime? anchor,
    LedgerDateRange? customRange,
  }) => StatisticsWindow(
    period: period ?? this.period,
    anchor: anchor ?? this.anchor,
    customRange: customRange ?? this.customRange,
    today: today,
  );

  DateTime get _today => dateOnly(today ?? DateTime.now());

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

  /// 当期已经走完的天数：区间起点到今天（含今天）。
  ///
  /// 区间整体落在过去时等于 [LedgerDateRange.dayCount]；整体落在未来时为 0
  /// （自定义模式可以选到未来的区间）。
  int get elapsedDayCount {
    final current = range;
    final day = _today;
    if (day.isBefore(current.start)) return 0;
    if (!day.isBefore(current.endExclusive)) return current.dayCount;
    return day.difference(current.start).inDays + 1;
  }

  /// 当期是否还没走完。
  ///
  /// 进行中的区间不能拿去和完整的上一周期比：8 月 13 日看月视图时，
  /// 「13 天的支出」对上「31 天的支出」几乎必然显示大幅下降，
  /// 环比徽章会在每个月上半月稳定误报利好。
  bool get isPartial => elapsedDayCount < range.dayCount;

  /// 环比对照区间：当期进行中时只取上一周期同样长度的前缀。
  ///
  /// 前缀长度还要夹在上一周期自身长度内——3 月 29 日看月视图时，
  /// 29 天的前缀会越过 2 月末尾，此时退化成整个 2 月。
  LedgerDateRange get comparisonRange {
    final previous = previousRange;
    if (!isPartial) return previous;
    final days = math.min(elapsedDayCount, previous.dayCount);
    final start = previous.start;
    return LedgerDateRange(
      start,
      DateTime(start.year, start.month, start.day + days),
    );
  }

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

  /// 趋势卡标题。收支口径由卡内切换器表达，标题只说明时间范围。
  String get trendTitle => switch (period) {
    StatisticsPeriod.day => '当日趋势',
    StatisticsPeriod.week => '本周趋势',
    StatisticsPeriod.year => '年度趋势',
    _ => '本期趋势',
  };

  /// 对比卡标题。[kind] 为 0 支出 / 1 收入。
  ///
  /// 收支口径写进标题而不是只靠卡内的切换器：这张卡在页面最下方，
  /// 用户往往是滚到这里才看见它，标题必须自己说清算的是哪一边。
  String comparisonTitle(int kind) {
    final subject = kind == 0 ? '支出' : '收入';
    return switch (period) {
      StatisticsPeriod.day => '日$subject对比',
      StatisticsPeriod.week => '周$subject对比',
      StatisticsPeriod.year => '年$subject对比',
      _ => '月$subject对比',
    };
  }

  /// 趋势卡副标题：说明聚合粒度，省得用户猜横轴是天还是月。
  String get trendCaption => groupByMonth ? '按月聚合' : '按天聚合';

  /// 对比卡副标题。
  String get comparisonCaption => switch (period) {
    StatisticsPeriod.day => '最近 6 天',
    StatisticsPeriod.week => '最近 6 周',
    StatisticsPeriod.year => '最近 6 年',
    _ => '最近 6 个月',
  };

  /// 环比说明里对对照区间的称呼。
  ///
  /// 当期没走完时对照的是上一周期的等长前缀，文案必须点明「同期」，
  /// 否则「较上月 -58%」会被读成和整个上月相比。
  String get previousLabel => switch (period) {
    StatisticsPeriod.day => '较昨日',
    StatisticsPeriod.week => isPartial ? '较上周同期' : '较上周',
    StatisticsPeriod.month => isPartial ? '较上月同期' : '较上月',
    StatisticsPeriod.year => isPartial ? '较去年同期' : '较去年',
    StatisticsPeriod.custom => isPartial ? '较上期同期' : '较上期',
  };

  /// 区间切换器中间显示的文案。
  String get rangeLabel => _labelOf(range);

  /// [comparisonRange] 的文案，给下钻面板的期段切换用。
  ///
  /// 当期没走完时对照的是上一周期的**等长前缀**，不能按周期形状写成「7 月」——
  /// 那会让人以为看的是整个七月。这种情况直接给出起止日期。
  String get comparisonRangeLabel {
    if (!isPartial) return _labelOf(previousRange);
    final current = comparisonRange;
    final lastDay = current.endExclusive.subtract(const Duration(days: 1));
    return '${dateKey(current.start)} - ${dateKey(lastDay)}';
  }

  String _labelOf(LedgerDateRange value) {
    final lastDay = value.endExclusive.subtract(const Duration(days: 1));
    return switch (period) {
      StatisticsPeriod.day =>
        '${value.start.year} 年 ${value.start.month} 月 ${value.start.day} 日',
      StatisticsPeriod.week =>
        '${value.start.month}/${value.start.day} - ${lastDay.month}/${lastDay.day}',
      StatisticsPeriod.month => formatMonth(value.start),
      StatisticsPeriod.year => '${value.start.year} 年',
      StatisticsPeriod.custom => '${dateKey(value.start)} - ${dateKey(lastDay)}',
    };
  }

  /// 区间是否已经包含今天——包含时禁用「下一周期」，
  /// 避免用户一路翻到没有数据的未来区间。
  bool get includesToday {
    final day = _today;
    final current = range;
    return !day.isBefore(current.start) && day.isBefore(current.endExclusive);
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
          today: today,
        );
    }
  }
}
