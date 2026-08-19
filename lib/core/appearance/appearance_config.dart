import 'package:flutter/material.dart';

import '../theme/app_accent.dart';
import '../theme/app_density.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/hero_skin.dart';
import '../theme/sign_palette.dart';

/// 深浅皮肤的取值来源。
///
/// [system] 跟随系统，[light] / [dark] 由用户手动锁定。
/// 默认 [system]——记账是「随手掏出手机」的场景，跟随系统才能在夜里
/// 自动变暗，而不是让用户想起来去设置里翻一下。
enum AppThemeMode {
  system('跟随系统'),
  light('浅色'),
  dark('深色');

  const AppThemeMode(this.label);

  final String label;

  ThemeMode get materialMode => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  static const fallback = AppThemeMode.system;

  static AppThemeMode decode(String? name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return fallback;
  }
}

/// 记一笔页里账单图片的展示方式。
///
/// [backdrop] 整页背板：高斯模糊 + 向下渐隐，图只贡献色调与氛围，
/// 模糊强度另由 [AppearanceConfig.backdropBlur] 控制；
/// [polaroid] 拍立得贴纸：清晰的小照片叠成一摞贴在分类区上方，可点开管理。
///
/// 两者互斥而不是叠加：同一张图在一屏里出现两次，清晰那份会把模糊那份
/// 显成脏底，视觉上像没处理干净。
enum TransactionImageStyle {
  backdrop,
  polaroid;

  static const fallback = TransactionImageStyle.backdrop;

  static TransactionImageStyle decode(String? name) {
    for (final style in values) {
      if (style.name == name) return style;
    }
    return fallback;
  }
}

/// 记账页分类选择的展示布局。
///
/// [list] 一级分类纵向列表，二级分类在所属一级下方原地展开；
/// [grid] 一级分类 4 列网格，二级分类面板插入在被展开项所在行的下方。
enum CategoryPickerLayout {
  list,
  grid;

  static const fallback = CategoryPickerLayout.list;

  static CategoryPickerLayout decode(String? name) {
    for (final layout in values) {
      if (layout.name == name) return layout;
    }
    return fallback;
  }
}

/// 底部导航栏的形态。
///
/// [docked] 贴底铺满 + 一道顶线（历史默认）；
/// [floating] 左右留白的悬浮胶囊，带阴影。
///
/// 悬浮档只加外边距、不让内容滚到栏下面：让内容穿过底栏需要三个一级页
/// 各自重算滚动内边距，而用户感知到的「悬浮」全部来自那圈留白和圆角。
enum NavBarStyle {
  docked('贴底'),
  floating('悬浮');

  const NavBarStyle(this.label);

  final String label;

  static const fallback = NavBarStyle.docked;

  static NavBarStyle decode(String? name) {
    for (final style in values) {
      if (style.name == name) return style;
    }
    return fallback;
  }
}

/// 背景模糊半径的取值范围。0 是原图直出（仍有渐隐，只是不糊），
/// 40 往上只剩一片色、看不出还有张照片。
const double kBackdropBlurMin = 0;
const double kBackdropBlurMax = 40;
const double kBackdropBlurDefault = 24;

/// 壁纸浓度（照片透出的比例）的上下限。
///
/// ## 为什么上限是 1.0
///
/// 曾经钉在 0.5，理由是「页面底色要压得住照片，否则卡片外的小字会糊进背景」。
/// 那条上限保护的是两类文字：铬层里的标题（页头、吸顶月份条）和卡片外的分组
/// 小标题。但它是**全局**收紧的——为了护住那几行字，整张照片永远发白，
/// 而浓度滑杆拖到头也看不出「满」是什么样。
///
/// 现在保护范围收窄到真正需要的地方：铬层自己铺一层实色蒙版
///（见 `_kChromeScrimOpacity`），卡片本身一直是实底。于是这条上限可以一路
/// 开到全透明，用户想要「照片就是照片」时真的拿得到。
///
/// 代价说清楚：**卡片外的分组小标题**（设置页那些「偏好」「主题」）在高浓度
/// 下会不好读。它们散落在页面中段，没法像铬层那样给一块局部底，而为它们加
/// 描边或阴影会把整个应用的文字观感拖下去。这是用户自己拧到头才会遇到的
/// 取舍，不该让所有人替它买单。
const double kWallpaperOpacityMin = 0.05;
const double kWallpaperOpacityMax = 1;
const double kWallpaperOpacityDefault = 0.2;

