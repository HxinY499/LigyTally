/// 日期 / 时间 / 日期区间选择的底部浮层。
///
/// 替代 Material 的 `showDatePicker` / `showTimePicker` /
/// `showDateRangePicker`——那几个弹窗自带 Material 的视觉语言（大圆角对话框、
/// 涟漪、独立配色，区间选择器还会整页铺开成 Android 原生全屏页），
/// 和本应用的「白面 + 淡描边 + 扁平」调性冲突。这里统一用 forui 的
/// FCalendar / FTimePicker 作为内容，套同一个 `_SheetShell` 外壳，
/// 保证三者观感一致。
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/ledger_date.dart';

/// 日历左右留白：让日期网格不贴到浮层边缘。
///
/// 取代 forui 自带的 `padding: EdgeInsets.all(12)`——那个 padding 在
/// 「宽度由内容决定」的默认布局里够用，但这里日历要撑满容器，
/// 留白得由外层控制，否则算宽度时要跨层扣减，容易算错。
const _kCalendarInset = 8.0;

/// 撑满可用宽度的日历。
///
/// forui 日历的宽度是 `7 × daySize.width` 算出来的**固定值**（触屏预设 44，
/// 即 308px），内部网格 `crossAxisStride` 也直接取 `daySize.width`，
/// 没有任何弹性布局。所以想占满容器只能反过来做：
/// 用 [LayoutBuilder] 拿到可用宽度，除以 7 反算出格子宽度再喂回样式。
///
/// 同时去掉 forui 自带的描边卡片——日历已经躺在浮层的白面卡片里，
/// 再套一层 `ShapeDecoration(border + card 底色)` 就成了「框中框」。
class _StretchedCalendar extends StatelessWidget {
  const _StretchedCalendar({
    required this.control,
    required this.selectionControl,
  });

  final FGridCalendarControl control;
  final FDateSelectionControl selectionControl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kCalendarInset),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 高度仍用主题预设的格子高度：只横向拉伸，竖向保持原比例，
          // 否则窄屏上格子会被拉成扁长方形。
          final base = context.theme.calendarStyle.dayPickerStyle.daySize;
          final width = constraints.maxWidth / DateTime.daysPerWeek;
          return FCalendar.grid(
            control: control,
            selectionControl: selectionControl,
            dayBuilder: _dayBuilder,
            style: FCalendarStyleDelta.delta(
              // 整体替换成透明无描边：融进浮层。
              decoration: const DecorationDelta.value(BoxDecoration()),
              // padding 归零，留白交给外层 Padding，
              // 这样 LayoutBuilder 拿到的宽度就是格子可用的全部宽度。
              padding: const EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
              dayPickerStyle: FCalendarDayPickerStyleDelta.delta(
                daySize: Size(width, base.height),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 弹出日期选择浮层，返回选中的日期（仅年月日，本地时区）；取消返回 null。
Future<DateTime?> showAppDatePicker(
  BuildContext context, {
  required DateTime initial,
}) async {
  // forui 日历的 DateTime 一律是 UTC，进出都要转换。
  final start = DateTime.utc(2000);
  final end = DateTime.utc(2100, 12, 31);
  var selected = DateTime.utc(initial.year, initial.month, initial.day);

  // control 在 builder 外创建：浮层重建时实例不变，日历才不会重置到当月。
  final control = FGridCalendarControl(
    start: start,
    end: end,
    initial: selected,
  );
  final selectionControl = FDateSelectionControl.managedSingle(
    initial: selected,
    toggleable: false,
    onChange: (value) {
      if (value != null) selected = value;
    },
  );

  final result = await showFSheet<DateTime>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (sheetContext) => _SheetShell(
      title: '选择日期',
      onConfirm: () => Navigator.pop(sheetContext, selected),
      child: _StretchedCalendar(
        control: control,
        selectionControl: selectionControl,
      ),
    ),
  );
  if (result == null) return null;
  return DateTime(result.year, result.month, result.day);
}

/// 弹出时间选择浮层（24 小时滚轮），取消返回 null。
Future<TimeOfDay?> showAppTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
}) async {
  var selected = FTime(initial.hour, initial.minute);
  final control = FTimePickerControl.managed(
    initial: selected,
    onChange: (value) => selected = value,
  );

  final result = await showFSheet<FTime>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (sheetContext) => _SheetShell(
      title: '选择时间',
      onConfirm: () => Navigator.pop(sheetContext, selected),
      child: SizedBox(
        height: 180,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          // hour24 固定 24 小时制：记账场景不需要 AM/PM，也避免跟随
          // 系统设置导致同一版本在不同手机上排版不一致。
          child: FTimePicker(control: control, hour24: true),
        ),
      ),
    ),
  );
  if (result == null) return null;
  return TimeOfDay(hour: result.hour, minute: result.minute);
}

