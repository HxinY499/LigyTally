/// 记账金额输入表达式：支持「数字 + 加减」的简单链式计算，
/// 例如买菜「3.5+7+12」。只做加减（记账场景足够），左到右顺序求值。
class AmountExpression {
  const AmountExpression._();

  /// 把表达式字符串求值为金额（保留两位小数的double）。
  /// 无法解析或为空时返回 0。
  static double evaluate(String raw) {
    if (raw.isEmpty) return 0;
    final tokens = _tokenize(raw);
    if (tokens.isEmpty) return 0;
    var result = 0.0;
    var sign = 1;
    var expectingOperand = true;
    for (final token in tokens) {
      if (token == '+' || token == '-') {
        // 连续运算符或以运算符结尾：忽略，保持宽容。
        if (expectingOperand) continue;
        sign = token == '+' ? 1 : -1;
        expectingOperand = true;
      } else {
        final value = double.tryParse(token);
        if (value == null) continue;
        result += sign * value;
        expectingOperand = false;
      }
    }
    // 规避浮点误差，按分取整再还原。
    return (result * 100).round() / 100;
  }

  /// 表达式是否含未结算的运算符（用于 UI 是否显示「=」提示）。
  static bool hasOperator(String raw) => raw.contains('+') || raw.contains('-');

  static List<String> _tokenize(String raw) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '+' || ch == '-') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        tokens.add(ch);
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());
    return tokens;
  }
}
