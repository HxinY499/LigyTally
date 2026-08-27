/// 卡面探针：从 widget 树里取「阴影」「渐变」「圆角」，
/// **不关心装饰用的是哪个类**。
///
/// 卡片的装饰类型是实现细节，而且已经变过一次：原来全是
/// [BoxDecoration]（只认 `borderRadius`），换成超椭圆圆角后必须是
/// [ShapeDecoration]（圆角藏在 `shape` 里）。
///
/// 而那批用例真正要锁的是「全应用卡片浮起在同一高度」「卡片自己是 Material，
/// 水波才有地方画」——两条都和装饰类型无关。直接断言 `as BoxDecoration` 的
/// 写法把实现细节焊进了断言，于是换装饰类型时十几条无关的用例一起变红，
/// 却没有任何一条真的失效了。
library;

import 'package:flutter/material.dart';

/// 从任意 [Decoration] 里取阴影。取不到（不是这两种装饰、或没设阴影）返回 null。
List<BoxShadow>? surfaceShadows(Decoration? decoration) => switch (decoration) {
  BoxDecoration(:final boxShadow) => boxShadow,
  ShapeDecoration(:final shadows) => shadows,
  _ => null,
};

/// 从任意 [Decoration] 里取渐变。
Gradient? surfaceGradient(Decoration? decoration) => switch (decoration) {
  BoxDecoration(:final gradient) => gradient,
  ShapeDecoration(:final gradient) => gradient,
  _ => null,
};

/// 若 [gradient] 的所有色停同色（也就是一条**退化**渐变，渲染结果等于实色
/// 填充），返回那个颜色；真渐变或 null 一律返回 null。
///
/// Hero 卡的纯色档与描边档就是这样表达实底的，见 `HeroSkin.decoration`。
/// 判断「这一档是不是实底」要用它，而不是看 `gradient == null`。
Color? flatGradientColor(Gradient? gradient) {
  final colors = gradient?.colors;
  if (colors == null || colors.isEmpty) return null;
  return colors.every((color) => color == colors.first) ? colors.first : null;
}

/// 从任意 [Decoration] 里取圆角。
///
/// [ShapeDecoration] 的圆角在 `shape` 上，且只有 [OutlinedBorder] 的
/// 圆角子类才有——[CircleBorder] 这类返回 null。
BorderRadius? surfaceRadius(Decoration? decoration) => switch (decoration) {
  BoxDecoration(:final borderRadius) => borderRadius?.resolve(null),
  ShapeDecoration(:final shape) => shapeRadius(shape),
  _ => null,
};

/// 从 [ShapeBorder] 里取圆角。认 [RoundedSuperellipseBorder] 与
/// [RoundedRectangleBorder]（迁移期两种都可能出现）。
BorderRadius? shapeRadius(ShapeBorder? shape) => switch (shape) {
  RoundedSuperellipseBorder(:final borderRadius) => borderRadius.resolve(null),
  RoundedRectangleBorder(:final borderRadius) => borderRadius.resolve(null),
  _ => null,
};

/// 从 [Material] 上取圆角：它可能写在 `borderRadius`，也可能藏在 `shape` 里。
BorderRadius? materialRadius(Material material) =>
    material.borderRadius?.resolve(null) ?? shapeRadius(material.shape);