/// 弹出日期区间选择浮层，返回 `[start, endExclusive)` 半开区间；取消返回 null。
///
/// 交互：点第一下定起点，点第二下定终点（点到早于起点的日期则改起点）。
/// 再点已选端点会清空选择，此时「确定」置灰——不允许把空区间交回业务层。
///
/// [initial] 传入的也是半开区间，内部会转成 forui 需要的闭区间端点。
/// [firstDate] / [lastDate] 限定可选范围，默认 2000-01-01 ~ 2100-12-31。
Future<LedgerDateRange?> showAppDateRangePicker(
  BuildContext context, {
  required LedgerDateRange initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final result = await showFSheet<LedgerDateRange>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    // 内容需要随选择变化重绘（区间预览文案 + 确定按钮启用态），
    // 所以浮层内容自己是个 StatefulWidget，而不是在这里持有可变量。
    builder: (sheetContext) => _DateRangeSheet(
      initial: initial,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2100, 12, 31),
    ),
  );
  return result;
}

/// 区间选择浮层内容。
///
/// 独立成 StatefulWidget 而不是在闭包里存可变量：选择变化时要同步刷新
/// 顶部区间预览和「确定」的可用态，需要 setState 驱动重建。
class _DateRangeSheet extends StatefulWidget {
  const _DateRangeSheet({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
  });

  final LedgerDateRange initial;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  /// forui 日历的 DateTime 一律是 UTC 且不带时分秒，进出都要转换。
  late final FGridCalendarControl _control;

  /// 当前选中的闭区间端点；null 表示用户把选择清空了。
  (DateTime, DateTime)? _selection;

  @override
  void initState() {
    super.initState();
    // 业务侧是半开区间 [start, endExclusive)，日历要的是闭区间，
    // 所以末端减一天。
    final start = _toUtc(widget.initial.start);
    final end = _toUtc(
      widget.initial.endExclusive.subtract(const Duration(days: 1)),
    );
    _selection = (start, end);
    // control 在 State 里创建：浮层重建时实例不变，日历才不会跳回当月。
    _control = FGridCalendarControl(
      start: _toUtc(widget.firstDate),
      end: _toUtc(widget.lastDate),
      initial: start,
    );
  }

  static DateTime _toUtc(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  /// 半开区间：末端 +1 天，与 [LedgerDateRange] 的约定一致。
  LedgerDateRange? get _range {
    final selection = _selection;
    if (selection == null) return null;
    final (start, end) = selection;
    return LedgerDateRange(
      DateTime(start.year, start.month, start.day),
      DateTime(end.year, end.month, end.day).add(const Duration(days: 1)),
    );
  }

  /// 顶部预览文案：`2026年3月1日 - 2026年3月15日 · 15 天`。
  String get _summary {
    final range = _range;
    if (range == null) return '请选择起止日期';
    final start = range.start;
    final end = range.endExclusive.subtract(const Duration(days: 1));
    final startText = '${start.year} 年 ${start.month} 月 ${start.day} 日';
    // 同年时终点省略年份，避免一行文案过长换行。
    final endText = end.year == start.year
        ? '${end.month} 月 ${end.day} 日'
        : '${end.year} 年 ${end.month} 月 ${end.day} 日';
    return '$startText - $endText · ${range.dayCount} 天';
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    return _SheetShell(
      title: '选择日期区间',
      // 选择被清空时禁用确定：空区间对统计毫无意义，
      // 直接拦在浮层里比让业务层兜底更合理。
      onConfirm: range == null ? null : () => Navigator.pop(context, range),
      subtitle: _summary,
      child: _StretchedCalendar(
        control: _control,
        // liftedRange 把选择状态交给本 State 持有，
        // 这样 setState 能同时刷新日历和顶部预览，两者不会脱节。
        selectionControl: FDateSelectionControl.liftedRange(
          value: _selection,
          onChange: (value) => setState(() => _selection = value),
        ),
      ),
    );
  }
}

/// 日历格子：只画数字。
///
/// forui 默认用 `DateFormat.d(locale)`，中文 locale 下会渲染成「23日」，
/// 在 40px 宽的格子里挤成两行。日期网格的列头已经说明了语境，日号不需要单位。
Widget _dayBuilder(
  BuildContext context,
  FCalendarDayStyles styles,
  FLocalizations localizations,
  DateTime date,
  Set<FCalendarDayVariant> variants,
) {
  final style = styles.resolve(variants);
  return DecoratedBox(
    decoration: style.background,
    child: DecoratedBox(
      decoration: style.foreground,
      child: Center(child: Text('${date.day}', style: style.textStyle)),
    ),
  );
}

/// 选择器浮层外壳：白面 + 顶部大圆角 + 抓手 + 取消/确定。
class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.title,
    required this.onConfirm,
    required this.child,
    this.subtitle,
  });

  final String title;

  /// null 表示当前不可确认（例如区间未选全），按钮置灰不可点。
  final VoidCallback? onConfirm;
  final Widget child;

  /// 标题下方的一行辅助说明，区间选择用它做实时预览。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final subtitle = this.subtitle;
    // forui 的 sheet 不像 Material 的 bottom sheet 自带 Material 祖先，
    // 而壳内用了 InkWell，所以这里必须自己铺一层 Material。
    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: Row(
                children: [
                  _SheetAction(
                    label: '取消',
                    onTap: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              fontSize: 12,
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _SheetAction(label: '确定', primary: true, onTap: onConfirm),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;

  /// null 表示禁用：InkWell 不响应，文字降到 inactive。
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    final Color color;
    if (!enabled) {
      color = colors.inactive;
    } else {
      color = primary ? colors.primary : colors.muted;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
