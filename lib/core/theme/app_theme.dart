import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class AppColors {
  static const ink = Color(0xFF17211E);
  static const muted = Color(0xFF65716D);
  static const canvas = Color(0xFFF5F7F5);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFDCE3DF);
  static const primary = Color(0xFF087A69);
  static const primarySoft = Color(0xFFDDF1EC);
  static const expense = Color(0xFFD55A46);
  static const expenseSoft = Color(0xFFF8E8E4);
  static const income = Color(0xFF2E7D32);
  static const incomeSoft = Color(0xFFE8F5E9);
  static const accent = Color(0xFFE5A62E);
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
      toolbarHeight: 60,
      titleSpacing: 4,
      iconTheme: const IconThemeData(color: AppColors.ink, size: 22),
      titleTextStyle: _flat(text.titleLarge).copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
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
/// - primary       → 品牌绿，用于选中态、强调按钮
/// - destructive   → 支出红（记账语境里的"扣钱/删除"）
/// - background→ 页面浅灰底
/// - card / border  → 卡片白面 + 淡描边
///
/// 通过 [FThemeData.copyWith] + [FColors.copyWith] 只改颜色，其余间距/圆角/字体
/// 沿用 forui 触屏预设，保证组件观感一致。
FThemeData buildForuiTheme() {
  final base = FTheme.neutral.light.touch;
  return FThemeData(
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
}

