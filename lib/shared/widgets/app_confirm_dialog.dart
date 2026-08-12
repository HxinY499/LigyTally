import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 应用统一的强确认弹窗：圆角白卡 + 语义色描边胶囊「确定」+ 无边框「取消」。
///
/// 刻意**不用** Material 的 [AlertDialog]：它的 actions 是右下角一排小字按钮，
/// 在「删除后不可恢复」这类不可逆操作上按钮太轻、点击热区也小。这里两颗按钮
/// 都撑满内容区宽度、竖向堆叠，主操作在上、取消在下，拇指够得到且不易误触。
///
/// 两颗按钮同宽同高（同一组 padding + 同圆角）——一长一短会看着像没对齐。
///
/// 返回 true 表示用户确认；点取消、点遮罩、返回手势都返回 false。
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',

  /// 「确定」的语义色。删除类操作传支出红（默认），其余可传品牌蓝。
  ///
  /// 缺省值只能写 null 再在 builder 里解析：色板改成 [ThemeExtension] 之后
  /// 支出红不再是编译期常量，没法直接当默认参数值。
  Color? accent,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = context.colors;
      final accentColor = accent ?? colors.expense;
      return Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accentColor,
                    side: BorderSide(color: accentColor, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    confirmLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.ink,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
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
          ),
        ),
      );
    },
  );
  return confirmed == true;
}
