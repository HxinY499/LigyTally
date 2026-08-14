import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/theme/app_theme.dart';

/// 备份密码输入弹窗：圆角白卡 + 一个输入框 + 竖排两颗撑满宽度的按钮。
///
/// 与 [showAppConfirmDialog] 共用一套视觉。刻意**不用** Material [AlertDialog]：
/// 它标题左对齐、输入框顶着系统默认的 label 浮动动画、两颗按钮挤在右下角，
/// 和 app 里其它浮层完全两个长相。
///
/// 密码只在这里输一次、没有二次确认，输错了备份自己都打不开，所以给了
/// 一个明码开关。返回 null 表示取消；返回空串表示用户选择不加密。
Future<String?> showAppPasswordDialog(
  BuildContext context, {
  required String title,
  String confirmLabel = '继续',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _PasswordDialog(title: title, confirmLabel: confirmLabel),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title, required this.confirmLabel});

  final String title;
  final String confirmLabel;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final radius = radii.blockAll;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: radii.sheetAll),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.4,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '留空表示不加密',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: colors.muted),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: TextStyle(fontSize: 15, color: colors.ink),
              cursorColor: colors.primary,
              decoration: InputDecoration(
                hintText: '密码',
                hintStyle: TextStyle(fontSize: 15, color: colors.inactive),
                filled: true,
                fillColor: colors.canvas,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: radius,
                  borderSide: const BorderSide(color: Colors.transparent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: radius,
                  borderSide: const BorderSide(color: Colors.transparent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: radius,
                  borderSide: BorderSide(color: colors.primary),
                ),
                suffixIcon: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _obscure = !_obscure),
                  child: Icon(
                    _obscure ? FLucideIcons.eye : FLucideIcons.eyeOff,
                    size: 18,
                    color: colors.muted,
                  ),
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _submit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.primary, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: radii.sheetAll),
                ),
                child: Text(
                  widget.confirmLabel,
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
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: colors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: radii.sheetAll),
                ),
                child: const Text(
                  '取消',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
