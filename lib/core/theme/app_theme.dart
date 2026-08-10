import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class AppColors {
  static const ink = Color(0xFF17211E);
  static const muted = Color(0xFF65716D);
  static const canvas = Color(0xFFF5F5F5);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFDCDCDC);

  /// 更淡的分割线：用于大面积贴边描边（底部导航栏顶线等）。
  /// [line] 在长直线上会压出一道明显的灰边，显脏。
  static const lineSoft = Color(0xFFEDEDED);

  /// 未选中态图标/ 文字：比 [muted] 更低饱和。
  /// [muted]偏绿灰，用在小字上会发脏。
  static const inactive = Color(0xFF9AA3A0);
  static const primary = Color(0xFF5190F2);
  static const primarySoft = Color(0xFFE3EDFD);
  static const expense = Color(0xFFD55A46);
  static const expenseSoft = Color(0xFFF8E8E4);
  static const income = Color(0xFF2E7D32);
  static const incomeSoft = Color(0xFFE8F5E9);
  static const accent = Color(0xFFE5A62E);

  /// 列表项按下时的浅底反馈。
  ///
  /// 白面卡片上的点击反馈：太重会像「选中态」，太轻则等于没有。
  /// 这里取品牌蓝的极低透明度版本，按下时是一层几乎无色的冷灰，
  /// 既能确认「按到了」，又不会在快速滑动列表时闪出一片蓝。
  static const pressed = Color(0x0F5190F2);

  /// 水波扩散色：比 [pressed] 更淡。
  ///
  /// 水波是动态扩散的，视觉上比静态高亮更「抓眼」，
  /// 因此必须比按下底色更淡，否则点一下会像炸开一朵蓝花。
  static const ripple = Color(0x0A5190F2);
}

/// 全应用统一的卡片阴影。
///
/// 只有一处定义，记账页 / 统计页 / 以后新增的页面都引用这里——阴影一旦
/// 各页硬编码，很快就会出现「同一种卡片在两屏浮起高度不一样」。
///
/// 设计上一律用**两层叠加**而不是单层：
/// - 近距离一层（offset 1~2、blur 小）压出卡片边界，替代描边。
///   描边在浅灰底上会压出一道灰线显脏，用极淡阴影收边更干净。
/// - 远距离一层（offset 8、blur 大）做柔光，让卡片从背景「浮」起来。
///
/// 单层阴影要么太硬（边界锐利像描边），要么糊成一团灰（把底色压暗），
/// 两层分工才能既有边界又有空气感。
class AppShadows {
  const AppShadows._();

  /// 中性卡片阴影：白面卡片通用（记账日卡、统计各图表卡）。
  ///
  /// 色值用带蓝的深灰 `#101828` 而不是纯黑——纯黑阴影在浅灰底上会发脏，
  /// 略带冷色调更接近真实环境光。
  static const card = [
    BoxShadow(color: Color(0x0A101828), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0F101828), offset: Offset(0, 8), blurRadius: 24),
  ];

  /// 主色 Hero 卡阴影（统计页概览卡）：带品牌蓝色调，比中性灰更有发光感。
  ///
  /// 彩色卡片配中性灰阴影会显得「脏」——阴影里必须掺入卡片自身的色相。
  static const heroPrimary = [
    BoxShadow(color: Color(0x335190F2), offset: Offset(0, 8), blurRadius: 24),
    BoxShadow(color: Color(0x1A5190F2), offset: Offset(0, 2), blurRadius: 6),
  ];

  /// 暖色 Hero 卡阴影（记账页月度摘要卡）：同 [heroPrimary] 的思路，
  /// 色相换成摘要卡的暖黄 `#E5A62E`，避免中性灰压在暖黄渐变上发浊。
  static const heroWarm = [
    BoxShadow(color: Color(0x2ED9A22B), offset: Offset(0, 8), blurRadius: 24),
    BoxShadow(color: Color(0x1AD9A22B), offset: Offset(0, 2), blurRadius: 6),
  ];
}

