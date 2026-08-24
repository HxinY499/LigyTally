import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 从下方弹出的月份选择器：两列滚轮（年/月），iOS 风。
///
/// 明细页吸顶月份条和日历页周期条共用这一份：同一个 App 里「点月份跳到
/// 哪个月」出现两套滚轮，只会让人以为某处坏了。
///
/// 用 `showGeneralDialog` + 缩放淡入，返回选中的 [DateTime]（日固定为 1）。
Future<DateTime?> showMonthPicker(
  BuildContext context, {
  required DateTime initial,
}) {
  return showGeneralDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: context.colors.barrier,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, a, b) => _MonthPickerDialog(initial: initial),
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

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initial});

  final DateTime initial;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  /// 年份范围以「今年 ± 20」为窗口，够用又不至于滚太久。
  static const _yearsBack = 20;
  static const _yearsForward = 20;

  late final List<int> _years;
  late int _year;
  late int _month;
  late final FixedExtentScrollController _yearController;
  late final FixedExtentScrollController _monthController;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _years = [
      for (var y = now.year - _yearsBack; y <= now.year + _yearsForward; y++) y,
    ];
    _year = widget.initial.year;
    _month = widget.initial.month;
    final yearIndex = _years.indexOf(_year).clamp(0, _years.length - 1);
    _yearController = FixedExtentScrollController(initialItem: yearIndex);
    _monthController = FixedExtentScrollController(initialItem: _month - 1);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Material(
          color: colors.surface,
          borderRadius: context.radii.sheetAll,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_year 年 $_month 月',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 190,
                  child: Row(
                    children: [
                      Expanded(
                        child: _WheelColumn(
                          controller: _yearController,
                          itemCount: _years.length,
                          onChanged: (index) =>
                              setState(() => _year = _years[index]),
                          labelBuilder: (index) => '${_years[index]}年',
                        ),
                      ),
                      Expanded(
                        child: _WheelColumn(
                          controller: _monthController,
                          itemCount: 12,
                          onChanged: (index) =>
                              setState(() => _month = index + 1),
                          labelBuilder: (index) =>
                              '${(index + 1).toString().padLeft(2, '0')}月',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(DateTime(_year, _month)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.primary,
                      side: BorderSide(color: colors.primary, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: context.radii.sheetAll,
                      ),
                    ),
                    child: const Text(
                      '确定',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 与「确定」同宽同高：一长一短会看着像没对齐，
                // 也和 showAppConfirmDialog 的按钮区保持一致。
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
                      '取消',
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

/// 单列滚轮：iOS `CupertinoPicker` 风格。选中项加粗黑，周边项灰色渐弱。
class _WheelColumn extends StatefulWidget {
  const _WheelColumn({
    required this.controller,
    required this.itemCount,
    required this.onChanged,
    required this.labelBuilder,
  });

  final FixedExtentScrollController controller;
  final int itemCount;
  final ValueChanged<int> onChanged;
  final String Function(int index) labelBuilder;

  @override
  State<_WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<_WheelColumn> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.controller.initialItem;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return CupertinoPicker.builder(
      scrollController: widget.controller,
      itemExtent: 38,
      onSelectedItemChanged: (index) {
        setState(() => _selected = index);
        widget.onChanged(index);
      },
      childCount: widget.itemCount,
      selectionOverlay: const SizedBox.shrink(),
      itemBuilder: (context, index) {
        final offset = (index - _selected).abs();
        final selected = offset == 0;
        final alpha = selected
            ? 1.0
            : offset == 1
            ? 0.55
            : offset == 2
            ? 0.28
            : 0.14;
        return Center(
          child: Text(
            widget.labelBuilder(index),
            style: TextStyle(
              fontSize: selected ? 22 : 17,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: colors.ink.withValues(alpha: alpha),
            ),
          ),
        );
      },
    );
  }
}
