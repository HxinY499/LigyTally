import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 对比度相关的色彩换算。
///
/// 放在 core/theme 而不是各自的样式文件里：统计页 Hero 渐变和记账页摘要卡
/// 都要「按主题色重染卡面、同时钉住卡面亮度」，两处各抄一份的话，以后调
/// 阈值只会改到一边。

/// WCAG 2.1 相对亮度。
double relativeLuminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// 沿 HSL 明度轴二分，把 [color] 调到相对亮度 [target]，色相与饱和度不动。
///
/// 只动明度，是因为 HSL 明度相同时不同色相的实际亮度差很多（青比蓝亮得多）：
/// 换主题色时只转色相，压在卡面上的白字对比度会掉一半。钉住相对亮度才能让
/// 「选了哪个主题色」和「卡面上的字看不看得清」彻底解耦。
///
/// 明度与相对亮度单调同向，所以二分一定收敛；固定 12 步而不是「直到收敛」，
/// 是为了让耗时可预测——调用点都在卡片的 build 里，每次重建都会跑。
Color withRelativeLuminance(Color color, double target) {
  final hsl = HSLColor.fromColor(color);
  var low = 0.0;
  var high = 1.0;
  var result = color;
  for (var i = 0; i < 12; i++) {
    final mid = (low + high) / 2;
    result = hsl.withLightness(mid).toColor();
    if (relativeLuminance(result) < target) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return result;
}