const double kWallpaperBlurMin = 0;
const double kWallpaperBlurMax = 40;
const double kWallpaperBlurDefault = 12;

/// 全局壁纸设置。
@immutable
class WallpaperConfig {
  const WallpaperConfig({
    this.enabled = false,
    this.opacity = kWallpaperOpacityDefault,
    this.blur = kWallpaperBlurDefault,
    this.stamp = 0,
  });

  static const none = WallpaperConfig();

  /// 有没有选过壁纸。为 false 时另外三个字段仍保留上次的值，
  /// 这样「关掉再打开」不用重新调浓度。
  final bool enabled;

  /// 照片透出的比例。页面底色会按 `1 - opacity` 的不透明度铺在照片之上。
  final double opacity;

  final double blur;

  /// 换图时间戳，只用来当图片缓存的 key。
  final int stamp;

  WallpaperConfig copyWith({
    bool? enabled,
    double? opacity,
    double? blur,
    int? stamp,
  }) => WallpaperConfig(
    enabled: enabled ?? this.enabled,
    opacity: opacity ?? this.opacity,
    blur: blur ?? this.blur,
    stamp: stamp ?? this.stamp,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WallpaperConfig &&
          other.enabled == enabled &&
          other.opacity == opacity &&
          other.blur == blur &&
          other.stamp == stamp);

  @override
  int get hashCode => Object.hash(enabled, opacity, blur, stamp);
}

/// 全部外观偏好，一个对象。
///
/// ## 为什么合成一个对象
///
/// 这些项原本是九个独立的 `Notifier` + 九个 SharedPreferences key，各自
/// 「先给默认值、再异步读盘覆盖」。项数少的时候这套写法很省事，加到十几项
/// 之后三个代价同时到期：
///
/// 1. **启动闪一下**。九次独立读盘各自在不同的微任务里回来，锁定深色 + 紧凑 +
///    悬浮底栏的用户会看到版式分几帧重排。合成一个对象后只有一次读盘，
///    可以在 `runApp` 之前 `await` 掉（见 `main.dart`），第一帧就是终态。
/// 2. **备份带不走**。九个 key 要在备份里逐个列举，加一项就要改一次备份格式。
///    一个对象只需要往备份里多塞一个字符串。
///
/// ## 什么不在这里
///
/// - **应用图标**：它改的是 Android launcher 的 activity-alias，属于系统状态
///   而不是 app 内的渲染参数。塞进来会让「恢复备份」变成一个需要重启
///   launcher 的操作。
/// - **快速记账模式**：那是行为，不是外观。
/// - **上次选中的分类**：那是使用痕迹。
@immutable
class AppearanceConfig {
  const AppearanceConfig({
    this.themeMode = AppThemeMode.fallback,
    this.accent = AccentChoice.initial,
    this.corner = AppCornerStyle.fallback,
    this.density = AppDensityLevel.fallback,
    this.motion = MotionLevel.fallback,
    this.trueBlack = false,
    this.signPalette = SignPalette.fallback,
    this.tabularFigures = true,
    this.moneyGrouped = true,
    this.heroStyle = HeroCardStyle.fallback,
    this.navBarStyle = NavBarStyle.fallback,
    this.wallpaper = WallpaperConfig.none,
    this.transactionImageStyle = TransactionImageStyle.fallback,
    this.backdropBlur = kBackdropBlurDefault,
    this.categoryPickerLayout = CategoryPickerLayout.fallback,
  });

  /// 冷启动、以及读盘拿到脏数据时的默认值。
  ///
  /// 全部字段都取「升级上来的老用户看不出变化」的那一档：多了十个开关
  /// 不该让 app 自己换一副样子。唯一的例外是 [tabularFigures] 默认开——
  /// 它只让金额列的小数点对齐，没有人会觉得那是「换了样子」。
  static const initial = AppearanceConfig();

