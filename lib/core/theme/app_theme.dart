import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../appearance/appearance_config.dart';
import 'app_accent.dart';
import 'app_density.dart';
import 'app_motion.dart';
import 'app_radius.dart';
import 'color_shift.dart';
import 'hero_skin.dart';
import 'sign_palette.dart';

/// 全应用语义色板。
///
/// 这里是**实例**而不是一堆 `static const`：深浅两套皮肤必须能在运行时切换，
/// 而静态常量只能有一份值。切换靠 [ThemeExtension]——调用点统一写
/// `context.colors.ink`，主题一变，读过色板的 widget 自动重建，
/// 不需要重建整棵树（重建整棵树会丢掉正在填的表单和滚动位置）。
///
/// 命名一律按**用途**而不是按颜色（`ink` / `muted` / `line` 而不是
/// `black` / `gray1` / `gray2`），否则深色模式下「white」字段装着深灰，
/// 每个调用点都要重新猜它到底该用哪个。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brightness,
    required this.ink,
    required this.muted,
    required this.inactive,
    required this.faint,
    required this.canvasBase,
    required this.surface,
    required this.line,
    required this.lineSoft,
    required this.fill,
    required this.primary,
    required this.primarySoft,
    required this.expense,
    required this.expenseSoft,
    required this.income,
    required this.incomeSoft,
    required this.danger,
    required this.dangerSoft,
    required this.success,
    required this.accent,
    required this.pressed,
    required this.ripple,
    required this.barrier,
    required this.shadowCard,
    required this.shadowHeroPrimary,
    this.heroStyle = HeroCardStyle.fallback,
    this.hasWallpaper = false,
  });

  /// 从最近的 [Theme] 取色板。
  ///
  /// 兜底成 [light] 而不是抛异常：测试里大量 `MaterialApp` 只给了近似
  /// Material 主题，缺扩展时应该渲染成浅色而不是整屏红。
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  /// 按亮度和整套外观配置取色板。
  ///
  /// 顺序是**先皮肤、再强调色、最后语义换向**，不能调换：
  /// - 纯黑档是在深色皮肤之上压暗中性轴，必须先选中皮肤；
  /// - [withAccent] 会从 `canvas` 现算 `primarySoft`，所以纯黑要在它之前生效，
  ///   否则纯黑档下的图标底座仍然是普通深色那支；
  /// - 收支换向只是把两组已经定好的颜色对调，放最后最省事，也保证
  ///   [danger] / [success] 不被任何一步碰到。
  ///
  /// 默认蓝 + 全默认档时直接返回 [light] / [dark] 常量实例——测试和缓存
  /// 都按引用比较。
  static AppColors resolve(
    Brightness brightness, [
    AppearanceConfig config = AppearanceConfig.initial,
  ]) {
    var base = brightness == Brightness.dark ? dark : light;
    if (brightness == Brightness.dark && config.trueBlack) {
      base = base.withTrueBlack();
    }
    if (config.hasWallpaper) base = base.copyWith(hasWallpaper: true);
    if (config.heroStyle != HeroCardStyle.fallback) {
      base = base.copyWith(heroStyle: config.heroStyle);
    }
    if (config.accent.preset != AppAccent.blue) {
      base = base.withAccent(config.accent.primaryOf(brightness));
    }
    if (config.signPalette.isReversed) base = base.withReversedSigns();
    return base;
  }

  /// 浅色：奶白页底 + 纯白卡片，文字用带绿的深墨色。
  static const light = AppColors(
    brightness: Brightness.light,
    ink: Color(0xFF17211E),
    muted: Color(0xFF65716D),
    inactive: Color(0xFF9AA3A0),
    faint: Color(0xFFC2CBC6),
    canvasBase: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    line: Color(0xFFDCDCDC),
    lineSoft: Color(0xFFEDEDED),
    fill: Color(0xFFF1F3F2),
    primary: Color(0xFF5190F2),
    primarySoft: Color(0xFFE3EDFD),
    expense: Color(0xFFD55A46),
    expenseSoft: Color(0xFFF8E8E4),
    income: Color(0xFF2E7D32),
    incomeSoft: Color(0xFFE8F5E9),
    danger: Color(0xFFD55A46),
    dangerSoft: Color(0xFFF8E8E4),
    success: Color(0xFF2E7D32),
    accent: Color(0xFFE5A62E),
    pressed: Color(0x0F5190F2),
    ripple: Color(0x0A5190F2),
    barrier: Color(0x73000000),
    shadowCard: _shadowCardLight,
    shadowHeroPrimary: _shadowHeroPrimaryLight,
  );

  /// 深色：沿用品牌 `ink` 的冷绿灰做中性轴，而不是纯黑/纯灰。
  ///
  /// - 页底比卡片**更暗**（`canvas` < `surface`）：深色下阴影几乎不可见，
  ///   卡片只能靠自身更亮才浮得起来，这与浅色模式的逻辑正好相反。
  /// - 品牌蓝、支出红、收入绿全部提亮：原色值是为白底挑的，压在深底上
  ///   对比度不足，文字会糊进背景。
  /// - `pressed` / `ripple` 的透明度要比浅色高一档：深底上 6% 的叠加层
  ///   等于没有反馈。
  static const dark = AppColors(
    brightness: Brightness.dark,
    ink: Color(0xFFE9EFEC),
    muted: Color(0xFFA0ABA6),
    inactive: Color(0xFF79837E),
    faint: Color(0xFF5C6661),
    canvasBase: Color(0xFF101413),
    surface: Color(0xFF1A201E),
    line: Color(0xFF2E3633),
    lineSoft: Color(0xFF242B29),
    fill: Color(0xFF252D2A),
    primary: Color(0xFF6FA5F5),
    primarySoft: Color(0xFF1E2C41),
    expense: Color(0xFFEC7C64),
    expenseSoft: Color(0xFF37231F),
    income: Color(0xFF6BBE70),
    incomeSoft: Color(0xFF1B2C1D),
    danger: Color(0xFFEC7C64),
    dangerSoft: Color(0xFF37231F),
    success: Color(0xFF6BBE70),
    accent: Color(0xFFE9B44C),
    pressed: Color(0x1F6FA5F5),
    ripple: Color(0x146FA5F5),
    barrier: Color(0x99000000),
    shadowCard: _shadowCardDark,
    shadowHeroPrimary: _shadowHeroPrimaryDark,
  );

  final Brightness brightness;

  /// 主文字色。
  final Color ink;

  /// 次级文字：说明、副标题。
  final Color muted;

  /// 未选中态图标 / 文字：比 [muted] 更低饱和。
  /// [muted] 偏绿灰，用在小字上会发脏。
  final Color inactive;

  /// 最弱的图标色：行尾 chevron 这类「在那里但不该抢眼」的元素。
  final Color faint;

  /// 页面底色的**实色**值。
  ///
  /// 与 [canvas] 的区别只在壁纸模式下才显出来，但这个区别是必须的：
  /// `canvas` 有一半的调用点并不是在画页底，而是拿它当一个**前景色**用
  /// （深色皮肤下 FAB 上的加号、强调按钮上的文字、输入框的凹底）。
  /// 那些地方一旦拿到透明，字就直接消失了。所以画页底的写 [canvas]，
  /// 要一个「和页底同色的实色」的写这个。
  final Color canvasBase;

  /// 卡片面色。
  final Color surface;

  /// 描边 / 分割线。
  final Color line;

  /// 更淡的分割线：用于大面积贴边描边（底部导航栏顶线、卡内分组线）。
  /// [line] 在长直线上会压出一道明显的灰边，显脏。
  final Color lineSoft;

  /// 中性填充：二态切换器轨道底、进度槽、占位块。
  final Color fill;

  final Color primary;

  /// 品牌色的低饱和底：图标底座、徽章。
  final Color primarySoft;

  /// 支出色 / 收入色。**方向可以被用户翻转**，见 [SignPalette]。
  /// 只有「这笔钱是正还是负」该用它们。
  final Color expense;
  final Color expenseSoft;
  final Color income;
  final Color incomeSoft;

  /// 危险色：删除按钮、错误提示、表单校验失败。
  ///
  /// 独立于 [expense] 存在，因为它绝不能跟着收支配色翻转——用户为了看
  /// 股票把支出调成绿色，不该顺手把「删除分类」的确认按钮也变成绿的。
  /// 默认皮肤下两者同色，所以这次拆分对默认外观是零变化。
  final Color danger;
  final Color dangerSoft;

  /// 成功色：操作完成的 toast。理由同 [danger]。
  final Color success;

  final Color accent;

  /// 列表项按下时的浅底反馈。
  ///
  /// 白面卡片上的点击反馈：太重会像「选中态」，太轻则等于没有。
  /// 这里取品牌蓝的极低透明度版本，按下时是一层几乎无色的冷灰，
  /// 既能确认「按到了」，又不会在快速滑动列表时闪出一片蓝。
  final Color pressed;

  /// 水波扩散色：比 [pressed] 更淡。
  ///
  /// 水波是动态扩散的，视觉上比静态高亮更「抓眼」，
  /// 因此必须比按下底色更淡，否则点一下会像炸开一朵蓝花。
  final Color ripple;

  /// 模态遮罩色。深色模式要更重，否则浅色浮层压不住同样深的页面。
  final Color barrier;

  /// 中性卡片阴影：白面卡片通用（记账日卡、统计各图表卡）。
  ///
  /// 设计上一律用**两层叠加**而不是单层：
  /// - 近距离一层（offset 1~2、blur 小）压出卡片边界，替代描边。
  ///   描边在浅灰底上会压出一道灰线显脏，用极淡阴影收边更干净。
  /// - 远距离一层（offset 8、blur 大）做柔光，让卡片从背景「浮」起来。
  ///
  /// 单层阴影要么太硬（边界锐利像描边），要么糊成一团灰（把底色压暗），
  /// 两层分工才能既有边界又有空气感。
  final List<BoxShadow> shadowCard;

  /// 主色 Hero 卡阴影（统计页概览卡、记账页月度摘要卡）：带主色调，
  /// 比中性灰更有发光感。
  ///
  /// 彩色卡片配中性灰阴影会显得「脏」——阴影里必须掺入卡片自身的色相。
  final List<BoxShadow> shadowHeroPrimary;

  /// Hero 卡的卡面档位。见 [HeroCardStyle]。
  final HeroCardStyle heroStyle;

  /// 当前是否铺了全局壁纸。只影响 [canvas]（页底让位给壁纸）。
  final bool hasWallpaper;

  bool get isDark => brightness == Brightness.dark;

  /// 页面底色。
  ///
  /// 壁纸模式下是**全透明**：壁纸层（照片 + 压在它上面的那层页面色蒙版）铺在
  /// 整个应用之下，页底只要让开就行。
  ///
  /// 页头和吸顶条不靠这里保可读性——浓度可以一路拖到全透明（见
  /// [kWallpaperOpacityMax]），那时这条蒙版等于没有。它们自己会铺一层局部
  /// 实色，见 `AppChromeGlass`。卡片则一直用 [surface]，是实底。
  Color get canvas => hasWallpaper ? Colors.transparent : canvasBase;

  /// 当前档位下 Hero 卡的整套卡面 + 前景色。
  ///
  /// 三档都在这里现算而不是各存一份：[gradient] 档的色停本身已经是从
  /// 主题色推出来的（见 [heroGradient]），[solid] 只是取它中间那一停，
  /// [outline] 则整套换成白面 + 墨字。存三份的话换主题色时得记着改三处。
  HeroSkin get hero {
    switch (heroStyle) {
      case HeroCardStyle.gradient:
        return HeroSkin(
          style: heroStyle,
          gradient: heroGradient,
          shadow: shadowHeroPrimary,
          foreground: kOnHeroStrong,
          foregroundSoft: kOnHeroSoft,
          foregroundFaint: kOnHeroFaint,
          divider: kOnHeroDivider,
          highlight: kOnHeroHighlight,
          splash: kOnHeroSplash,
        );
      case HeroCardStyle.solid:
        // 取中间色停而不是 primary：色停是「边压暗边降饱和」挑出来的，
        // primary 要压得住白字，直接铺满一张大卡会亮得刺眼。
        final stops = heroGradient.colors;
        return HeroSkin(
          style: heroStyle,
          color: stops[stops.length ~/ 2],
          shadow: shadowHeroPrimary,
          foreground: kOnHeroStrong,
          foregroundSoft: kOnHeroSoft,
          foregroundFaint: kOnHeroFaint,
          divider: kOnHeroDivider,
          highlight: kOnHeroHighlight,
          splash: kOnHeroSplash,
        );
      case HeroCardStyle.outline:
        return HeroSkin(
          style: heroStyle,
          color: surface,
          border: Border.all(color: primary, width: 1.5),
          // 中性阴影而不是带主色的那套：卡面已经是白的，彩色光晕会在
          // 白卡下面露出一圈脏边。
          shadow: shadowCard,
          foreground: ink,
          foregroundSoft: muted,
          foregroundFaint: inactive,
          divider: line,
          highlight: pressed,
          splash: ripple,
        );
    }
  }

  /// Hero 卡渐变：统计页概览卡与记账页月度摘要卡共用的那条卡面。
  ///
  /// 两张卡必须是同一条渐变——它们是同一个视觉元素在两屏上的两次出现，
  /// 各存一份色停的话，以后调其中一张另一张不会跟着变。
  ///
  /// 做法是「手挑三色停 → 转到当前主题色的色相 → 钉回原色停的相对亮度」，
  /// 两步都不能省：
  /// - 不能「从 [primary] 沿明度轴现算」。手挑的色停是边压暗边降饱和的
  ///   （浅色饱和度从 0.86 收到 0.65），只挪明度会得到一支电光蓝，深色那套
  ///   刻意压暗（深页面里高亮卡会刺眼）也一起丢掉。
  /// - 不能只转色相。HSL 明度相同时青色比蓝色亮得多，纯转色相会让青色主题
  ///   下的白字压在 #6BF7ED 上，对比度从 2.56 掉到 1.30，等于看不见。
  ///
  /// 所以卡上白字的对比度与选了哪个主题色无关（但它本身只有 2.56:1，
  /// 靠 38/40px 的字重撑可读性，不是 AA）。
  LinearGradient get heroGradient {
    final rotation = accentHueRotation;
    final saturation = accentSaturationScale;
    final source = isDark ? _heroGradientDark : _heroGradientLight;
    if (rotation == 0 && saturation == 1) return source;
    return LinearGradient(
      begin: source.begin,
      end: source.end,
      colors: [
        for (final stop in source.colors)
          withRelativeLuminance(
            scaleSaturation(rotateHue(stop, rotation), saturation),
            relativeLuminance(stop),
          ),
      ],
      stops: source.stops,
    );
  }

  /// 当前主色相对**默认主色**的色相偏移量（度）。
  ///
  /// 所有「跟着主题色重染」的手挑色值都按这个量转色相。锚点取同一亮度下的
  /// 默认色板，所以默认主题的偏移恒为 0，手挑色值原样返回。
  double get accentHueRotation {
    final anchor = isDark ? dark.primary : light.primary;
    return HSLColor.fromColor(primary).hue - HSLColor.fromColor(anchor).hue;
  }

  /// 当前主色相对默认主色的饱和度倍率。锚点同 [accentHueRotation]。
  ///
  /// [heroGradient] 必须跟着它走：自选强调色开放了饱和度这一维，只转色相的话
  /// 「浓淡」滑到最淡时按钮变灰、而全 app 最大的一块彩色面（Hero 卡）纹丝不动，
  /// 那条滑杆就等于坏的。预设也一起受这条影响——青 / 粉 / 橙 的饱和度本来就
  /// 低于蓝，它们的 Hero 卡会比只转色相时softer 一档，这是把「卡面浓淡跟着
  /// 主色」这条规则补齐的结果。
  double get accentSaturationScale {
    final anchor = isDark ? dark.primary : light.primary;
    final anchorSaturation = HSLColor.fromColor(anchor).saturation;
    if (anchorSaturation == 0) return 1;
    return HSLColor.fromColor(primary).saturation / anchorSaturation;
  }

  /// 只重染强调色家族（主色、浅底、按下/水波、Hero 阴影）。
  /// 支出红 / 收入绿保持原样。
  ///
  /// 两张 Hero 卡（统计页概览、记账页月度摘要）的卡面不在这里重染：
  /// 它们各自从 [primary] 现算，见 `StatsTokens.heroGradient` 与 `SummaryBand`。
  AppColors withAccent(Color primary) {
    final soft = isDark
        ? Color.lerp(primary, canvasBase, 0.78)!
        : Color.lerp(primary, const Color(0xFFFFFFFF), 0.82)!;
    return copyWith(
      primary: primary,
      primarySoft: soft,
      pressed: primary.withValues(alpha: isDark ? 0.12 : 0.06),
      ripple: primary.withValues(alpha: isDark ? 0.08 : 0.04),
      shadowHeroPrimary: isDark
          ? [
              BoxShadow(
                color: Color.lerp(
                  primary,
                  const Color(0xFF000000),
                  0.12,
                )!.withValues(alpha: 0.18),
                offset: const Offset(0, 8),
                blurRadius: 24,
              ),
              const BoxShadow(
                color: Color(0x4D000000),
                offset: Offset(0, 2),
                blurRadius: 6,
              ),
            ]
          : [
              BoxShadow(
                color: primary.withValues(alpha: 0.20),
                offset: const Offset(0, 8),
                blurRadius: 24,
              ),
              BoxShadow(
                color: primary.withValues(alpha: 0.10),
                offset: const Offset(0, 2),
                blurRadius: 6,
              ),
            ],
    );
  }

  /// 把深色皮肤的中性轴压到纯黑（OLED 档）。
  ///
  /// 只动中性轴那五个值，主色 / 收支色 / 阴影一律不碰：纯黑档要的是「页底更黑」，
  /// 不是「整套配色重做」。
  ///
  /// 卡片没有跟着压到纯黑（`#0B0F0E` 而不是 `#000000`）：深色下卡片是靠自己
  /// 比页底更亮才浮起来的（阴影在深底上几乎不可见），页底和卡片同为纯黑会让
  /// 整页糊成一片，反而看不出有卡片。分割线同理要跟着抬一档，
  /// 否则纯黑底上 `#2E3633` 的线会变成三条抢眼的亮痕。
  AppColors withTrueBlack() => copyWith(
    canvasBase: const Color(0xFF000000),
    surface: const Color(0xFF0B0F0E),
    line: const Color(0xFF232A28),
    lineSoft: const Color(0xFF181E1C),
    fill: const Color(0xFF161C1A),
  );

  /// 对调支出色与收入色。见 [SignPalette]。
  ///
  /// [danger] / [dangerSoft] / [success] 刻意不在对调范围里——那才是这次
  /// 把它们从 `expense` / `income` 里拆出来的全部理由。
  AppColors withReversedSigns() => copyWith(
    expense: income,
    expenseSoft: incomeSoft,
    income: expense,
    incomeSoft: expenseSoft,
  );

  /// 状态栏 / 导航栏图标的明暗。深底要浅图标，反之亦然。
  ///
  /// 系统栏底色取 [canvasBase] 而不是 [canvas]：壁纸模式下后者是透明的，
  /// 交给系统会得到一条黑边（Android 不接受透明的导航栏色）。
  SystemUiOverlayStyle get systemOverlayStyle => isDark
      ? SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: canvasBase,
          systemNavigationBarIconBrightness: Brightness.light,
        )
      : SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: canvasBase,
          systemNavigationBarIconBrightness: Brightness.dark,
        );

  @override
  AppColors copyWith({
    Brightness? brightness,
    Color? ink,
    Color? muted,
    Color? inactive,
    Color? faint,
    Color? canvasBase,
    Color? surface,
    Color? line,
    Color? lineSoft,
    Color? fill,
    Color? primary,
    Color? primarySoft,
    Color? expense,
    Color? expenseSoft,
    Color? income,
    Color? incomeSoft,
    Color? danger,
    Color? dangerSoft,
    Color? success,
    Color? accent,
    Color? pressed,
    Color? ripple,
    Color? barrier,
    List<BoxShadow>? shadowCard,
    List<BoxShadow>? shadowHeroPrimary,
    HeroCardStyle? heroStyle,
    bool? hasWallpaper,
  }) => AppColors(
    brightness: brightness ?? this.brightness,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    inactive: inactive ?? this.inactive,
    faint: faint ?? this.faint,
    canvasBase: canvasBase ?? this.canvasBase,
    surface: surface ?? this.surface,
    line: line ?? this.line,
    lineSoft: lineSoft ?? this.lineSoft,
    fill: fill ?? this.fill,
    primary: primary ?? this.primary,
    primarySoft: primarySoft ?? this.primarySoft,
    expense: expense ?? this.expense,
    expenseSoft: expenseSoft ?? this.expenseSoft,
    income: income ?? this.income,
    incomeSoft: incomeSoft ?? this.incomeSoft,
    danger: danger ?? this.danger,
    dangerSoft: dangerSoft ?? this.dangerSoft,
    success: success ?? this.success,
    accent: accent ?? this.accent,
    pressed: pressed ?? this.pressed,
    ripple: ripple ?? this.ripple,
    barrier: barrier ?? this.barrier,
    shadowCard: shadowCard ?? this.shadowCard,
    shadowHeroPrimary: shadowHeroPrimary ?? this.shadowHeroPrimary,
    heroStyle: heroStyle ?? this.heroStyle,
    hasWallpaper: hasWallpaper ?? this.hasWallpaper,
  );

  /// 主题切换时的过渡插值。
  ///
  /// [brightness] 不插值（没有「半深」这种东西），在中点直接翻转，
  /// 与 [ThemeData.lerp] 对 brightness 的处理保持一致，
  /// 否则 forui 组件和本色板会在过渡途中错开一帧明暗。
  ///
  /// [heroStyle] 与 [hasWallpaper] 同理在中点翻转：前者是枚举（没有「半渐变」），
  /// 后者决定 [canvas] 要不要透明，插值出来的半透明页底会让壁纸在过渡途中
  /// 忽隐忽现。
  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    final late = t >= 0.5;
    return AppColors(
      brightness: late ? other.brightness : brightness,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      inactive: Color.lerp(inactive, other.inactive, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      canvasBase: Color.lerp(canvasBase, other.canvasBase, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineSoft: Color.lerp(lineSoft, other.lineSoft, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      expenseSoft: Color.lerp(expenseSoft, other.expenseSoft, t)!,
      income: Color.lerp(income, other.income, t)!,
      incomeSoft: Color.lerp(incomeSoft, other.incomeSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      pressed: Color.lerp(pressed, other.pressed, t)!,
      ripple: Color.lerp(ripple, other.ripple, t)!,
      barrier: Color.lerp(barrier, other.barrier, t)!,
      shadowCard: BoxShadow.lerpList(shadowCard, other.shadowCard, t)!,
      shadowHeroPrimary: BoxShadow.lerpList(
        shadowHeroPrimary,
        other.shadowHeroPrimary,
        t,
      )!,
      heroStyle: late ? other.heroStyle : heroStyle,
      hasWallpaper: late ? other.hasWallpaper : hasWallpaper,
    );
  }
}

/// 色值用带蓝的深灰 `#101828` 而不是纯黑——纯黑阴影在浅灰底上会发脏，
/// 略带冷色调更接近真实环境光。
const _shadowCardLight = [
  BoxShadow(color: Color(0x0A101828), offset: Offset(0, 1), blurRadius: 2),
  BoxShadow(color: Color(0x0F101828), offset: Offset(0, 8), blurRadius: 24),
];

/// 深色下阴影必须更黑更重才看得见：浅色那套 4%~6% 的灰压在深底上
/// 完全消失，卡片会和页底糊成一片。
const _shadowCardDark = [
  BoxShadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 2),
  BoxShadow(color: Color(0x59000000), offset: Offset(0, 8), blurRadius: 24),
];

/// Hero 卡的手挑色停（默认蓝）。见 [AppColors.heroGradient]。
const _heroGradientLight = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF6BA3F7), Color(0xFF4A7FE8), Color(0xFF3B63D6)],
  stops: [0.0, 0.55, 1.0],
);

