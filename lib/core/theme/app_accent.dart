import 'package:flutter/material.dart';

/// 交互强调色。只替换色板里跟着 [AppColors.primary] 走的字段
/// （主色、浅底、按下/水波、Hero 蓝阴影），支出红 / 收入绿 / 摘要黄不动。
///
/// 预设而不是自由取色：随手记的场景里对比度比「个性」重要，
/// 开放色盘很容易选出压白字不够、或和收支语义色撞车的颜色。
enum AppAccent {
  blue('蓝', Color(0xFF5190F2), Color(0xFF6FA5F5)),
  teal('青', Color(0xFF2A9B94), Color(0xFF4DB8B0)),
  indigo('靛', Color(0xFF5C6AE8), Color(0xFF8894F5)),
  purple('紫', Color(0xFF8B5FDB), Color(0xFFA98AE8)),
  pink('粉', Color(0xFFD4537E), Color(0xFFE87A9C)),
  orange('橙', Color(0xFFE07A2F), Color(0xFFEE9A55));

  const AppAccent(this.label, this.light, this.dark);

  final String label;

  /// 浅色皮肤下的主色。
  final Color light;

  /// 深色皮肤下的主色：比 [light] 更亮，否则会糊进深底。
  final Color dark;

  Color primaryOf(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static AppAccent fromName(String? name) {
    for (final value in AppAccent.values) {
      if (value.name == name) return value;
    }
    return AppAccent.blue;
  }
}
