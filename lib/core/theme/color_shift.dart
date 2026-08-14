import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 「按主题色重染手挑色值」用到的两种色彩换算。
///
/// 放在 core/theme 而不是各自的样式文件里：统计页概览 Hero 卡和记账页月度
/// 摘要卡共用同一条渐变（见 `AppColors.heroGradient`），统计页的图表调色板
/// 也要跟着主题色转色相。两处各抄一份的话，以后调换算只会改到一边。

/// 转色相，饱和度、明度、透明度全部保持原样。
///
/// 只动色相是为了保住原手挑色值里的明度 / 饱和度走势；[degrees] 为 0 时
/// 原样返回，而不是走一趟 HSL 往返——默认主题下所有手挑色值必须逐位不变，
/// 全透明的色停（面积填充的末端）也不能在往返里丢掉透明度。
Color rotateHue(Color color, double degrees) {
  if (degrees == 0) return color;
  final hsl = HSLColor.fromColor(color);
  return hsl.withHue((hsl.hue + degrees) % 360).toColor();
}

/// 按倍率缩饱和度，色相、明度、透明度不动。
///
/// 用倍率而不是绝对值：手挑色停之间本来就有饱和度落差（Hero 渐变从 0.86
/// 收到 0.70），换成绝对值会把这层落差压平。
Color scaleSaturation(Color color, double scale) {
  if (scale == 1) return color;
  final hsl = HSLColor.fromColor(color);
  return hsl.withSaturation((hsl.saturation * scale).clamp(0.0, 1.0)).toColor();
}

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
/// 配合 [rotateHue] 用：HSL 明度相同时不同色相的实际亮度差很多（青比蓝亮
/// 得多），单纯转色相会让压在卡面上的白字对比度掉一半。转完色相再钉回原色
/// 停的相对亮度，卡面深浅才与「选了哪个主题色」无关。
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