/// 深色下略压暗：深色页面里高亮卡会刺眼。
const _heroGradientDark = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF4C82DC), Color(0xFF3A65C4), Color(0xFF2C4CA6)],
  stops: [0.0, 0.55, 1.0],
);

const _shadowHeroPrimaryLight = [
  BoxShadow(color: Color(0x335190F2), offset: Offset(0, 8), blurRadius: 24),
  BoxShadow(color: Color(0x1A5190F2), offset: Offset(0, 2), blurRadius: 6),
];

/// 深色下彩色光晕要收一半：深底上的高饱和光晕会糊成一团发光的雾。
const _shadowHeroPrimaryDark = [
  BoxShadow(color: Color(0x2E4A7FE8), offset: Offset(0, 8), blurRadius: 24),
  BoxShadow(color: Color(0x4D000000), offset: Offset(0, 2), blurRadius: 6),
];

/// 取色板 / 圆角阶梯的终端写法：`context.colors.ink`、`context.radii.card`。
///
/// 比 `AppColors.of(context).ink` 短，调用点密度高的 build 方法里差别明显。
extension AppThemeContext on BuildContext {
  AppColors get colors => AppColors.of(this);

  AppRadius get radii => AppRadius.of(this);
}

TextStyle _flat(TextStyle? style, AppColors colors) =>
    (style ?? const TextStyle()).copyWith(letterSpacing: 0, color: colors.ink);

