import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 全应用圆角阶梯，可由用户在设置里整体缩放。
///
/// ## 为什么是四档语义，而不是「一个全局圆角值」
///
/// 「统一圆角」不等于「所有东西一个数」：浮层比卡片圆、卡片比卡内小块圆，
/// 这层递进正是层级感的来源，全抹平成一个值反而会让弹窗看着像贴纸。
/// 所以这里定的是**比例固定的四档**，用户能调的是整条阶梯的缩放系数，
/// 四档之间的相对关系永远不变。
///
/// 命名按用途而不是按大小（`sheet` / `card` 而不是 `xl` / `lg`），
/// 与 [AppColors] 同一条规则——调用点看名字就知道该用哪个，
/// 不需要回来数哪一档更大。
///
/// ## 胶囊不在这里
///
/// 徽章、设置里的开关滑块、圆头按钮这类「半径 = 高度一半」的元素不受缩放影响：
/// 它们的圆是**形状**（就是要一个胶囊），不是圆角风格的一档。跟着缩放走的话，
/// 用户选「直角」会把开关滑块和色点一起压成方块，那不是圆角设置该干的事。
/// 这类地方继续写 [pill] 或 `height / 2`。
///
/// 分段选择器（统计页年月日、记账页收支、外观页深浅 / 分类样式 / 账单图片）
/// 走 [block]，和输入框、选项行同一档——那是轨道，不是胶囊。
/// 选直角时它们该一起变方。
@immutable
class AppRadius extends ThemeExtension<AppRadius> {
  const AppRadius({this.scale = 1});

  /// 从最近的 [Theme] 取圆角阶梯。
  ///
  /// 兜底成标准档而不是抛异常：测试里大量 `MaterialApp` 只给了近似主题，
  /// 缺扩展时应该按默认圆角渲染，而不是整屏直角。
  static AppRadius of(BuildContext context) =>
      Theme.of(context).extension<AppRadius>() ?? const AppRadius();

  /// 整条阶梯的缩放系数。0 是直角，1 是设计默认。
  final double scale;

  /// 模态浮层外壳：底部弹层顶角、对话框、通栏操作按钮。
  ///
  /// 全应用最大的一档——浮层压在页面之上，圆角不够大就不像「浮起来的一层」。
  static const sheetBase = 24.0;

  /// 内容卡片：日记账卡、设置分组卡、统计图表卡、月度摘要 Hero 卡。
  static const cardBase = 18.0;

  /// 卡内小块：输入框、选项行、分段轨道、照片。
  static const blockBase = 12.0;

  /// 最小一档：图标底座、色块这类 32px 上下的小方块。
  ///
  /// 小方块用大圆角会直接被吃成圆形，必须比 [blockBase] 再收一档。
  static const chipBase = 10.0;

  /// 胶囊：不参与缩放，见类文档。
  static const pill = 999.0;

  double get sheet => sheetBase * scale;
  double get card => cardBase * scale;
  double get block => blockBase * scale;
  double get chip => chipBase * scale;

  BorderRadius get sheetAll => BorderRadius.circular(sheet);

  /// 底部弹层只圆上面两角，下面两角贴着屏幕边缘。
  BorderRadius get sheetTop =>
      BorderRadius.vertical(top: Radius.circular(sheet));

  BorderRadius get cardAll => BorderRadius.circular(card);

  /// 卡片顶部一段（日记账卡的日期条）：下边贴着卡内分割线，不该有圆角。
  BorderRadius get cardTop => BorderRadius.vertical(top: Radius.circular(card));

  /// 卡片底部一段（分类卡的「添加子分类」行）。
  BorderRadius get cardBottom =>
      BorderRadius.vertical(bottom: Radius.circular(card));
  BorderRadius get blockAll => BorderRadius.circular(block);
  BorderRadius get chipAll => BorderRadius.circular(chip);

