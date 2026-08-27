import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/database/app_database.dart';
import '../../../core/location/place_fix.dart';
import '../../../core/theme/app_density.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../statistics/presentation/stats_design.dart';
import '../application/providers.dart';
import 'month_picker.dart';
import 'transaction_editor.dart';

/// 日历页：按日历网格铺开的收支视图。
///
/// 两个层级问的是同一个问题的不同尺度：
/// - **月层级**：一屏一个月，横滑翻月，一格一天。点某天在下方展开当天账单。
/// - **年层级**：一屏一年，一格一月。点某个月下钻到那个月的月历。
///
/// 顶部的口径 tab（收支 / 结余）同时决定格子里显示哪个数和热力按哪个量
/// 上色——两者不一致的话，切到「结余」还按支出深浅上色就自相矛盾了。
///
/// 它和统计页的趋势折线吃同一批聚合数据，但折线的横轴是连续时间，读得出
/// 走势、读不出「上周六花了多少」。日历按星期对齐，既能定位到具体某天，
/// 也能看出周内规律和哪几天压根没记账。所以这里不做趋势 / 占比分析，
/// 那些是统计页的职责。
///
/// **本页自成一体**：点格子只在页内展开明细，不联动明细页的月份。
/// 它是底栏上的一级页，不是明细的弹层。跑离当前自然日时，页头「今」拉回来。
class CalendarScreen extends ConsumerStatefulWidget {
  CalendarScreen({super.key, DateTime? initialMonth})
    : initialMonth = _asMonth(initialMonth ?? DateTime.now());

  /// 打开时停在哪个月。底栏入口不传，默认当前自然月。
  final DateTime initialMonth;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

DateTime _asMonth(DateTime value) => DateTime(value.year, value.month);

/// 格子里显示什么、热力按什么算。
///
/// 只有两档，是因为「只看支出」「只看收入」相对 [both] 几乎没有增量信息：
/// 个人记账里绝大多数日子没有收入，[both] 那一档本来就只画得出支出一行，
/// 两张网格摆在一起是同一张。真正独立的只有 [net]——它是合成出来的一个
/// 带符号的数，[both] 无论如何也显示不了。
enum _Metric {
  /// 支出和收入两行并列。进页面的默认档。
  both('收支'),

  /// 收入减支出。日粒度上它几乎等于支出取负（多数日子没有收入），
  /// 真正有用的是年层级——「哪几个月是净流出」月历本身答不上来。
  net('结余');

  const _Metric(this.label);

  final String label;
}

/// 可翻阅的年份下界 / 上界。
///
/// 与 `showMonthPicker`、forui 日期选择器同一个区间：同一个 App 里
/// 「最早能翻到哪一年」出现三个答案，只会让人以为某处坏了。
const int _kFirstYear = 2000;
const int _kLastYear = 2100;

const int _kMonthPageCount = (_kLastYear - _kFirstYear + 1) * 12;

int _monthPage(DateTime month) =>
    (month.year - _kFirstYear) * 12 + month.month - 1;

DateTime _monthOfPage(int page) =>
    DateTime(_kFirstYear + page ~/ 12, page % 12 + 1);

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month;
  late int _year;
  late PageController _pageController;

  /// true 时展示一年十二格，false 时展示可横滑的月历。
  bool _yearLevel = false;

  _Metric _metric = _Metric.both;

  /// 月层级当前选中的那一天。null 表示下方不展开明细。
  DateTime? _selectedDay;

