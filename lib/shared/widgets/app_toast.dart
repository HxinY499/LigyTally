import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../core/theme/app_theme.dart';

/// toast 的语义级别。业务页只表达「这是什么性质的提示」，
/// 图标、颜色、时长由本文件统一决定。
enum AppToastLevel {
  /// 中性信息，如「已保存」以外的一般结果反馈
  info,

  /// 操作成功
  success,

  /// 失败 / 错误
  error,
}

/// 应用统一 toast 入口。
///
/// 交互形态（触屏顶部居中、滑动消失、堆叠展开）来自 forui 预设，
/// 视觉基线（圆角/阴影/字号/内边距）来自 [buildForuiTheme] 里的
/// `toasterStyle`；本文件只负责按语义补上图标和强调色。
///
/// 业务页一律用 [showAppToast]，不裸用 `showFToast`——
/// 以后要统一换图标、加触感、加埋点，只改这里。
void showAppToast(
  BuildContext context, {
  required String message,
  String? description,
  AppToastLevel level = AppToastLevel.info,
  Duration? duration,
  Widget Function(BuildContext context, FToasterEntry entry)? suffixBuilder,
}) {
  final isError = level == AppToastLevel.error;
  showFToast(
    context: context,
    variant: isError ? FToastVariant.destructive : FToastVariant.primary,
    // 非错误级别在主题基线上只改图标色，其余保持全局一致
    style: isError
        ? const FToastStyleDelta.context()
        : FToastStyleDelta.delta(
            iconStyle: IconThemeDataDelta.delta(color: _accent(level)),
          ),
    icon: Icon(_icon(level)),
    title: Text(message),
    description: description == null ? null : Text(description),
    suffixBuilder: suffixBuilder,
    duration: duration ?? _defaultDuration(level),
  );
}

IconData _icon(AppToastLevel level) => switch (level) {
  AppToastLevel.info => FLucideIcons.info,
  AppToastLevel.success => FLucideIcons.circleCheck,
  AppToastLevel.error => FLucideIcons.circleAlert,
};

Color _accent(AppToastLevel level) => switch (level) {
  AppToastLevel.info => AppColors.primary,
  AppToastLevel.success => AppColors.income,
  AppToastLevel.error => AppColors.expense,
};

/// 成功提示看一眼就够，错误要留足阅读时间。
Duration _defaultDuration(AppToastLevel level) => switch (level) {
  AppToastLevel.success => const Duration(seconds: 2),
  AppToastLevel.info => const Duration(seconds: 3),
  AppToastLevel.error => const Duration(seconds: 4),
};