  // ------------------------------------------------------- 超椭圆（连续曲率）
  //
  // 以下几个 getter 返回的是**形状**而不是圆角半径，给「一整块面」用：
  // 卡片、Hero 卡、底部弹层。
  //
  // ## 为什么大面要换成超椭圆
  //
  // 普通圆角（[BorderRadius] / `RRect`）在直边与圆弧的接点处曲率是**突变**的：
  // 直线段曲率 0，一进圆弧立刻跳到 1/r。人眼对这个拐点很敏感，半径越大越明显，
  // 观感就是「四个角像是被剪掉的」。超椭圆让曲率连续过渡，角看起来是「长出来」
  // 的——这是 iOS 图标与卡片观感更「贵」的一个隐形来源。
  //
  // 差别随半径增大而增大，所以只有 [card]（18）和 [sheet]（24）这两档值得换；
  // [chip]（10）上肉眼已分不出，而它的调用点是日历格子这类一屏几十个的元素，
  // 换过去只是白付渲染成本（超椭圆比 RRect 贵）。因此**不提供 chipShape**。
  //
  // ## 调用点要跟着换 decoration 类型
  //
  // [BoxDecoration] 只认 `borderRadius`，画不出超椭圆。用这几个 getter 的地方
  // 需要改成 [ShapeDecoration]（它有 `shape` / `color` / `gradient` / `shadows`）
  // 或 `Material(shape: ...)`。`Material` 的 `shape` 与 `borderRadius` 互斥，
  // 传了前者就要删掉后者。

  /// 内容卡片的形状。[side] 默认无描边——卡片靠阴影收边，见
  /// [AppColors.shadowCard] 的说明。
  RoundedSuperellipseBorder cardShape({BorderSide side = BorderSide.none}) =>
      RoundedSuperellipseBorder(side: side, borderRadius: cardAll);

  /// 卡内小块的形状（输入框、分段轨道、照片）。
  RoundedSuperellipseBorder blockShape({BorderSide side = BorderSide.none}) =>
      RoundedSuperellipseBorder(side: side, borderRadius: blockAll);

  /// 底部弹层的形状：只圆上面两角。
  RoundedSuperellipseBorder get sheetTopShape =>
      RoundedSuperellipseBorder(borderRadius: sheetTop);

  /// 居中浮层（对话框）的形状：四角都圆。
  RoundedSuperellipseBorder get sheetShape =>
      RoundedSuperellipseBorder(borderRadius: sheetAll);

  /// forui 组件的圆角令牌。
  ///
  /// 不用 [FBorderRadius.scale]：它会把 `pill` 一起缩放，选「直角」时
  /// forui 开关、徽章会跟着变成方块。这里逐档缩放并把 `pill` 钉死。
  FBorderRadius get forui => FBorderRadius(
    xs2: BorderRadius.circular(4 * scale),
    xs: BorderRadius.circular(6 * scale),
    sm: BorderRadius.circular(8 * scale),
    md: BorderRadius.circular(10 * scale),
    lg: BorderRadius.circular(14 * scale),
    xl: BorderRadius.circular(18 * scale),
    xl2: BorderRadius.circular(22 * scale),
    xl3: BorderRadius.circular(26 * scale),
  );

  @override
  AppRadius copyWith({double? scale}) => AppRadius(scale: scale ?? this.scale);

  @override
  AppRadius lerp(AppRadius? other, double t) {
    if (other == null) return this;
    return AppRadius(scale: lerpDouble(scale, other.scale, t)!);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is AppRadius && other.scale == scale);

  @override
  int get hashCode => scale.hashCode;
}

/// 用户可选的圆角档位。
///
/// 做成枚举而不是连续滑杆：圆角只有「方 / 默认 / 圆」几种观感差别，
/// 17.3px 和 18px 谁也分不出来，而连续值会让主题缓存的键变成无限多个
/// （拖一遍滑杆就灌进几百份主题）。离散档位还能顺便保证每一档都是
/// 设计上验证过的整数比例。
enum AppCornerStyle {
  /// 直角：全部方到底，只留胶囊和圆形。
  sharp('直角', 0),

  /// 微圆：只收掉尖角。
  subtle('微圆', 0.5),

  /// 设计默认。
  standard('标准', 1),

  round('圆润', 1.3),

  extraRound('极圆', 1.6);

  const AppCornerStyle(this.label, this.scale);

  final String label;
  final double scale;

  static const fallback = AppCornerStyle.standard;

  /// 按持久化的名字反查，认不出就回落默认档。
  ///
  /// 认不出包括两种情况：没存过（首次启动），以及存的是旧版本才有的档位
  /// （档位增删后老用户的偏好会变成陌生字符串）。两种都该回到默认而不是崩。
  static AppCornerStyle decode(String? name) {
    for (final style in values) {
      if (style.name == name) return style;
    }
    return fallback;
  }
}
