import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 应用统一的强确认弹窗：圆角白卡 + 实心主操作 + 浅灰底取消。
///
/// 刻意**不用** Material 的 [AlertDialog]：它的 actions 是右下角一排小字按钮，
/// 在「删除后不可恢复」这类不可逆操作上按钮太轻、点击热区也小。这里两颗按钮
/// 都撑满内容区宽度、竖向堆叠，主操作在上、取消在下，拇指够得到且不易误触。
///
/// 两颗都是实心胶囊、同宽同高。主操作铺语义色，取消铺浅灰，不再一颗描边、
/// 一颗裸文字。
///
/// 返回 true 表示用户确认；点取消、点遮罩、返回手势都返回 false。
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',

  /// 「确定」的语义色。删除类操作传危险红（默认），其余可传品牌蓝。
  ///
  /// 缺省值只能写 null 再在 builder 里解析：色板改成 [ThemeExtension] 之后
  /// 危险红不再是编译期常量，没法直接当默认参数值。
  Color? accent,

  /// 替换居中的一句 [message]。记账和改账用账单卡，删除仍走 [message]。
  Widget? content,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = context.colors;
      // danger 而不是 expense：确认框默认是给「删除」用的，
      // 而用户可以把支出色翻成绿的。
      final accentColor = accent ?? colors.danger;
      return Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: context.radii.sheetAll),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              content ??
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: colors.ink,
                    ),
                  ),
              const SizedBox(height: 24),
              AppConfirmButtons(
                confirmLabel: confirmLabel,
                onConfirm: () => Navigator.pop(context, true),
                cancelLabel: cancelLabel,
                onCancel: () => Navigator.pop(context, false),
                accent: accentColor,
              ),
            ],
          ),
        ),
      );
    },
  );
  return confirmed == true;
}

/// 通栏的主操作和取消。
///
/// 两颗都是实心胶囊、同宽同高。主操作用语义色铺满，取消用浅灰底。
/// [onCancel] 为空时只画主操作，给只有一颗确认按钮的面板用。
class AppConfirmButtons extends StatelessWidget {
  const AppConfirmButtons({
    super.key,
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel = '取消',
    this.onCancel,
    this.accent,
  });

  final String confirmLabel;
  final VoidCallback? onConfirm;
  final String cancelLabel;
  final VoidCallback? onCancel;

  /// 主操作底色。不传则用品牌蓝。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accentColor = accent ?? colors.primary;
    final onAccent = colors.isDark ? colors.canvasBase : Colors.white;
    final shape = RoundedRectangleBorder(borderRadius: context.radii.sheetAll);
    const padding = EdgeInsets.symmetric(vertical: 13);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: onAccent,
              elevation: 0,
              padding: padding,
              shape: shape,
            ),
            child: Text(
              confirmLabel,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (onCancel != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onCancel,
              style: FilledButton.styleFrom(
                backgroundColor: colors.fill,
                foregroundColor: colors.ink,
                elevation: 0,
                padding: padding,
                shape: shape,
              ),
              child: Text(
                cancelLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
