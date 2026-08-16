import 'package:flutter/material.dart';

import '../theme/app_accent.dart';
import '../theme/app_density.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/hero_skin.dart';
import 'appearance_config.dart';

/// 一套成品风格：按一下同时换掉深浅、主题色、圆角、密度、动效、Hero 卡与底栏。
///
/// ## 为什么要有预设，而不是只给逐项开关
///
/// 逐项开关有十几个，全部组合是四位数。多数人并不想做十几次决策，只想
/// 「换一个不难看的样子」；而对我来说，保证六套预设好看是可控的，保证
/// 四位数种组合都好看是不可能的。预设把这两件事对齐了：一次点击拿到一个
/// 验证过的组合，想细调的人再往下翻。
///
/// ## 预设**不**碰哪些字段
///
/// 收支配色、千分位、数字等宽、记账页版式都不在预设里。它们不是「风格」：
/// 用户把支出调成绿色是因为看股票的习惯，把千分位关掉是因为嫌吵，
/// 换个皮肤把这些一起改掉属于偷东西。壁纸同理——那是用户自己的照片。
@immutable
class AppearancePreset {
  const AppearancePreset({
    required this.label,
    required this.caption,
    required this.themeMode,
    required this.accent,
    required this.corner,
    required this.density,
    required this.heroStyle,
    required this.navBarStyle,
    this.motion = MotionLevel.full,
    this.trueBlack = false,
  });

  final String label;

  /// 卡片下方那行小字：说这套风格「是什么感觉」，不重复上面已经看得见的颜色。
  final String caption;

  final AppThemeMode themeMode;
  final AccentChoice accent;
  final AppCornerStyle corner;
  final AppDensityLevel density;
  final HeroCardStyle heroStyle;
  final NavBarStyle navBarStyle;
  final MotionLevel motion;
  final bool trueBlack;

  /// 把这套风格盖到现有配置上，只覆盖风格字段。
  AppearanceConfig applyTo(AppearanceConfig base) => base.copyWith(
    themeMode: themeMode,
    accent: accent,
    corner: corner,
    density: density,
    motion: motion,
    trueBlack: trueBlack,
    heroStyle: heroStyle,
    navBarStyle: navBarStyle,
  );

  /// 当前配置是否正好落在这套风格上。
  ///
  /// 只比 [applyTo] 会写的那些字段——否则用户改一下千分位，
  /// 明明还是「墨夜」的样子，卡片却会集体取消选中。
  bool matches(AppearanceConfig config) =>
      config.themeMode == themeMode &&
      config.accent == accent &&
      config.corner == corner &&
      config.density == density &&
      config.motion == motion &&
      config.trueBlack == trueBlack &&
      config.heroStyle == heroStyle &&
      config.navBarStyle == navBarStyle;

  /// 这套风格用于预览的亮度。跟随系统时用调用方传进来的平台亮度。
  Brightness brightnessFor(Brightness platform) => switch (themeMode) {
    AppThemeMode.system => platform,
    AppThemeMode.light => Brightness.light,
    AppThemeMode.dark => Brightness.dark,
  };
}

/// 内置风格包。
///
/// 六套而不是更多：一行能横滑完，且每套之间的差别一眼看得出。再加就会出现
/// 「这两个有什么区别」——那时候用户会放弃选择，退回逐项开关，预设就白做了。
const kAppearancePresets = <AppearancePreset>[
  AppearancePreset(
    label: '素白',
    caption: '出厂默认',
    themeMode: AppThemeMode.light,
    accent: AccentChoice.preset(AppAccent.blue),
    corner: AppCornerStyle.standard,
    density: AppDensityLevel.standard,
    heroStyle: HeroCardStyle.gradient,
    navBarStyle: NavBarStyle.docked,
  ),
  AppearancePreset(
    label: '墨夜',
    caption: '深色 · 靛蓝',
    themeMode: AppThemeMode.dark,
    accent: AccentChoice.preset(AppAccent.indigo),
    corner: AppCornerStyle.round,
    density: AppDensityLevel.standard,
    heroStyle: HeroCardStyle.gradient,
    navBarStyle: NavBarStyle.docked,
  ),
  AppearancePreset(
    label: '纯黑',
    caption: 'OLED · 紧凑',
    themeMode: AppThemeMode.dark,
    accent: AccentChoice.preset(AppAccent.teal),
    corner: AppCornerStyle.subtle,
    density: AppDensityLevel.compact,
    heroStyle: HeroCardStyle.solid,
    navBarStyle: NavBarStyle.floating,
    trueBlack: true,
  ),
  AppearancePreset(
    label: '奶油',
    caption: '圆润 · 宽松',
    themeMode: AppThemeMode.light,
    accent: AccentChoice.preset(AppAccent.orange),
    corner: AppCornerStyle.extraRound,
    density: AppDensityLevel.relaxed,
    heroStyle: HeroCardStyle.solid,
    navBarStyle: NavBarStyle.floating,
  ),
  AppearancePreset(
    label: '纸感',
    caption: '直角 · 无彩块',
    themeMode: AppThemeMode.light,
    accent: AccentChoice.preset(AppAccent.teal),
    corner: AppCornerStyle.sharp,
    density: AppDensityLevel.compact,
    heroStyle: HeroCardStyle.outline,
    navBarStyle: NavBarStyle.docked,
    motion: MotionLevel.reduced,
  ),
  AppearancePreset(
    label: '霓夜',
    caption: '深色 · 玫红',
    themeMode: AppThemeMode.dark,
    accent: AccentChoice.preset(AppAccent.pink),
    corner: AppCornerStyle.extraRound,
    density: AppDensityLevel.standard,
    heroStyle: HeroCardStyle.gradient,
    navBarStyle: NavBarStyle.floating,
  ),
];

/// 当前配置命中的内置风格，全都不匹配时为 null（即「自定义」）。
AppearancePreset? matchedPreset(AppearanceConfig config) {
  for (final preset in kAppearancePresets) {
    if (preset.matches(config)) return preset;
  }
  return null;
}
