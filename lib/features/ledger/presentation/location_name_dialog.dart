import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 改地点名。返回 null 表示取消；空串表示清掉文案、只留坐标。
Future<String?> showLocationNameDialog(
  BuildContext context, {
  required String initial,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _LocationNameDialog(initial: initial),
  );
}

class _LocationNameDialog extends StatefulWidget {
  const _LocationNameDialog({required this.initial});

  final String initial;

  @override
  State<_LocationNameDialog> createState() => _LocationNameDialogState();
}

class _LocationNameDialogState extends State<_LocationNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

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
              '地点',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.4,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: TextStyle(fontSize: 15, color: colors.ink),
              cursorColor: colors.primary,
              decoration: InputDecoration(
                hintText: '店名或地点',
                hintStyle: TextStyle(fontSize: 15, color: colors.inactive),
                filled: true,
                fillColor: colors.canvasBase,
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
                child: const Text(
                  '确定',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