TextStyle _flat(TextStyle? style) => (style ?? const TextStyle()).copyWith(
  letterSpacing: 0,
  color: AppColors.ink,
);

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.income,
      tertiary: AppColors.expense,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.canvas,
  );
  final text = base.textTheme;
  return base.copyWith(
    textTheme: text.copyWith(
      displayLarge: _flat(text.displayLarge),
      displayMedium: _flat(text.displayMedium),
      displaySmall: _flat(text.displaySmall),
      headlineLarge: _flat(text.headlineLarge),
      headlineMedium: _flat(text.headlineMedium),
      headlineSmall: _flat(text.headlineSmall),
      titleLarge: _flat(text.titleLarge),
      titleMedium: _flat(text.titleMedium),
      titleSmall: _flat(text.titleSmall),
      bodyLarge: _flat(text.bodyLarge),
      bodyMedium: _flat(text.bodyMedium),
      bodySmall: _flat(text.bodySmall),
      labelLarge: _flat(text.labelLarge),
      labelMedium: _flat(text.labelMedium),
      labelSmall: _flat(text.labelSmall),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      toolbarHeight: 56,
      titleSpacing: 4,
      iconTheme: const IconThemeData(color: AppColors.ink, size: 22),
      titleTextStyle: _flat(
        text.titleLarge,
      ).copyWith(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.2),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      labelTextStyle: WidgetStatePropertyAll(
        _flat(text.labelMedium).copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: _flat(
          text.labelLarge,
        ).copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        textStyle: WidgetStatePropertyAll(
          _flat(text.labelLarge).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

/// forui 品牌主题：以 neutral(light/touch) 为底，套上LigyTally 的语义化配色。
///
/// - primary       → 品牌蓝，用于选中态、强调按钮
/// - destructive   → 支出红（记账语境里的"扣钱/删除"）
/// - background→ 页面浅灰底
/// - card / border  → 卡片白面 + 淡描边
///
/// 通过 [FThemeData.copyWith] + [FColors.copyWith] 只改颜色，其余间距/圆角/字体
/// 沿用 forui 触屏预设，保证组件观感一致。
FThemeData buildForuiTheme() {
  final base = FTheme.neutral.light.touch;
  final theme = FThemeData(
    touch: true,
    debugLabel: 'LigyTally forui',
    colors: base.colors.copyWith(
      background: AppColors.canvas,
      foreground: AppColors.ink,
      primary: AppColors.primary,
      primaryForeground: Colors.white,
      secondary: AppColors.primarySoft,
      secondaryForeground: AppColors.primary,
      muted: AppColors.canvas,
      mutedForeground: AppColors.muted,
      destructive: AppColors.expense,
      destructiveForeground: Colors.white,
      card: AppColors.surface,
      border: AppColors.line,
    ),
  );
  return theme.copyWith(toasterStyle: _toasterStyle);
}

/// toast 的浮起阴影：两层叠加（近距离描边阴影 + 远距离柔光），
/// 比单层阴影更接近真实浮层，也不会糊成一团灰。
const _toastShadow = [
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 2), blurRadius: 6),
  BoxShadow(color: Color(0x1F000000), offset: Offset(0, 10), blurRadius: 28),
];

/// toast 全局样式：卡片式浮层+ 语义色。
///
/// 只调样式不动交互——位置（触屏顶部居中）、滑动消失、堆叠展开
/// 全部沿用 forui 预设。
///
/// -圆角用超椭圆 18px，比默认 md(10) 更圆润，符合浮层调性
/// - 白面+ 极淡描边 + 双层阴影，从页面浅灰底上「浮」起来
/// - 标题 15/w600、描述 13，比默认更紧凑，一行提示不显得空旷
/// - destructive 变体改成淡红底 + 红描边，比纯白底红字更有警示感
final _toasterStyle = FToasterStyleDelta.delta(
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
              color: AppColors.surface,
              shape: const RoundedSuperellipseBorder(
                side: BorderSide(color: AppColors.line),
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
              shadows: _toastShadow,
            ),
            padding: const EdgeInsetsGeometryDelta.value(
              EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            ),
            iconStyle: const IconThemeDataDelta.delta(
              size: 18,
              color: AppColors.primary,
            ),
            iconSpacing: 12,
            titleTextStyle: const TextStyleDelta.delta(
              fontSize: 15,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
            titleSpacing: 3,
            descriptionTextStyle: const TextStyleDelta.delta(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w400,
              color: AppColors.muted,
            ),
            suffixSpacing: 8,
          ),
        ),
        // 再单独覆盖 destructive：淡红底、红描边、红字
        FVariantOperation.exact(
          <FToastVariantConstraint>{FToastVariant.destructive},
          FToastStyleDelta.delta(
            decoration: DecorationDelta.shapeDelta(
              color: AppColors.expenseSoft,
              shape: RoundedSuperellipseBorder(
                side: BorderSide(
                  color: AppColors.expense.withValues(alpha: 0.28),
                ),
                borderRadius: const BorderRadius.all(Radius.circular(18)),
              ),
              shadows: _toastShadow,
            ),
            iconStyle: const IconThemeDataDelta.delta(color: AppColors.expense),
            titleTextStyle: const TextStyleDelta.delta(
              color: AppColors.expense,
            ),
            descriptionTextStyle: TextStyleDelta.delta(
              color: AppColors.expense.withValues(alpha: 0.8),
            ),
          ),
        ),
      ]),
);
