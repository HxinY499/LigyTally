import 'package:flutter/material.dart';

/// Hero 卡的卡面样式。
///
/// Hero 卡是全应用面积最大的一块彩色面（明细页月度摘要 + 统计页概览，
/// 同一个视觉元素在两屏上的两次出现）。它换一副样子，整个 app 的第一印象
/// 就换了，所以这是外观设置里性价比最高的一档。
///
/// 三档不是「同一张卡的三种滤镜」，[outline] 会把卡面从深彩底翻成白面——
/// 因此**前景色必须跟着卡面一起换**，不能继续写死白色。这就是为什么
/// 这里给的是 [HeroSkin] 这样一个「卡面 + 前景」的整包，而不是一个 `Gradient?`：
/// 只换背景、白字留在原地，[outline] 档下卡上的数字会直接消失。
enum HeroCardStyle {
  /// 主题色三色停斜向渐变（历史默认）。
  gradient('渐变'),

  /// 取渐变的中间色停铺成实底：比渐变安静，深色皮肤下尤其不刺眼。
  solid('纯色'),

  /// 白面 + 主色描边，数字用墨色。整屏最重的那块彩色面消失，
  /// 页面回到「全是白卡」的极简观感。
  outline('描边');

  const HeroCardStyle(this.label);

  final String label;

  static const fallback = HeroCardStyle.gradient;

  static HeroCardStyle decode(String? name) {
    for (final style in values) {
      if (style.name == name) return style;
    }
    return fallback;
  }
}

/// 一整套 Hero 卡卡面：背景 + 描边 + 阴影 + 压在上面的四级前景色。
///
/// 卡面和前景必须成套发放，不能让调用点各取一半——见 [HeroCardStyle] 文档。
/// 调用点写 `final hero = context.colors.hero;`，然后
/// `BoxDecoration(gradient: hero.gradient, color: hero.color, ...)`：
/// 两个字段总有一个是 null，同时传给 BoxDecoration 也是合法的。
@immutable
class HeroSkin {
  const HeroSkin({
    required this.style,
    this.gradient,
    this.color,
    this.side = BorderSide.none,
    this.sheenGradient,
    required this.shadow,
    required this.foreground,
    required this.foregroundSoft,
    required this.foregroundFaint,
    required this.divider,
    required this.highlight,
    required this.splash,
  });

  final HeroCardStyle style;

  /// 渐变卡面；非渐变档为 null。
  final Gradient? gradient;

  /// 实底卡面；渐变档为 null。
  final Color? color;

  /// 卡片描边。只有 [HeroCardStyle.outline] 档非 none。
  ///
  /// 是 [BorderSide] 而不是 [BoxBorder]：卡片形状走超椭圆
  /// （见 `AppRadius.cardShape`），而超椭圆只能画在 [ShapeDecoration] 里，
  /// 后者的描边由 [OutlinedBorder.side] 提供，不接受 BoxBorder。
  final BorderSide side;

  /// 高光层的渐变，null 表示这一档不铺高光。见 [sheen]。
  ///
  /// 强度随皮肤走（[kHeroSheenLight] / [kHeroSheenDark]），所以由 `AppColors.hero`
  /// 挑好了传进来，不在本类里现算——本类拿不到当前亮度。
  final Gradient? sheenGradient;

  final List<BoxShadow> shadow;

  /// 主数字色。
  final Color foreground;

  /// 标签色。
  final Color foregroundSoft;

  /// 最弱一档：金额后面的「(元)」这类单位。
  final Color foregroundFaint;

  /// 卡内竖分割线。
  final Color divider;

  /// 卡上图标按钮的按下 / 水波色。
  ///
  /// 不能用全局的 `pressed` / `ripple`（墨色系）：它们是为白面卡片挑的，
  /// 压在深彩卡面上几乎看不见。[outline] 档卡面变白，这两个值也就跟着
  /// 换回全局那一套。
  final Color highlight;
  final Color splash;

  /// 卡面是否为深彩底（决定卡上要不要用浅色前景）。
  bool get isTinted => style != HeroCardStyle.outline;

  /// 卡面装饰。[borderRadius] 由调用点从 `AppRadius` 取。
  ///
  /// 是 [ShapeDecoration] 而不是 [BoxDecoration]：后者只认 `borderRadius`，
  /// 画不出超椭圆。
  ///
  /// ## 为什么纯色 / 描边档也铺一条渐变
  ///
  /// [ShapeDecoration] 断言 `color` 与 `gradient` 不能同时非空，而
  /// `ShapeDecoration.lerp` 是把这两个字段**各自独立**插值的。于是从渐变档
  /// （有 gradient、无 color）过渡到纯色档（无 gradient、有 color）时，中间帧
  /// 两个字段都非空，直接撞上那条断言——外观页的样张就是靠 [AnimatedContainer]
  /// 在这三档之间过渡的，实测会抛异常。
  ///
  /// 所以这里统一只用 `gradient`：纯色档把它的实底表达成一条首尾同色的退化
  /// 渐变。两个色停相同时渲染结果与实色填充没有差别，但 `color` 恒为 null，
  /// 三档之间就都能平滑插值了。
  ///
  /// [color] 字段本身保留不变——它是「这一档的卡面是什么颜色」这个语义值，
  /// 调用点（和测试）仍然读它，只是不再直接交给装饰。
  ShapeDecoration decoration(BorderRadius borderRadius) => ShapeDecoration(
    gradient: gradient ?? _flat(color),
    shadows: shadow,
    shape: RoundedSuperellipseBorder(side: side, borderRadius: borderRadius),
  );

