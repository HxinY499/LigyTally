import 'package:flutter/widgets.dart';

import 'app_button.dart';

/// forui 风格的分段选择器：一排按钮，选中态用primary，未选用 outline。
///
/// 替代 Material 的 SegmentedButton，用在账单筛选、收支切换、统计周期等处。
/// 内部走 [AppButton] 壳（不裸用 forui），保持全项目组件封装一致。
///
/// [expanded] 为 true 时按钮平分宽度（撑满一行）；为 false 时按内容宽度排列，
/// 适合放进可横向滚动的场景（如统计页的"日/周/月/年/自定义"）。
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.expanded = true,
    this.spacing = 8,
  });

  final List<AppSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool expanded;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isSelected = segment.value == selected;
      final button = AppButton(
        onPress: () => onChanged(segment.value),
        variant: isSelected
            ? AppButtonVariant.primary
            : AppButtonVariant.outline,
        child: Text(segment.label),
      );
      buttons.add(expanded ? Expanded(child: button) : button);
      if (i < segments.length - 1) buttons.add(SizedBox(width: spacing));
    }
    return Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: buttons,
    );
  }
}

class AppSegment<T> {
  const AppSegment({required this.value, required this.label});

  final T value;
  final String label;
}
