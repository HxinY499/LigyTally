import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'app_accent.dart';

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
    required this.canvas,
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
    required this.accent,
    required this.pressed,
    required this.ripple,
    required this.barrier,
    required this.shadowCard,
    required this.shadowHeroPrimary,
    required this.shadowHeroWarm,
  });

  /// 从最近的 [Theme] 取色板。
  ///
  /// 兜底成 [light] 而不是抛异常：测试里大量 `MaterialApp` 只给了近似
  /// Material 主题，缺扩展时应该渲染成浅色而不是整屏红。
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  /// 按亮度和强调色取色板。
  ///
  /// 默认蓝直接返回 [light] / [dark] 常量实例——测试和缓存都按引用比较，
  /// 其它色才从对应皮肤 [withAccent] 派生。
  static AppColors resolve(Brightness brightness, AppAccent accent) {
    final base = brightness == Brightness.dark ? dark : light;
    if (accent == AppAccent.blue) return base;
    return base.withAccent(accent.primaryOf(brightness));
  }

  /// 浅色：奶白页底 + 纯白卡片，文字用带绿的深墨色。
  static const light = AppColors(
    brightness: Brightness.light,
    ink: Color(0xFF17211E),
    muted: Color(0xFF65716D),
    inactive: Color(0xFF9AA3A0),
    faint: Color(0xFFC2CBC6),
    canvas: Color(0xFFF5F5F5),
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
    accent: Color(0xFFE5A62E),
    pressed: Color(0x0F5190F2),
    ripple: Color(0x0A5190F2),
    barrier: Color(0x73000000),
    shadowCard: _shadowCardLight,
    shadowHeroPrimary: _shadowHeroPrimaryLight,
    shadowHeroWarm: _shadowHeroWarmLight,
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
    canvas: Color(0xFF101413),
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
    accent: Color(0xFFE9B44C),
    pressed: Color(0x1F6FA5F5),
    ripple: Color(0x146FA5F5),
    barrier: Color(0x99000000),
    shadowCard: _shadowCardDark,
    shadowHeroPrimary: _shadowHeroPrimaryDark,
    shadowHeroWarm: _shadowHeroWarmDark,
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

  /// 页面底色。
  final Color canvas;

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

  final Color expense;
  final Color expenseSoft;
  final Color income;
  final Color incomeSoft;
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

  /// 主色 Hero 卡阴影（统计页概览卡）：带品牌蓝色调，比中性灰更有发光感。
  ///
  /// 彩色卡片配中性灰阴影会显得「脏」——阴影里必须掺入卡片自身的色相。
  final List<BoxShadow> shadowHeroPrimary;

  /// 暖色 Hero 卡阴影（记账页月度摘要卡）：同 [shadowHeroPrimary] 的思路，
  /// 色相换成摘要卡的暖黄，避免中性灰压在暖黄渐变上发浊。
  final List<BoxShadow> shadowHeroWarm;

  bool get isDark => brightness == Brightness.dark;

  /// 只重染强调色家族（主色、浅底、按下/水波、Hero 蓝阴影）。
  /// 支出红 / 收入绿 / 暖黄摘要保持原样。
  AppColors withAccent(Color primary) {
    final soft = isDark
        ? Color.lerp(primary, canvas, 0.78)!
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

  /// 状态栏 / 导航栏图标的明暗。深底要浅图标，反之亦然。
  SystemUiOverlayStyle get systemOverlayStyle => isDark
      ? SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: canvas,
          systemNavigationBarIconBrightness: Brightness.light,
        )
      : SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: canvas,
          systemNavigationBarIconBrightness: Brightness.dark,
        );

  @override
  AppColors copyWith({
    Brightness? brightness,
    Color? ink,
    Color? muted,
    Color? inactive,
    Color? faint,
    Color? canvas,
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
    Color? accent,
    Color? pressed,
    Color? ripple,
    Color? barrier,
    List<BoxShadow>? shadowCard,
    List<BoxShadow>? shadowHeroPrimary,
    List<BoxShadow>? shadowHeroWarm,
  }) => AppColors(
    brightness: brightness ?? this.brightness,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    inactive: inactive ?? this.inactive,
    faint: faint ?? this.faint,
    canvas: canvas ?? this.canvas,
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
    accent: accent ?? this.accent,
    pressed: pressed ?? this.pressed,
    ripple: ripple ?? this.ripple,
    barrier: barrier ?? this.barrier,
    shadowCard: shadowCard ?? this.shadowCard,
    shadowHeroPrimary: shadowHeroPrimary ?? this.shadowHeroPrimary,
    shadowHeroWarm: shadowHeroWarm ?? this.shadowHeroWarm,
  );

  /// 主题切换时的过渡插值。
  ///
  /// [brightness] 不插值（没有「半深」这种东西），在中点直接翻转，
  /// 与 [ThemeData.lerp] 对 brightness 的处理保持一致，
  /// 否则 forui 组件和本色板会在过渡途中错开一帧明暗。
  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      inactive: Color.lerp(inactive, other.inactive, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
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
      shadowHeroWarm: BoxShadow.lerpList(
        shadowHeroWarm,
        other.shadowHeroWarm,
        t,
      )!,
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

const _shadowHeroPrimaryLight = [
  BoxShadow(color: Color(0x335190F2), offset: Offset(0, 8), blurRadius: 24),
  BoxShadow(color: Color(0x1A5190F2), offset: Offset(0, 2), blurRadius: 6),
];

/// 深色下彩色光晕要收一半：深底上的高饱和光晕会糊成一团发光的雾。
const _shadowHeroPrimaryDark = [
  BoxShadow(color: Color(0x2E4A7FE8), offset: Offset(0, 8), blurRadius: 24),
  BoxShadow(color: Color(0x4D000000), offset: Offset(0, 2), blurRadius: 6),
];

const _shadowHeroWarmLight = [
  BoxShadow(color: Color(0x2ED9A22B), offset: Offset(0, 8), blurRadius: 24),
  BoxShadow(color: Color(0x1AD9A22B), offset: Offset(0, 2), blurRadius: 6),
];

const _shadowHeroWarmDark = [
  BoxShadow(color: Color(0x29B07F1E), offset: Offset(0, 8), blurRadius: 24),
  BoxShadow(color: Color(0x4D000000), offset: Offset(0, 2), blurRadius: 6),
];

/// 取色板的终端写法：`context.colors.ink`。
///
/// 比 `AppColors.of(context).ink` 短，调用点密度高的 build 方法里差别明显。
extension AppThemeContext on BuildContext {
  AppColors get colors => AppColors.of(this);
}

TextStyle _flat(TextStyle? style, AppColors colors) =>
    (style ?? const TextStyle()).copyWith(letterSpacing: 0, color: colors.ink);

/// Material 兜底主题（`showDialog`、`InputDecoration` 这类没迁到 forui 的组件）。
///
/// [brightness] 决定取哪套色板，并把色板挂进 [ThemeData.extensions]——
/// `context.colors` 就是从这里读的，漏挂会静默退回浅色。
ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
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
    extensions: [colors],
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
        borderRadius: const BorderRadius.all(Radius.circular(8)),
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
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: colors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: colors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: _flat(
          text.labelLarge,
          colors,
        ).copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
/// - destructive   → 支出红（记账语境里的"扣钱/删除"）
/// - background    → 页面底色
/// - card / border → 卡片面色 + 淡描边
///
/// 通过 [FThemeData.copyWith] + [FColors.copyWith] 只改颜色，其余间距/圆角/字体
/// 沿用 forui 触屏预设，保证组件观感一致。
FThemeData buildForuiTheme({
  Brightness brightness = Brightness.light,
  AppColors? colors,
}) {
  final dark = brightness == Brightness.dark;
  final resolved = colors ?? (dark ? AppColors.dark : AppColors.light);
  final base = dark ? FTheme.neutral.dark.touch : FTheme.neutral.light.touch;
  final theme = FThemeData(
    touch: true,
    debugLabel: 'LigyTally forui ${dark ? 'dark' : 'light'}',
    colors: base.colors.copyWith(
      background: resolved.canvas,
      foreground: resolved.ink,
      primary: resolved.primary,
      // 深色下强调色被提亮了，压白字对比度不够，改用深墨色前景。
      primaryForeground: dark ? resolved.canvas : Colors.white,
      secondary: resolved.primarySoft,
      secondaryForeground: resolved.primary,
      muted: resolved.fill,
      mutedForeground: resolved.muted,
      destructive: resolved.expense,
      destructiveForeground: dark ? resolved.canvas : Colors.white,
      card: resolved.surface,
      border: resolved.line,
      barrier: resolved.barrier,
    ),
  );
  return theme.copyWith(toasterStyle: _toasterStyle(resolved));
}

final _foruiCache = <(Brightness, AppAccent), FThemeData>{};

/// 缓存好的 forui 主题。
///
/// [buildForuiTheme] 里的 toast 样式 delta 构造不算便宜，而主题过渡的
/// 200ms 里外层会重建十几次，每次重建一份纯粹是浪费。
/// 按（亮度 × 强调色）缓存：默认蓝仍是原来那两份，其它强调色各一份。
FThemeData foruiThemeFor(
  Brightness brightness, [
  AppAccent accent = AppAccent.blue,
]) => _foruiCache.putIfAbsent(
  (brightness, accent),
  () => buildForuiTheme(
    brightness: brightness,
    colors: AppColors.resolve(brightness, accent),
  ),
);

/// 生产环境用的 Material 兜底主题：forui 主题的近似映射 + 挂上色板扩展。
///
/// 保持「以 forui 主题为唯一真源」的原有结构（[buildAppTheme] 是另一套
/// 独立的 Material3 主题，只有测试在用），这里只补两件事：
/// 亮度跟随、以及把 [AppColors] 挂进 extensions。
ThemeData buildMaterialTheme(
  Brightness brightness, [
  AppAccent accent = AppAccent.blue,
]) {
  final colors = AppColors.resolve(brightness, accent);
  return foruiThemeFor(
    brightness,
    accent,
  ).toApproximateMaterialTheme().copyWith(extensions: [colors]);
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
/// -圆角用超椭圆 18px，比默认 md(10) 更圆润，符合浮层调性
/// - 卡片面色 + 极淡描边 + 双层阴影，从页面底色上「浮」起来
/// - 标题 15/w600、描述 13，比默认更紧凑，一行提示不显得空旷
/// - destructive 变体改成淡红底 + 红描边，比纯卡片底红字更有警示感
///
/// 这里必须是**函数**而不是 top-level final：后者只在首次访问时求值一次，
/// 之后切主题拿到的仍是旧色板的 toast。
FToasterStyleDelta _toasterStyle(AppColors colors) {
  final shadow = colors.isDark ? _toastShadowDark : _toastShadowLight;
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
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
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
                color: colors.expenseSoft,
                shape: RoundedSuperellipseBorder(
                  side: BorderSide(
                    color: colors.expense.withValues(alpha: 0.28),
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                ),
                shadows: shadow,
              ),
              iconStyle: IconThemeDataDelta.delta(color: colors.expense),
              titleTextStyle: TextStyleDelta.delta(color: colors.expense),
              descriptionTextStyle: TextStyleDelta.delta(
                color: colors.expense.withValues(alpha: 0.8),
              ),
            ),
          ),
        ]),
  );
}
