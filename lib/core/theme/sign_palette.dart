/// 收支两色的方向。
///
/// ## 为什么这是一个设置而不是一条设计决定
///
/// 「支出红、收入绿」在中国大陆的记账语境里是默认，但在港台、日本以及
/// 任何做过股票的人那里是**反的**（红涨绿跌）。同一个用户看同一屏数字，
/// 两种直觉给出的结论正好相反，这不是审美偏好，是会读错账的。
///
/// ## 换向只换「钱的正负」，不换「危险」
///
/// 全应用的红色有两种含义混在一起：账单是支出（钱变少），以及这个操作
/// 会删东西（危险）。前者该跟着这个设置翻，后者绝对不能——翻过去之后
/// 「删除分类」的确认按钮会变成绿的。所以 [AppColors] 里把它们拆成了
/// 两组字段：`expense` / `income` 跟着这里翻，`danger` / `success` 钉死。
enum SignPalette {
  /// 支出红、收入绿。
  warmExpense('红支绿收'),

  /// 支出绿、收入红。
  coolExpense('绿支红收');

  const SignPalette(this.label);

  final String label;

  static const fallback = SignPalette.warmExpense;

  bool get isReversed => this == SignPalette.coolExpense;

  static SignPalette decode(String? name) {
    for (final palette in values) {
      if (palette.name == name) return palette;
    }
    return fallback;
  }
}