  /// 明细面板的锚点，用来在选中靠下的日期后把面板滚进视口。
  final GlobalKey _detailKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);
    _year = _month.year;
    _pageController = PageController(initialPage: _monthPage(_month));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _shift(int direction) {
    if (_yearLevel) {
      final year = _year + direction;
      if (year < _kFirstYear || year > _kLastYear) return;
      setState(() => _year = year);
      return;
    }
    final page = _monthPage(_month) + direction;
    if (page < 0 || page >= _kMonthPageCount) return;
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleLevel() {
    if (_yearLevel) {
      _showMonth(DateTime(_year, _month.year == _year ? _month.month : 1));
      return;
    }
    setState(() {
      _year = _month.year;
      _yearLevel = true;
      _selectedDay = null;
    });
  }

  /// 已经停在今天：月层级、选中的就是今天。此时「今」置灰，点了也没处可去。
  bool get _atToday {
    final selected = _selectedDay;
    if (_yearLevel || selected == null) return false;
    return dateOnly(selected) == dateOnly(DateTime.now());
  }

  /// 回到月层级并停在 [month]。
  ///
  /// 必须换一个 [PageController]：年层级期间 PageView 整个离开了树，控制器
  /// 也跟着 detach，重新 attach 时没有旧 position 可继承，只会退回自己的
  /// `initialPage`——那是进页面时的月份，不是刚点的那个月。
  ///
  /// [select] 非空时同时选中那一天（「回到今天」用）。年层级点月份不传，
  /// 只下钻到月历，不擅自选中某一天。
  void _showMonth(DateTime month, {DateTime? select}) {
    final target = DateTime(month.year, month.month);
    setState(() {
      _month = target;
      _year = target.year;
      _yearLevel = false;
      _selectedDay = select == null ? null : dateOnly(select);
      _pageController.dispose();
      _pageController = PageController(initialPage: _monthPage(target));
    });
    if (select != null) _scrollDetailIntoView();
  }

  /// 回到今天：当前自然月的月历，并展开当天。
  void _goToday() {
    final today = dateOnly(DateTime.now());
    _jumpToMonth(today, select: today);
  }

  /// 点周期条上的月份，弹出和明细页同一套滚轮。
  Future<void> _pickPeriod() async {
    final initial = _yearLevel
        ? DateTime(_year, _month.year == _year ? _month.month : 1)
        : _month;
    final picked = await showMonthPicker(context, initial: initial);
    if (picked == null || !mounted) return;
    _jumpToMonth(picked);
  }

  /// 跳到 [month] 的月历。年层级时重建控制器；月层级只 jump，不拆 PageView。
  void _jumpToMonth(DateTime month, {DateTime? select}) {
    final target = DateTime(month.year, month.month);
    if (_yearLevel) {
      _showMonth(target, select: select);
      return;
    }
    final targetPage = _monthPage(target);
    final currentPage = _pageController.hasClients
        ? (_pageController.page?.round() ?? _monthPage(_month))
        : _monthPage(_month);
    if (currentPage == targetPage) {
      if (select != null) _selectDay(select);
      return;
    }
    _pageController.jumpToPage(targetPage);
    if (select != null) _selectDay(select);
  }

  void _selectDay(DateTime day) {
    setState(() => _selectedDay = day);
    _scrollDetailIntoView();
  }

  void _scrollDetailIntoView() {
    // 网格底下几行的格子按下去时，面板会长在视口之外，看起来像没反应。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _detailKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.6,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = _selectedDay;
    return AppPageHeader(
      title: '日历',
      actions: [_TodayAction(onTap: _atToday ? null : _goToday)],
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _PeriodBarDelegate(
            label: _yearLevel ? '$_year 年' : formatMonth(_month),
            yearLevel: _yearLevel,
            onShift: _shift,
            onPick: _pickPeriod,
            onToggleLevel: _toggleLevel,
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            28 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverList.list(
            children: [
              _MetricTabs(
                selected: _metric,
                onChanged: (value) => setState(() => _metric = value),
              ),
              const SizedBox(height: 12),
              if (_yearLevel)
                _YearLevel(
                  year: _year,
                  metric: _metric,
                  onPickMonth: (month) => _showMonth(month),
                )
              else
                _MonthLevel(
                  controller: _pageController,
                  metric: _metric,
                  selectedDay: _selectedDay,
                  onPageChanged: (page) => setState(() {
                    final next = _monthOfPage(page);
                    _month = next;
                    final selected = _selectedDay;
                    // 选中日不属于这一页就丢掉。用户横滑是这种情况；
                    // 「回到今天」先 jump 再选中，选中日就在目标月里，会留下。
                    if (selected == null ||
                        selected.year != next.year ||
                        selected.month != next.month) {
                      _selectedDay = null;
                    }
                  }),
                  onPickDay: _selectDay,
                ),
              if (!_yearLevel && selected != null) ...[
                const SizedBox(height: 12),
                _DayDetail(key: _detailKey, day: selected),
              ] else ...[
                const SizedBox(height: 14),
                Text(
                  _yearLevel ? '点某个月进入当月月历' : '点某天查看当天账单',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────── 周期条（吸顶）

const double _kPeriodBarHeight = 52;

/// `‹  2026 年 8 月  ›`：两侧翻页；点月份弹出滚轮跳月；旁边箭头切年/月层级。
///
/// 左右箭头的手势语言直接照搬统计页的周期切换。点月份弹出的滚轮和明细页
/// 吸顶条是同一份 [showMonthPicker]——滑动是挨着翻，点选是随便跳，两套都要。
///
/// 底板与明细页吸顶月份条共用 [AppChromeGlass]：内容穿过去时才挂毛玻璃，
/// 壁纸模式下的实色蒙版也由它负责。
class _PeriodBarDelegate extends SliverPersistentHeaderDelegate {
  const _PeriodBarDelegate({
    required this.label,
    required this.yearLevel,
    required this.onShift,
    required this.onPick,
    required this.onToggleLevel,
  });

  final String label;
  final bool yearLevel;
  final ValueChanged<int> onShift;
  final VoidCallback onPick;
  final VoidCallback onToggleLevel;

  @override
  double get minExtent => _kPeriodBarHeight;

  @override
  double get maxExtent => _kPeriodBarHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = context.colors;
    return AppChromeGlass(
      translucency: (shrinkOffset / _kPeriodBarHeight).clamp(0.0, 1.0),
      child: Material(
        // 底色交给 AppChromeGlass，这里只提供水波画布。
        type: MaterialType.transparency,
        child: SizedBox(
          height: _kPeriodBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _ArrowButton(
                  icon: FLucideIcons.chevronLeft,
                  tooltip: yearLevel ? '上一年' : '上个月',
                  onTap: () => onShift(-1),
                ),
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: '选择月份',
                          child: InkWell(
                            onTap: onPick,
                            borderRadius: context.radii.chipAll,
                            highlightColor: colors.pressed,
                            splashColor: colors.ripple,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: colors.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: yearLevel ? '月视图' : '年视图',
                          child: InkWell(
                            onTap: onToggleLevel,
                            borderRadius: context.radii.chipAll,
                            highlightColor: colors.pressed,
                            splashColor: colors.ripple,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                yearLevel
                                    ? FLucideIcons.chevronDown
                                    : FLucideIcons.chevronUp,
                                size: 16,
                                color: colors.inactive,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _ArrowButton(
                  icon: FLucideIcons.chevronRight,
                  tooltip: yearLevel ? '下一年' : '下个月',
                  onTap: () => onShift(1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_PeriodBarDelegate oldDelegate) =>
      label != oldDelegate.label || yearLevel != oldDelegate.yearLevel;
}

/// 页头右侧的「今」：地图跑远了要能复位。
///
/// 不用 [AppHeaderAction]：那颗键只收图标，「今」一个字比任何日历图标都准。
/// 热区仍按 [kAppHeaderActionSize]，页头算标题避让宽度时才不会偏。
///
/// [onTap] 为 null 即已停在今天：键还在，只是置灰，位置不因「在不在今天」跳动。
class _TodayAction extends StatelessWidget {
  const _TodayAction({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = onTap != null;
    return Tooltip(
      message: '回到今天',
      child: InkResponse(
        onTap: onTap,
        radius: kAppHeaderActionSize / 2,
        containedInkWell: true,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: kAppHeaderActionSize,
          child: Center(
            child: Text(
              '今',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: active ? colors.ink : colors.inactive,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        containedInkWell: true,
        customBorder: const CircleBorder(),
        highlightColor: colors.pressed,
        splashColor: colors.ripple,
        child: SizedBox.square(
          dimension: 40,
          child: Center(child: Icon(icon, size: 20, color: colors.ink)),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────── 口径 tab

/// 四档口径切换：轨道底 + 跟随滑动的高亮块。
///
/// 几何与统计页的 [StatsPeriodSelector] 刻意一致（40 高、4 内缩、滑块带
/// 一层极淡阴影）——两处都是「一排等宽档位选一个」，长得不一样会让人以为
/// 它们的行为也不一样。没有直接复用是因为那个组件绑死在 `StatisticsPeriod`
/// 和统计页的 token 上，为了四个字把记账 feature 挂到统计 feature 上不划算。
class _MetricTabs extends StatelessWidget {
  const _MetricTabs({required this.selected, required this.onChanged});

  final _Metric selected;
  final ValueChanged<_Metric> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const values = _Metric.values;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: context.radii.blockAll,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = constraints.maxWidth / values.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: slotWidth * values.indexOf(selected),
                top: 0,
                bottom: 0,
                width: slotWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(
                      math.max(0, context.radii.block - 4),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14101828),
                        offset: Offset(0, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final value in values)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(value),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: value == selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: value == selected
                                  ? colors.primary
                                  : colors.muted,
                            ),
                            child: Text(value.label),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────── 月层级

/// 一格的高度。日期数字 18 + 金额区 24 + 上下各 2 的格间距。
const double _kCellHeight = 46;

/// 日期数字占的固定高度。金额区同样固定，两者都不随「这天有没有收入」
/// 变化——否则同一行里日期数字会上下错位，整张表看着在抖。
const double _kDateLineHeight = 18;
const double _kAmountAreaHeight = 24;

/// 网格恒按 6 行留高，即使这个月只用得上 4 行。
///
/// PageView 的页高不能随页而变，否则每翻一个月整块卡片都要长高或塌下去一截。
const double _kGridHeight = _kCellHeight * 6;

/// 页高 = 网格 + 底部合计行。
const double _kMonthPageHeight = _kGridHeight + 40;

/// 月层级：静止的星期表头 + 可横滑的月网格。
///
/// 星期表头留在 PageView 外面：七列的含义每个月都一样，让它跟着页面一起
/// 滑动只会制造「这一栏也在动」的错觉。
class _MonthLevel extends StatelessWidget {
  const _MonthLevel({
    required this.controller,
    required this.metric,
    required this.selectedDay,
    required this.onPageChanged,
    required this.onPickDay,
  });

  final PageController controller;
  final _Metric metric;
  final DateTime? selectedDay;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<DateTime> onPickDay;

  @override
  Widget build(BuildContext context) {
    return _CalendarCard(
      child: Column(
        children: [
          const _WeekdayHeader(),
          const SizedBox(height: 4),
          SizedBox(
            height: _kMonthPageHeight,
            child: PageView.builder(
              controller: controller,
              onPageChanged: onPageChanged,
              itemCount: _kMonthPageCount,
              itemBuilder: (context, page) => _MonthPage(
                month: _monthOfPage(page),
                metric: metric,
                selectedDay: selectedDay,
                onPickDay: onPickDay,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthPage extends ConsumerWidget {
  const _MonthPage({
    required this.month,
    required this.metric,
    required this.selectedDay,
    required this.onPickDay,
  });

  final DateTime month;
  final _Metric metric;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onPickDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(databaseProvider);
    // 只订阅按天聚合，不订阅整月明细：这里要的是每格一两个数字，
    // 拉全量账单再在内存里分组等于把明细页的活儿重做一遍。
    return StreamBuilder<List<TrendPoint>>(
      stream: database.watchTrend(monthRange(month), groupByMonth: false),
      builder: (context, snapshot) {
        // 首帧没数据时先把网格铺出来（日期格永远画得出），金额随流到达后
        // 填进去，避免整块区域先塌一下再长出来。
        final points = snapshot.data ?? const <TrendPoint>[];
        return Column(
          children: [
            SizedBox(
              height: _kGridHeight,
              child: _MonthGrid(
                month: month,
                metric: metric,
                selectedDay: selectedDay,
                byDay: {for (final point in points) point.bucket: point},
                onPickDay: onPickDay,
              ),
            ),
            Expanded(
              child: Center(
                child: _TotalRow(points: points, metric: metric),
              ),
            ),
          ],
        );
      },
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
        for (final label in _labels)
          Expanded(
            child: Center(
              child: Text(
                label,
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

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.metric,
    required this.selectedDay,
    required this.byDay,
    required this.onPickDay,
  });

  final DateTime month;
  final _Metric metric;
  final DateTime? selectedDay;

  /// 日期 key（yyyy-MM-dd）→ 当天聚合。只有至少有一笔记录的天才在表里，
  /// 所以「在不在表里」就是「这天有没有记录」。
  final Map<String, TrendPoint> byDay;

  final ValueChanged<DateTime> onPickDay;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final dayCount = _daysInMonth(month);
    // 首行左侧要空出的格数：周一起始，所以周一空 0 格、周日空 6 格。
    final leading = first.weekday - DateTime.monday;
    final rowCount = ((leading + dayCount) / 7).ceil();

    // 热力上限取当月单日峰值：跨月比较不是这张表的职责——月层级回答
    // 「这个月哪几天花得凶」，用固定阈值会让低消费月份整月一片白。
    final ceiling = _ceilingFor(metric, byDay.values);
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
                    ceiling: ceiling,
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
    required int ceiling,
    required DateTime today,
  }) {
    if (dayNumber < 1 || dayNumber > dayCount) {
      return const SizedBox(height: _kCellHeight);
    }
    final day = DateTime(month.year, month.month, dayNumber);
    return _DayCell(
      day: day,
      metric: metric,
      point: byDay[dateKey(day)],
      ceilingCents: ceiling,
      isToday: day == today,
      isSelected: day == selectedDay,
      onTap: () => onPickDay(day),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.metric,
    required this.point,
    required this.ceilingCents,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final _Metric metric;
  final TrendPoint? point;
  final int ceilingCents;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // 描边一格只画一条：选中优先于今天。两条都画会让「今天恰好被选中」
    // 变成双层框，而它们表达的其实是同一格。
    final border = isSelected
        ? BorderSide(color: colors.primary, width: 2)
        : isToday
        ? BorderSide(color: colors.primary, width: 1.2)
        : BorderSide.none;
    return SizedBox(
      height: _kCellHeight,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          // 底色三层各管一件事，互不抢：热力=金额大小，描边=今天/选中，
          // 水波=按下反馈。所以今天用描边而不是实底。
          color: _heatColor(colors, metric, point, ceilingCents),
          shape: RoundedRectangleBorder(
            borderRadius: context.radii.chipAll,
            side: border,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
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
                        fontWeight: isToday || isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: isToday
                            ? colors.primary
                            : isSelected || !_isBlank(point)
                            ? colors.ink
                            : colors.inactive,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: _kAmountAreaHeight,
                  child: _isBlank(point)
                      ? const _BlankHint()
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final line in _amountLines(
                              metric,
                              point,
                              colors,
                            ))
                              _Amount(spec: line),
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
}

class _Amount extends StatelessWidget {
  const _Amount({required this.spec, this.fontSize = 10});

  final _AmountSpec spec;

  /// 月格子比日格子宽一倍，金额是那一格的主内容，可以放大一档。
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // 日格才 40 出头的宽度，塞不下 `¥1,234.56`。复用坐标轴那套紧凑格式：
    // 这里要的是量级对比，精确到分点开下方明细看。
    return Text(
      '${spec.prefix}${formatAxisMoney(spec.cents)}',
      maxLines: 1,
      style: TextStyle(
        fontSize: fontSize,
        height: 1.1,
        fontWeight: FontWeight.w700,
        color: spec.color,
      ),
    );
  }
}

/// 空格上的点：没记账，不是花得少。
///
/// 空格原来和卡片同色，小额热力又很淡，远看分不出「没记」和「记了很少」。
/// 日期已经改成 [AppColors.inactive]，这一点是第二通道——有账的格里是数字。
class _BlankHint extends StatelessWidget {
  const _BlankHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 3.5,
        height: 3.5,
        decoration: BoxDecoration(
          color: context.colors.faint,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────── 年层级

/// 年层级一格的高度。月份 + 金额两三行，比日格高一档。
const double _kMonthTileHeight = 62;

/// 一行三格。
///
/// 四列的格子只有 80 出头宽，「1.2万」这种紧凑金额还塞得下，但用户把字号
/// 密度调大一档就会顶出去；三列换来的行数（4 行）一屏仍然放得下。
const int _kYearColumns = 3;

/// 年层级：一年十二格，每格是那个月的收支。
///
/// 单位是**月**而不是天。整年按天铺开（GitHub 贡献图那种）只剩颜色一个
/// 通道，读得出「哪段时间在花钱」，读不出「三月花了多少」——而从年视图
/// 往下找的动作恰恰是先挑月份。所以这一层直接按月聚合，格子里放金额。
class _YearLevel extends ConsumerWidget {
  const _YearLevel({
    required this.year,
    required this.metric,
    required this.onPickMonth,
  });

  final int year;
  final _Metric metric;
  final ValueChanged<DateTime> onPickMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(databaseProvider);
    // groupByMonth：整年只回十二行，不必把三百多天拉回来再在内存里合并。
    return StreamBuilder<List<TrendPoint>>(
      stream: database.watchTrend(
        yearRange(DateTime(year)),
        groupByMonth: true,
      ),
      builder: (context, snapshot) {
        final points = snapshot.data ?? const <TrendPoint>[];
        return _CalendarCard(
          child: Column(
            children: [
              _YearGrid(
                year: year,
                metric: metric,
                byMonth: {for (final point in points) point.bucket: point},
                onPickMonth: onPickMonth,
              ),
              const SizedBox(height: 12),
              _TotalRow(points: points, metric: metric),
            ],
          ),
        );
      },
    );
  }
}

class _YearGrid extends StatelessWidget {
  const _YearGrid({
    required this.year,
    required this.metric,
    required this.byMonth,
    required this.onPickMonth,
  });

  final int year;
  final _Metric metric;

  /// 月份 key（yyyy-MM）→ 当月聚合。没有任何记录的月份不在表里。
  final Map<String, TrendPoint> byMonth;

  final ValueChanged<DateTime> onPickMonth;

  @override
  Widget build(BuildContext context) {
    // 热力上限取当年单月峰值。这一层的职责本来就是「十二个月互相比」，
    // 峰值归一化正好——十二个数里出一个极端值本身就是要看见的信息。
    final ceiling = _ceilingFor(metric, byMonth.values);
    final now = DateTime.now();
    final rowCount = (12 / _kYearColumns).ceil();

    return Column(
      children: [
        for (var row = 0; row < rowCount; row++)
          Row(
            children: [
              for (var column = 0; column < _kYearColumns; column++)
                Expanded(
                  child: _buildTile(
                    month: row * _kYearColumns + column + 1,
                    ceiling: ceiling,
                    now: now,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildTile({
    required int month,
    required int ceiling,
    required DateTime now,
  }) {
    final anchor = DateTime(year, month);
    return _MonthTile(
      month: month,
      metric: metric,
      point: byMonth[_monthKey(anchor)],
      ceilingCents: ceiling,
      isCurrent: year == now.year && month == now.month,
      onTap: () => onPickMonth(anchor),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.month,
    required this.metric,
    required this.point,
    required this.ceilingCents,
    required this.isCurrent,
    required this.onTap,
  });

  final int month;
  final _Metric metric;
  final TrendPoint? point;
  final int ceilingCents;

  /// 是不是当前自然月。与日格上的「今天」同一套描边语言。
  final bool isCurrent;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: _kMonthTileHeight,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: _heatColor(colors, metric, point, ceilingCents),
          shape: RoundedRectangleBorder(
            borderRadius: context.radii.chipAll,
            side: isCurrent
                ? BorderSide(color: colors.primary, width: 1.2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            highlightColor: colors.pressed,
            splashColor: colors.ripple,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$month 月',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                    color: isCurrent
                        ? colors.primary
                        : _isBlank(point)
                        ? colors.inactive
                        : colors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                if (_isBlank(point))
                  const _BlankHint()
                else
                  for (final line in _amountLines(metric, point, colors))
                    _Amount(spec: line, fontSize: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── 当天账单面板

/// 选中某天后在网格下方展开的当天账单。
///
/// 刻意不复用明细页的 `_DayCard`：那张卡背着多选、长按删除、首图缩略图和
/// 高亮描边一整套状态，搬过来等于把明细页的交互模型也搬过来。这里只要
/// 「看一眼 + 点进去改」，写一份只读的轻列表更省。
///
/// 不跟着口径过滤：两档口径读的都是收支两侧——「结余」本身就是这两侧算
/// 出来的，只列一边等于把它的来源藏起来一半。
///
/// 标题行整条可点，进记一笔——和明细页日卡 header 同一条手势。日历底栏
/// 没有 FAB，有账的天也得从这里再记；单独放一颗加号会变成两套入口。
class _DayDetail extends ConsumerWidget {
  const _DayDetail({super.key, required this.day});

  final DateTime day;

  Future<void> _edit(BuildContext context, LedgerItem item) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TransactionEditor(existing: item)),
    );
  }

  Future<void> _add(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TransactionEditor(initialDate: dateOnly(day)),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final database = ref.watch(databaseProvider);
    return _CalendarCard(
      child: StreamBuilder<List<LedgerItem>>(
        stream: database.watchTransactions(dayRange(day)),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <LedgerItem>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: '记一笔',
                child: InkWell(
                  onTap: () => _add(context),
                  borderRadius: context.radii.chipAll,
                  highlightColor: colors.pressed,
                  splashColor: colors.ripple,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                    child: Row(
                      children: [
                        Text(
                          formatDay(day),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          formatWeekday(day),
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                        const Spacer(),
                        Text(
                          '${items.length} 笔',
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (items.isEmpty)
                const _EmptyDay()
              else
                for (final item in items)
                  _DetailRow(item: item, onTap: () => _edit(context, item)),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          '这天没有记录',
          style: TextStyle(fontSize: 13, color: colors.muted),
        ),
      ),
    );
  }
}

class _DetailRow extends ConsumerWidget {
  const _DetailRow({required this.item, required this.onTap});

  final LedgerItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final grouped = ref.watch(moneyGroupedProvider);
    final isExpense = item.transaction.kind == 0;
    final color = isExpense ? colors.expense : colors.income;
    final soft = isExpense ? colors.expenseSoft : colors.incomeSoft;
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      item.transaction.occurredAt,
    );
    final extra = item.transaction.locationAndNote;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radii.blockAll,
      highlightColor: colors.pressed,
      splashColor: colors.ripple,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 6,
          vertical: context.density.space(9),
        ),
        child: Row(
          children: [
            CategoryIconBadge(
              iconKey: item.category.iconKey,
              color: color,
              background: soft,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    extra.isEmpty
                        ? formatClock(occurredAt)
                        : '${formatClock(occurredAt)} · $extra',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${isExpense ? '-' : '+'}'
              '${formatMoney(item.transaction.amountCents, grouped: grouped)}',
              style: AppText.money(AppText.moneySm, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────── 共用零件

/// 网格外壳：白面卡片，与明细页日卡、统计页图表卡同一高度浮起。
class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shape = context.radii.cardShape();
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, shadows: colors.shadowCard),
      // 白底必须由 Material 提供：水波画在最近的 Material 上，
      // 用 Container(color:) 会把反馈盖住。明细页日卡踩过同一个坑。
      child: Material(
        color: colors.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: child,
        ),
      ),
    );
  }
}

/// 当前周期在当前口径下的合计。
///
/// 翻到别的月 / 年时，「我现在看的是哪一段、总共多少」必须留在屏幕上，
/// 否则一屏格子读不出量级——这正是能翻月之后新增的问题。
class _TotalRow extends ConsumerWidget {
  const _TotalRow({required this.points, required this.metric});

  final List<TrendPoint> points;
  final _Metric metric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final grouped = ref.watch(moneyGroupedProvider);
    var expense = 0;
    var income = 0;
    for (final point in points) {
      expense += point.expenseCents;
      income += point.incomeCents;
    }
    final labelStyle = TextStyle(fontSize: 11, color: colors.muted);
    // 颜色在下面按收支各自覆盖，这里给个占位。
    final valueStyle = AppText.money(13, color: colors.ink);

    List<Widget> cells() {
      switch (metric) {
        case _Metric.both:
          return [
            Text('支出 ', style: labelStyle),
            Text(
              formatMoney(expense, grouped: grouped),
              style: valueStyle.copyWith(color: colors.expense),
            ),
            const SizedBox(width: 14),
            Text('收入 ', style: labelStyle),
            Text(
              formatMoney(income, grouped: grouped),
              style: valueStyle.copyWith(color: colors.income),
            ),
          ];
        case _Metric.net:
          final net = income - expense;
          return [
            Text('结余 ', style: labelStyle),
            Text(
              formatMoney(net, signed: true, grouped: grouped),
              style: valueStyle.copyWith(
                color: net < 0 ? colors.expense : colors.income,
              ),
            ),
          ];
      }
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: cells());
  }
}

/// 一格里要显示的一行金额。
class _AmountSpec {
  const _AmountSpec({
    required this.cents,
    required this.color,
    required this.prefix,
  });

  final int cents;
  final Color color;
  final String prefix;
}

/// 当前口径下，一格该显示哪几行金额。空列表表示这格什么都不显示。
///
/// 「收支」档最多两行，其余档最多一行。收入为 0 时不占行——多数日子没有
/// 收入，恒定两行会让整张表被一列「0」占满。
List<_AmountSpec> _amountLines(
  _Metric metric,
  TrendPoint? point,
  AppColors colors,
) {
  if (point == null) return const [];
  switch (metric) {
    case _Metric.both:
      return [
        if (point.expenseCents > 0)
          _AmountSpec(
            cents: point.expenseCents,
            color: colors.expense,
            prefix: '-',
          ),
        if (point.incomeCents > 0)
          _AmountSpec(
            cents: point.incomeCents,
            color: colors.income,
            prefix: '+',
          ),
      ];
    case _Metric.net:
      final net = point.incomeCents - point.expenseCents;
      if (net == 0) return const [];
      return [
        _AmountSpec(
          cents: net.abs(),
          color: net < 0 ? colors.expense : colors.income,
          prefix: net < 0 ? '-' : '+',
        ),
      ];
  }
}

/// 这格有没有账。热力为 0、结余为 0 都还可能有账（收支相抵），
/// 只有两侧都空才是「没记」。
bool _isBlank(TrendPoint? point) =>
    point == null || (point.expenseCents <= 0 && point.incomeCents <= 0);

/// 当前口径下的热力分母：这一屏里该口径的峰值。
int _ceilingFor(_Metric metric, Iterable<TrendPoint> points) {
  var ceiling = 0;
  for (final point in points) {
    final value = switch (metric) {
      _Metric.both => point.expenseCents,
      _Metric.net => (point.incomeCents - point.expenseCents).abs(),
    };
    ceiling = math.max(ceiling, value);
  }
  return ceiling;
}

/// 一格的热力底色。
///
/// 口径决定用哪个量、哪个色系。「结余」是唯一有正负的口径，用发散配色：
/// 净流出偏支出色、净流入偏收入色。色值一律取 [AppColors] 的语义色而不是
/// 写死红绿——用户可以在外观里把收支配色整个翻转过来。
Color? _heatColor(
  AppColors colors,
  _Metric metric,
  TrendPoint? point,
  int ceilingCents,
) {
  if (point == null) return null;
  return switch (metric) {
    _Metric.both => _rampColor(
      colors.expenseSoft,
      point.expenseCents,
      ceilingCents,
    ),
    _Metric.net => _netHeat(colors, point, ceilingCents),
  };
}

Color? _netHeat(AppColors colors, TrendPoint point, int ceilingCents) {
  final net = point.incomeCents - point.expenseCents;
  if (net == 0) return null;
  return _rampColor(
    net < 0 ? colors.expenseSoft : colors.incomeSoft,
    net.abs(),
    ceilingCents,
  );
}

/// 单色渐变：越接近 [ceilingCents] 越浓。
///
/// 开方压缩是因为金额分布极偏——一个月里往往一两天几百、其余几十，线性
/// 映射会让除了峰值以外的所有格子都近乎全白。
///
/// 底色取 `*Soft` 这档淡色而不是实色：格子里还压着金额文字，底色一浓就和
/// 文字打架。热力在这里是辅助通道，不是唯一通道。
Color? _rampColor(Color base, int magnitude, int ceilingCents) {
  if (magnitude <= 0 || ceilingCents <= 0) return null;
  final ratio = math.sqrt(math.min(1, magnitude / ceilingCents));
  return base.withValues(alpha: 0.3 + 0.7 * ratio);
}

/// 按月聚合的桶键，格式与 `watchTrend(groupByMonth: true)` 里的
/// `substr(accounting_date, 1, 7)` 对齐。
String _monthKey(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}'
    '-${month.month.toString().padLeft(2, '0')}';

/// 当月天数。
///
/// 不走 [LedgerDateRange.dayCount]：那是两个本地时刻相减，在有夏令时的
/// 时区会少算一天，月末最后一格会整个消失。`DateTime(y, m + 1, 0)` 由
/// 日期归一化推出上个月最后一天，不受时刻影响。
int _daysInMonth(DateTime month) =>
    DateTime(month.year, month.month + 1, 0).day;
