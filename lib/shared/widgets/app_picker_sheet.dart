/// 日期 / 时间选择的底部浮层。
///
/// 替代 Material 的 `showDatePicker` / `showTimePicker`——那两个弹窗自带
/// Material 的视觉语言（大圆角对话框、涟漪、独立配色），和本应用的
/// 「白面 + 淡描边 + 扁平」调性冲突。这里统一用 forui 的 FCalendar /
/// FTimePicker 作为内容，套同一个 `_SheetShell` 外壳，保证两者观感一致。
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/theme/app_theme.dart';

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
      child: Center(
        child: FCalendar.grid(
          control: control,
          selectionControl: selectionControl,
          dayBuilder: _dayBuilder,
        ),
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
  });

  final String title;
  final VoidCallback onConfirm;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // forui 的 sheet 不像 Material 的 bottom sheet 自带 Material 祖先，
    // 而壳内用了 InkWell，所以这里必须自己铺一层 Material。
    return Material(
      color: AppColors.surface,
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
                color: AppColors.line,
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
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: primary ? AppColors.primary : AppColors.muted,
            fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
