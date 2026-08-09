import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// 应用统一开关壳，转发到forui 的 [FSwitch]。
///
/// 薄封装作为「注入锚点」：以后想统一开关色/ 触感，只改这一处。
/// 业务页一律用 [AppSwitch]，不裸用 FSwitch。
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChange,
    this.label,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool>? onChange;
  final Widget? label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FSwitch(
      value: value,
      onChange: onChange,
      label: label,
      enabled: enabled,
    );
  }
}