/// 等宽数字（`tnum`）字体特性。
///
/// ## 为什么挂在 textTheme 上而不是逐个金额 Text 加
///
/// `Text` 的 style 会与最近的 `DefaultTextStyle` 做 `merge`，而 `merge` 对
/// `fontFeatures` 的处理是「自己没给就沿用祖先的」。Material widget 会用
/// `theme.textTheme.bodyMedium` 铺一层 DefaultTextStyle，所以把特性挂到
/// textTheme 上就能一路继承到几十处金额文本——它们写的是
/// `TextStyle(fontSize: 14, fontWeight: ...)`，从不碰 fontFeatures。
///
/// 逐处加的方案在这个项目里等于要改二十多个文件，而且下一个新增的金额
/// 一定会忘。代价是所有文本（含中文里夹的数字）都变等宽数字，这在记账
/// 场景里恰好是想要的：日期、笔数、占比全部逐行对齐。
List<FontFeature>? _figureFeatures(bool tabular) =>
    tabular ? const [FontFeature.tabularFigures()] : null;

TextTheme _withFigures(TextTheme text, bool tabular) {
  final features = _figureFeatures(tabular);
  if (features == null) return text;
  TextStyle? apply(TextStyle? style) => style?.copyWith(fontFeatures: features);
  return text.copyWith(
    displayLarge: apply(text.displayLarge),
    displayMedium: apply(text.displayMedium),
    displaySmall: apply(text.displaySmall),
    headlineLarge: apply(text.headlineLarge),
    headlineMedium: apply(text.headlineMedium),
    headlineSmall: apply(text.headlineSmall),
    titleLarge: apply(text.titleLarge),
    titleMedium: apply(text.titleMedium),
    titleSmall: apply(text.titleSmall),
    bodyLarge: apply(text.bodyLarge),
    bodyMedium: apply(text.bodyMedium),
    bodySmall: apply(text.bodySmall),
    labelLarge: apply(text.labelLarge),
    labelMedium: apply(text.labelMedium),
    labelSmall: apply(text.labelSmall),
  );
}