  final AppThemeMode themeMode;
  final AccentChoice accent;
  final AppCornerStyle corner;
  final AppDensityLevel density;
  final MotionLevel motion;

  /// 深色皮肤下把页底压到纯黑（OLED 屏省电，观感更沉）。
  /// 浅色皮肤下这个值不参与渲染，但仍然保留，切回深色时不用重设。
  final bool trueBlack;

  final SignPalette signPalette;

  /// 金额用等宽数字（`FontFeature.tabularFigures`），小数点逐行对齐。
  final bool tabularFigures;

  /// 金额千分位分组（`19,042.60`）。
  final bool moneyGrouped;

  final HeroCardStyle heroStyle;
  final NavBarStyle navBarStyle;
  final WallpaperConfig wallpaper;

  final TransactionImageStyle transactionImageStyle;
  final double backdropBlur;
  final CategoryPickerLayout categoryPickerLayout;

  /// 当前是否该把页底让给壁纸。
  bool get hasWallpaper => wallpaper.enabled;

  AppearanceConfig copyWith({
    AppThemeMode? themeMode,
    AccentChoice? accent,
    AppCornerStyle? corner,
    AppDensityLevel? density,
    MotionLevel? motion,
    bool? trueBlack,
    SignPalette? signPalette,
    bool? tabularFigures,
    bool? moneyGrouped,
    HeroCardStyle? heroStyle,
    NavBarStyle? navBarStyle,
    WallpaperConfig? wallpaper,
    TransactionImageStyle? transactionImageStyle,
    double? backdropBlur,
    CategoryPickerLayout? categoryPickerLayout,
  }) => AppearanceConfig(
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    corner: corner ?? this.corner,
    density: density ?? this.density,
    motion: motion ?? this.motion,
    trueBlack: trueBlack ?? this.trueBlack,
    signPalette: signPalette ?? this.signPalette,
    tabularFigures: tabularFigures ?? this.tabularFigures,
    moneyGrouped: moneyGrouped ?? this.moneyGrouped,
    heroStyle: heroStyle ?? this.heroStyle,
    navBarStyle: navBarStyle ?? this.navBarStyle,
    wallpaper: wallpaper ?? this.wallpaper,
    transactionImageStyle: transactionImageStyle ?? this.transactionImageStyle,
    backdropBlur: backdropBlur ?? this.backdropBlur,
    categoryPickerLayout: categoryPickerLayout ?? this.categoryPickerLayout,
  );

  // ------------------------------------------------------------------ 序列化

  /// 字段分隔符。
  ///
  /// 用 `~` 而不是 `,` / `:` / `|`：[AccentChoice.encode] 内部已经用了 `:`，
  /// 而 `~` 不出现在任何枚举名、数字或路径里。
  static const _sep = '~';

  /// 格式版本前缀。
  ///
  /// 解码时先认这个前缀，认不出就整串丢掉回落默认值。往后加字段**只能
  /// 追加在末尾**，老版本的串会因为「读不到那一位」自动拿到新字段的默认值，
  /// 不需要为每次加字段升一次版本号。只有改动既有字段的含义或顺序才该升版。
  static const _tag = 'LT1';

  /// 序列化成一行紧凑文本。落盘和备份共用这一套，加字段只改一处。
  String encode() {
    return [
      _tag,
      themeMode.name,
      accent.encode(),
      corner.name,
      density.name,
      motion.name,
      _bool(trueBlack),
      signPalette.name,
      _bool(tabularFigures),
      _bool(moneyGrouped),
      heroStyle.name,
      navBarStyle.name,
      transactionImageStyle.name,
      backdropBlur.toStringAsFixed(1),
      categoryPickerLayout.name,
      _bool(wallpaper.enabled),
      wallpaper.opacity.toStringAsFixed(3),
      wallpaper.blur.toStringAsFixed(1),
      wallpaper.stamp.toString(),
    ].join(_sep);
  }