  /// 把一个实色包成首尾同色的退化渐变。见 [decoration]。
  ///
  /// `begin` / `end` 与真渐变保持一致：这两个字段也参与插值，对不上的话
  /// 过渡途中渐变的方向会一起转动。
  static Gradient? _flat(Color? color) => color == null
      ? null
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color],
        );

  /// 压在卡面之上的一层高光，null 表示这一档不需要。
  ///
  /// ## 它解决什么
  ///
  /// 一条纯粹的线性渐变铺满一整块面，观感是「刷了漆的塑料」：亮度沿一个方向
  /// 匀速变化，现实里没有任何被光照亮的物体是这样的。真实光照下最亮的是**离
  /// 光源最近的那个点**，往外按距离衰减——那是一个径向而不是线性的分布。
  ///
  /// 所以这里叠一层从左上角发散的低透明度白，让高光有一个「落点」。它和底下
  /// 那条线性渐变叠加后，亮度分布不再是单向匀速的，卡面才像一个有体积的面。
  ///
  /// 强度必须很低：这一层的作用是打破匀速感，不是画一道光。
  /// 高到能被单独看见时，它就变成一块显眼的白斑了。深浅两套强度不同，
  /// 见 [kHeroSheenLight] / [kHeroSheenDark]。
  ///
  /// [HeroCardStyle.outline] 档返回 null——那一档卡面是白的，白色高光叠上去
  /// 什么也看不见，只是白付一层渲染。
  ShapeDecoration? sheen(BorderRadius borderRadius) {
    final gradient = sheenGradient;
    if (!isTinted || gradient == null) return null;
    return ShapeDecoration(
      gradient: gradient,
      shape: RoundedSuperellipseBorder(borderRadius: borderRadius),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HeroSkin &&
          other.style == style &&
          other.gradient == gradient &&
          other.color == color &&
          other.foreground == foreground);

  @override
  int get hashCode => Object.hash(style, gradient, color, foreground);
}

/// 浅色皮肤下 Hero 卡的高光层。见 [HeroSkin.sheen]。
///
/// 圆心落在卡片左上角**之外**（-0.6, -1.0 已经出了卡的上边界）：光源在画面外
/// 才符合「被斜上方的光照到」的直觉，圆心放在卡内会看出一个同心圆。
/// 半径 1.3 让衰减一路铺到右下角，不至于在卡中间就断出一道边。
const kHeroSheenLight = RadialGradient(
  center: Alignment(-0.6, -1.0),
  radius: 1.3,
  colors: [Color(0x2BFFFFFF), Color(0x00FFFFFF)],
  stops: [0.0, 1.0],
);

/// 深色皮肤下的高光层：峰值收到浅色的六成。
///
/// 同一层白在两套皮肤下的效果不对等。深色页面里这张卡本来就是全屏唯一的亮块，
/// 对比度已经很高，再叠一层浅色那样强度的白，卡片会从「有体积」变成「在发光」
/// ——而深色皮肤刻意压暗 Hero 卡就是为了避免高亮卡刺眼（见
/// `_heroGradientDark`），高光把那一步的效果抵掉一半就没意义了。
const kHeroSheenDark = RadialGradient(
  center: Alignment(-0.6, -1.0),
  radius: 1.3,
  colors: [Color(0x1AFFFFFF), Color(0x00FFFFFF)],
  stops: [0.0, 1.0],
);

/// 深彩卡面上的四级前景色：白色降透明度，而不是给一串灰。
///
/// 灰色压在彩色卡面上会发浊，这是 `SummaryBand` 与 `StatsTokens` 从一开始
/// 就共用的一条规则，这里把它收成 Hero 卡自己的常量。
const kOnHeroStrong = Colors.white;
const kOnHeroSoft = Color(0xCCFFFFFF);
const kOnHeroFaint = Color(0x94FFFFFF);
const kOnHeroDivider = Color(0x33FFFFFF);

/// 深彩卡面上的按下 / 水波色：半透明白。
const kOnHeroHighlight = Color(0x1FFFFFFF);
const kOnHeroSplash = Color(0x24FFFFFF);
