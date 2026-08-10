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

  /// 把表达式渲染成给人看的字符串。
  ///
  /// 两件事：
  /// 1. **千分位分组**（[grouped]）—— 只给每个数字段的整数部分分组。
  ///    金额卡原先显示裸串：输 `12000` 显示 `12000`，存完到明细页却变
  ///    `¥12,000.00`，同一个数字两种写法。这里与全局 `moneyGrouped` 偏好对齐。
  /// 2. **运算符两侧加空格**，并把 `-` 换成真减号 `−`（与键盘按键字形一致）。
  ///    `3.5+7` 挤在一起容易看成一个数，`3.5 + 7` 一眼能数出几笔。
  ///
  /// 只做展示，不参与 [evaluate]——求值始终以原始表达式为准。
  static String format(String raw, {bool grouped = true}) {
    if (raw.isEmpty) return '';
    final buffer = StringBuffer();
    for (final token in _tokenize(raw)) {
      if (token == '+') {
        buffer.write(' + ');
      } else if (token == '-') {
        buffer.write(' − ');
      } else {
        buffer.write(grouped ? _groupSegment(token) : token);
      }
    }
    return buffer.toString();
  }

  /// 给单个数字段的整数部分加千分位，小数部分原样保留。
  ///
  /// 小数部分既不能补零也不能截断：用户可能正停在 `12.` 或 `12.5` 中间，
  /// 补成 `12.00` 会让显示内容和「下一位按下去落在哪」对不上。
  static String _groupSegment(String segment) {
    final dot = segment.indexOf('.');
    final intPart = dot < 0 ? segment : segment.substring(0, dot);
    final rest = dot < 0 ? '' : segment.substring(dot);
    if (intPart.length <= 3) return '$intPart$rest';
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return '$buffer$rest';
  }

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