  /// [encode] 的逆。
  ///
  /// **任何**读不出来的字段都单独回落到自己的默认值，而不是整串作废：
  /// 偏好文件和备份包都是外部输入，一个字段被截断不该让用户丢掉其余十四项，
  /// 更不该让 app 起不来。整串作废只在前缀都认不出时发生。
  static AppearanceConfig decode(String? raw) {
    if (raw == null) return initial;
    final parts = raw.trim().split(_sep);
    if (parts.isEmpty || parts.first != _tag) return initial;
    String? at(int index) {
      if (index >= parts.length) return null;
      final value = parts[index].trim();
      return value.isEmpty ? null : value;
    }

    final paperEnabled = _parseBool(at(15)) ?? false;
    return AppearanceConfig(
      themeMode: AppThemeMode.decode(at(1)),
      accent: AccentChoice.decode(at(2)),
      corner: AppCornerStyle.decode(at(3)),
      density: AppDensityLevel.decode(at(4)),
      motion: MotionLevel.decode(at(5)),
      trueBlack: _parseBool(at(6)) ?? false,
      signPalette: SignPalette.decode(at(7)),
      tabularFigures: _parseBool(at(8)) ?? true,
      moneyGrouped: _parseBool(at(9)) ?? true,
      heroStyle: HeroCardStyle.decode(at(10)),
      navBarStyle: NavBarStyle.decode(at(11)),
      transactionImageStyle: TransactionImageStyle.decode(at(12)),
      backdropBlur: _parseDouble(
        at(13),
        fallback: kBackdropBlurDefault,
        min: kBackdropBlurMin,
        max: kBackdropBlurMax,
      ),
      categoryPickerLayout: CategoryPickerLayout.decode(at(14)),
      wallpaper: WallpaperConfig(
        enabled: paperEnabled,
        opacity: _parseDouble(
          at(16),
          fallback: kWallpaperOpacityDefault,
          min: kWallpaperOpacityMin,
          max: kWallpaperOpacityMax,
        ),
        blur: _parseDouble(
          at(17),
          fallback: kWallpaperBlurDefault,
          min: kWallpaperBlurMin,
          max: kWallpaperBlurMax,
        ),
        stamp: int.tryParse(at(18) ?? '') ?? 0,
      ),
    );
  }

  /// 一串文本看起来是不是外观配置。只看前缀，具体字段交给 [decode] 逐个兜底。
  static bool looksLikeCode(String raw) =>
      raw.trim().startsWith('$_tag$_sep');

  static String _bool(bool value) => value ? '1' : '0';

  static bool? _parseBool(String? raw) => switch (raw) {
    '1' => true,
    '0' => false,
    _ => null,
  };

  static double _parseDouble(
    String? raw, {
    required double fallback,
    required double min,
    required double max,
  }) {
    final value = double.tryParse(raw ?? '');
    if (value == null || value.isNaN) return fallback;
    return value.clamp(min, max).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppearanceConfig &&
          other.themeMode == themeMode &&
          other.accent == accent &&
          other.corner == corner &&
          other.density == density &&
          other.motion == motion &&
          other.trueBlack == trueBlack &&
          other.signPalette == signPalette &&
          other.tabularFigures == tabularFigures &&
          other.moneyGrouped == moneyGrouped &&
          other.heroStyle == heroStyle &&
          other.navBarStyle == navBarStyle &&
          other.wallpaper == wallpaper &&
          other.transactionImageStyle == transactionImageStyle &&
          other.backdropBlur == backdropBlur &&
          other.categoryPickerLayout == categoryPickerLayout);

  @override
  int get hashCode => Object.hash(
    themeMode,
    accent,
    corner,
    density,
    motion,
    trueBlack,
    signPalette,
    tabularFigures,
    moneyGrouped,
    heroStyle,
    navBarStyle,
    wallpaper,
    transactionImageStyle,
    backdropBlur,
    categoryPickerLayout,
  );

  @override
  String toString() => 'AppearanceConfig(${encode()})';
}
