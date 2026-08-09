import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// 应用统一输入框壳，转发到 forui 的 [FTextField]。
///
/// 薄封装作为「注入锚点」：以后想给所有输入框加统一校验样式 /
/// 聚焦态/ 清除按钮，只改这一处。业务页一律用 [AppTextField]，
/// 不裸用 FTextField / FTextFieldControl。
///
/// 传入已有的 [controller] 即可（内部包成 FTextFieldControl.managed）；
/// 或用 [onChange] 直接监听文本变化（实时搜索场景）。
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.onChange,
    this.label,
    this.hint,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
    this.prefixBuilder,
    this.multiline = false,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.onTap,
  });

  final TextEditingController? controller;

  /// 文本变化回调，参数是当前完整文本（已trim 前的原始值）。
  final ValueChanged<String>? onChange;
  final Widget? label;
  final String? hint;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// forui 的 prefix 构建器，签名为 (context, style, variants)。
  /// 直接复用 forui 的 typedef，避免第三参数类型写错。
  final FFieldIconBuilder<FTextFieldStyle>? prefixBuilder;

  /// 是否多行输入（映射到 FTextField.multiline）。
  final bool multiline;
  final int? maxLength;
  final int? minLines;
  final int maxLines;

  /// 输入框获得点击时的回调（如用于收起自定义键盘）。
  final VoidCallback? onTap;

  FTextFieldControl get _control => FTextFieldControl.managed(
    controller: controller,
    onChange: onChange == null ? null : (value) => onChange!(value.text),
  );

  @override
  Widget build(BuildContext context) {
    if (multiline) {
      return FTextField.multiline(
        control: _control,
        label: label,
        hint: hint,
        autofocus: autofocus,
        maxLength: maxLength,
        minLines: minLines ?? 1,
        maxLines: maxLines,
        onTap: onTap,
      );
    }
    return FTextField(
      control: _control,
      label: label,
      hint: hint,
      autofocus: autofocus,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      prefixBuilder: prefixBuilder,
      maxLength: maxLength,
      minLines: minLines,
      maxLines: maxLines,
      onTap: onTap,
    );
  }
}
