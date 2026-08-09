import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// 按钮语义变体，映射到 forui 的 FButtonVariant。
///
/// 业务页只依赖这个 enum，不直接引用 forui 的 FButtonVariant，
/// 以后要整体调整按钮风格（如换主色态、加统一动效）只改本文件。
enum AppButtonVariant { primary, secondary, outline, ghost, destructive }

FButtonVariant _toForui(AppButtonVariant v) => switch (v) {
  AppButtonVariant.primary => FButtonVariant.primary,
  AppButtonVariant.secondary => FButtonVariant.secondary,
  AppButtonVariant.outline => FButtonVariant.outline,
  AppButtonVariant.ghost => FButtonVariant.ghost,
  AppButtonVariant.destructive => FButtonVariant.destructive,
};

/// 应用统一按钮壳，转发到 forui 的 [FButton]。
///
/// 现在是薄封装（几乎等于直接用 FButton），价值在于「注入锚点」：
/// 以后想给所有主按钮加统一动效 / 触感 / 埋点，只改这一处，
/// 不必翻遍每个页面。业务页一律用 [AppButton]，不裸用 FButton。
///
/// [onPress] 为 null 时按钮自动进入禁用态（forui 原生语义）。
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.onPress,
    required this.child,
    this.variant = AppButtonVariant.primary,
    this.prefix,
    this.suffix,
  });

  final VoidCallback? onPress;
  final Widget child;
  final AppButtonVariant variant;
  final Widget? prefix;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return FButton(
      onPress: onPress,
      variant: _toForui(variant),
      prefix: prefix,
      suffix: suffix,
      child: child,
    );
  }
}

/// 纯图标按钮壳，转发到 forui 的 [FButton.icon]。
///
/// 用于只有一个图标、没有文字的按钮（如月份切换箭头、加图片）。
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.onPress,
    required this.icon,
    this.variant = AppButtonVariant.outline,
  });

  final VoidCallback? onPress;
  final Widget icon;
  final AppButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    return FButton.icon(
      onPress: onPress,
      variant: _toForui(variant),
      child: icon,
    );
  }
}
