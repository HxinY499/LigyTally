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
    this.border,
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

  final BoxBorder? border;
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