/// Material 兜底主题（`showDialog`、`InputDecoration` 这类没迁到 forui 的组件）。
///
/// [brightness] 决定取哪套色板，并把色板挂进 [ThemeData.extensions]——
/// `context.colors` 就是从这里读的，漏挂会静默退回浅色。
ThemeData buildAppTheme({
  Brightness brightness = Brightness.light,
  AppRadius radius = const AppRadius(),
  AppDensity density = const AppDensity(),
  AppMotion motion = const AppMotion(),
}) {
  final colors = brightness == Brightness.dark
      ? AppColors.dark
      : AppColors.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
      primary: colors.primary,
      secondary: colors.income,
      tertiary: colors.expense,
      surface: colors.surface,
    ),
    scaffoldBackgroundColor: colors.canvas,
  );
  final text = base.textTheme;
  return base.copyWith(
    extensions: [colors, radius, density, motion],
    textTheme: text.copyWith(
      displayLarge: _flat(text.displayLarge, colors),
      displayMedium: _flat(text.displayMedium, colors),
      displaySmall: _flat(text.displaySmall, colors),
      headlineLarge: _flat(text.headlineLarge, colors),
      headlineMedium: _flat(text.headlineMedium, colors),
      headlineSmall: _flat(text.headlineSmall, colors),
      titleLarge: _flat(text.titleLarge, colors),
      titleMedium: _flat(text.titleMedium, colors),
      titleSmall: _flat(text.titleSmall, colors),
      bodyLarge: _flat(text.bodyLarge, colors),
      bodyMedium: _flat(text.bodyMedium, colors),
      bodySmall: _flat(text.bodySmall, colors),
      labelLarge: _flat(text.labelLarge, colors),
      labelMedium: _flat(text.labelMedium, colors),
      labelSmall: _flat(text.labelSmall, colors),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: colors.canvas,
      foregroundColor: colors.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      toolbarHeight: 56,
      titleSpacing: 4,
      systemOverlayStyle: colors.systemOverlayStyle,
      iconTheme: IconThemeData(color: colors.ink, size: 22),
      titleTextStyle: _flat(
        text.titleLarge,
        colors,
      ).copyWith(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.2),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius.cardAll,
        side: BorderSide(color: colors.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: colors.surface,
      indicatorColor: colors.primarySoft,
      labelTextStyle: WidgetStatePropertyAll(
        _flat(text.labelMedium, colors).copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: DividerThemeData(color: colors.line, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: radius.blockAll,
        borderSide: BorderSide(color: colors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius.blockAll,
        borderSide: BorderSide(color: colors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius.blockAll,
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: radius.blockAll),
        textStyle: _flat(
          text.labelLarge,
          colors,
        ).copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: radius.blockAll),
        ),
        textStyle: WidgetStatePropertyAll(
          _flat(text.labelLarge, colors).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

/// forui 品牌主题：以 neutral(light/dark touch) 为底，套上 LigyTally 的语义化配色。
///
/// - primary       → 强调色，用于选中态、强调按钮
/// - destructive   → 危险红（删除、错误）。**不是** [AppColors.expense]：
///   用户可以把支出翻成绿色，而删除按钮必须一直是红的。
/// - background    → 页面底色
/// - card / border → 卡片面色 + 淡描边
///
/// 所有「压在彩色底上的前景色」取 [AppColors.canvasBase] 而不是 `canvas`：
/// 壁纸模式下后者是透明的，那会让深色皮肤的 FAB 上的加号直接消失。
///
/// 通过 [FThemeData] 重建（而不是 `copyWith`）只改颜色与圆角，其余间距/字体
/// 沿用 forui 触屏预设，保证组件观感一致。
///
/// 圆角必须走构造函数而不是 `copyWith(style: ...)`：forui 的各组件样式是在
/// [FThemeData] 构造时由 `style` 派生出来的，`copyWith` 只换 style 字段，
/// 已经算好的 cardStyle / buttonStyles 不会跟着重算，圆角设置会半数失效。
FThemeData buildForuiTheme({
  Brightness brightness = Brightness.light,
  AppColors? colors,
  AppRadius radius = const AppRadius(),
}) {
  final dark = brightness == Brightness.dark;
  final resolved = colors ?? (dark ? AppColors.dark : AppColors.light);
  final base = dark ? FTheme.neutral.dark.touch : FTheme.neutral.light.touch;
  final theme = FThemeData(
    touch: true,
    debugLabel: 'LigyTally forui ${dark ? 'dark' : 'light'}',
    style: base.style.copyWith(borderRadius: radius.forui),
    colors: base.colors.copyWith(
      background: resolved.canvas,
      foreground: resolved.ink,
      primary: resolved.primary,
      // 深色下强调色被提亮了，压白字对比度不够，改用深墨色前景。
      primaryForeground: dark ? resolved.canvasBase : Colors.white,
      secondary: resolved.primarySoft,
      secondaryForeground: resolved.primary,
      muted: resolved.fill,
      mutedForeground: resolved.muted,
      destructive: resolved.danger,
      destructiveForeground: dark ? resolved.canvasBase : Colors.white,
      card: resolved.surface,
      border: resolved.line,
      barrier: resolved.barrier,
    ),
  );
  return theme.copyWith(toasterStyle: _toasterStyle(resolved, radius));
}

/// forui 主题缓存的钥匙：只放**离散且真的会改到 forui 组件**的那些档位。
///
/// 密度、动效、Hero 卡样式、千分位都不进来：它们一个都不影响 forui 组件的
/// 颜色或圆角（密度走 `MediaQuery.textScaler`，动效和 Hero 卡走各自的
/// ThemeExtension）。放进来只会把缓存打成碎片，让每次改这些档位都白重建
/// 一份 forui 主题。
typedef _ForuiKey = (
  Brightness,
  AppAccent,
  AppCornerStyle,
  bool trueBlack,
  bool hasWallpaper,
  SignPalette,
);

_ForuiKey _foruiKey(
  Brightness brightness,
  AppAccent accent,
  AppearanceConfig config,
) => (
  brightness,
  accent,
  config.corner,
  config.trueBlack,
  config.hasWallpaper,
  config.signPalette,
);

final _foruiPresetCache = <_ForuiKey, FThemeData>{};

/// 自选色只留最新的一份（每套亮度各一格）。
///
/// 不能和预设共用一个 map：色相条是连着拖的，每个落点都是一把新钥匙，拖一遍
/// 就往 map 里灌进几百份主题，等于内存泄漏。同一时刻只有一种自选色在生效，
/// 一格备忘录就够。
///
/// 其余档位（圆角、纯黑、壁纸、收支向）可以安全地进缓存键：它们都是枚举
/// 或布尔，取值有限，不像色相那样连续。
final _foruiCustomCache =
    <Brightness, (AccentChoice, _ForuiKey, FThemeData)>{};

/// 缓存好的 forui 主题。
///
/// [buildForuiTheme] 里的 toast 样式 delta 构造不算便宜，而主题过渡的
/// 200ms 里外层会重建十几次，每次重建一份纯粹是浪费。
FThemeData foruiThemeFor(
  Brightness brightness, [
  AppearanceConfig config = AppearanceConfig.initial,
]) {
  FThemeData build() => buildForuiTheme(
    brightness: brightness,
    colors: AppColors.resolve(brightness, config),
    radius: AppRadius(scale: config.corner.scale),
  );
  final preset = config.accent.preset;
  if (preset != null) {
    return _foruiPresetCache.putIfAbsent(
      _foruiKey(brightness, preset, config),
      build,
    );
  }
  // 自选色没有预设枚举可以进钥匙，拿 blue 占位：这一格是按 accent 全等
  // 另外比对的，占位值只参与「其余档位有没有变」这半边。
  final key = _foruiKey(brightness, AppAccent.blue, config);
  final cached = _foruiCustomCache[brightness];
  if (cached != null && cached.$1 == config.accent && cached.$2 == key) {
    return cached.$3;
  }
  final theme = build();
  _foruiCustomCache[brightness] = (config.accent, key, theme);
  return theme;
}

/// 生产环境用的 Material 兜底主题：forui 主题的近似映射 + 挂上各套令牌扩展。
///
/// 保持「以 forui 主题为唯一真源」的原有结构（[buildAppTheme] 是另一套
/// 独立的 Material3 主题，只有测试在用），这里补三件事：亮度跟随、
/// 把四套令牌挂进 extensions、以及那两项**只能**在 Material 主题这一层
/// 落地的外观设置（等宽数字走 textTheme、页面转场走 pageTransitionsTheme）。
ThemeData buildMaterialTheme(
  Brightness brightness, [
  AppearanceConfig config = AppearanceConfig.initial,
]) {
  final colors = AppColors.resolve(brightness, config);
  final base = foruiThemeFor(brightness, config).toApproximateMaterialTheme();
  final transitions = config.motion.pageTransitions;
  return base.copyWith(
    extensions: [
      colors,
      AppRadius(scale: config.corner.scale),
      config.density.tokens,
      config.motion.tokens,
    ],
    textTheme: _withFigures(base.textTheme, config.tabularFigures),
    pageTransitionsTheme: transitions,
  );
}

/// toast 的浮起阴影：两层叠加（近距离描边阴影 + 远距离柔光），
/// 比单层阴影更接近真实浮层，也不会糊成一团灰。
const _toastShadowLight = [
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 2), blurRadius: 6),
  BoxShadow(color: Color(0x1F000000), offset: Offset(0, 10), blurRadius: 28),
];

const _toastShadowDark = [
  BoxShadow(color: Color(0x4D000000), offset: Offset(0, 2), blurRadius: 6),
  BoxShadow(color: Color(0x66000000), offset: Offset(0, 10), blurRadius: 28),
];

/// toast 全局样式：卡片式浮层+ 语义色。
///
/// 只调样式不动交互——位置（触屏顶部居中）、滑动消失、堆叠展开
/// 全部沿用 forui 预设。
///
/// - 圆角走卡片档的超椭圆，和日记账卡、统计卡是同一档
/// - 卡片面色 + 极淡描边 + 双层阴影，从页面底色上「浮」起来
/// - 标题 15/w600、描述 13，比默认更紧凑，一行提示不显得空旷
/// - destructive 变体改成淡红底 + 红描边，比纯卡片底红字更有警示感
///
/// 这里必须是**函数**而不是 top-level final：后者只在首次访问时求值一次，
/// 之后切主题拿到的仍是旧色板的 toast。
FToasterStyleDelta _toasterStyle(AppColors colors, AppRadius radius) {
  final shadow = colors.isDark ? _toastShadowDark : _toastShadowLight;
  final borderRadius = radius.cardAll;
  return FToasterStyleDelta.delta(
    padding: const EdgeInsetsGeometryDelta.value(
      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    expandSpacing: 8,
    collapsedProtrusion: 10,
    collapsedScale: 0.94,
    toastStyles:
        FVariantsDelta<
          FToastVariantConstraint,
          FToastVariant,
          FToastStyle,
          FToastStyleDelta
        >.delta([
          // 先把公共外观打到 base 和所有变体上
          FVariantOperation.all(
            FToastStyleDelta.delta(
              decoration: DecorationDelta.shapeDelta(
                color: colors.surface,
                shape: RoundedSuperellipseBorder(
                  side: BorderSide(color: colors.line),
                  borderRadius: borderRadius,
                ),
                shadows: shadow,
              ),
              padding: const EdgeInsetsGeometryDelta.value(
                EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              ),
              iconStyle: IconThemeDataDelta.delta(
                size: 18,
                color: colors.primary,
              ),
              iconSpacing: 12,
              titleTextStyle: TextStyleDelta.delta(
                fontSize: 15,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
              titleSpacing: 3,
              descriptionTextStyle: TextStyleDelta.delta(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w400,
                color: colors.muted,
              ),
              suffixSpacing: 8,
            ),
          ),
          // 再单独覆盖 destructive：淡红底、红描边、红字
          FVariantOperation.exact(
            <FToastVariantConstraint>{FToastVariant.destructive},
            FToastStyleDelta.delta(
              decoration: DecorationDelta.shapeDelta(
                color: colors.dangerSoft,
                shape: RoundedSuperellipseBorder(
                  side: BorderSide(color: colors.danger.withValues(alpha: 0.28)),
                  borderRadius: borderRadius,
                ),
                shadows: shadow,
              ),
              iconStyle: IconThemeDataDelta.delta(color: colors.danger),
              titleTextStyle: TextStyleDelta.delta(color: colors.danger),
              descriptionTextStyle: TextStyleDelta.delta(
                color: colors.danger.withValues(alpha: 0.8),
              ),
            ),
          ),
        ]),
  );
}
