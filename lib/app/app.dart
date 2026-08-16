import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../core/appearance/appearance.dart';
import '../core/media/image_storage.dart';
import '../core/theme/app_theme.dart';
import '../core/update/update_banner.dart';
import 'home_shell.dart';

class LigyTallyApp extends ConsumerWidget {
  const LigyTallyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 整套外观一次性 watch：这些档位是一起进主题的，分别 watch 十几个
    // 派生 provider 只会让同一次改动触发十几次重建。
    // 页面级别的细粒度订阅仍然走各自的派生 provider。
    final config = ref.watch(appearanceProvider);
    return MaterialApp(
      title: 'Ligy Tally',
      debugShowCheckedModeBanner: false,
      // Material 兜底组件（showDialog / 未迁移页面）沿用 forui 近似主题，
      // 保证 forui 与 Material 混用时观感一致。
      theme: buildMaterialTheme(Brightness.light, config),
      darkTheme: buildMaterialTheme(Brightness.dark, config),
      themeMode: config.themeMode.materialMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        // forui 组件的本地化（日历、选择器等）
        FLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => _ThemedShell(config: config, child: child!),
      home: const UpdateNotificationLayer(child: HomeShell()),
    );
  }
}

/// 把 Material 主题解析出的亮度接到 forui、系统状态栏、字号与壁纸上。
///
/// 必须是 MaterialApp 的**子级**而不是在上面直接算亮度：`themeMode.system`
/// 下真正生效的亮度由 MaterialApp 自己按平台亮度决定，只有在它下面
/// `Theme.of(context)` 才拿得到结果，否则 `ThemeMode.system` 会失效。
///
/// 这一层也是「只能在 widget 树上落地」的两项外观设置的唯一入口：
/// 显示密度的字号倍率（`MediaQuery.textScaler`）和全局壁纸。它们都没法
/// 表达成 ThemeData 上的字段。
class _ThemedShell extends StatelessWidget {
  const _ThemedShell({required this.config, required this.child});

  final AppearanceConfig config;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 项目没用 AppBar，状态栏图标明暗没人管，深色下会出现黑图标压深底。
      value: colors.systemOverlayStyle,
      child: MediaQuery(
        // 显示密度的字号倍率在这里生效，一次覆盖全应用——包括 forui 组件
        // 内部写死的字号。改成在各处 `fontSize * scale` 的话，漏掉的地方
        // 会和跟上的地方错开一档，比不做更难看。
        data: media.copyWith(
          textScaler: _DensityTextScaler(
            media.textScaler,
            config.density.textScale,
          ),
        ),
        // 用 FTheme 包裹整棵树，forui 组件才能读到品牌主题；
        // FToaster 为 forui 的 toast/sonner 提供挂载点。
        child: FTheme(
          data: foruiThemeFor(colors.brightness, config),
          child: FToaster(child: _withWallpaper(colors, child)),
        ),
      ),
    );
  }

  /// 把壁纸垫在整棵路由树之下。
  ///
  /// 垫在这里而不是各页面自己画：壁纸要在页面之间连续（切 Tab、推二级页
  /// 时不该闪一下），而只要它比 Navigator 高一层，路由怎么换它都不重建。
  /// 页面本身让开的方式是 [AppColors.canvas] 在壁纸模式下变透明。
  Widget _withWallpaper(AppColors colors, Widget child) {
    if (!config.hasWallpaper) return child;
    final path = ImageStorage.resolveSyncPath(kWallpaperRelativePath);
    if (path == null) return child;
    return Stack(
      // 必须 expand：Navigator 在松约束下量不出自己该多大。
      fit: StackFit.expand,
      children: [
        _WallpaperLayer(
          path: path,
          wallpaper: config.wallpaper,
          scrim: colors.canvasBase,
        ),
        child,
      ],
    );
  }
}

/// 壁纸层：照片 + 高斯模糊 + 一层页面色蒙版。
///
/// ## 蒙版为什么在这里，而不是让页面半透明
///
/// 「照片透出多少」这件事只有一个自由度，落在哪一层都能实现。放在壁纸层的
/// 好处是页面那一侧只需要知道「有没有壁纸」这个布尔值——[AppColors] 因此
/// 不必带上一个连续的透明度，forui 主题缓存的钥匙也就不会被拖动浓度滑杆
/// 打成碎片。
///
/// 这层蒙版**不承担可读性**：浓度拖到头它就完全消失。文字的底由各自那一层
/// 自己给——卡片是实底（`AppColors.surface`），页头和吸顶条自带一层局部实色
///（`AppChromeGlass`）。
class _WallpaperLayer extends StatelessWidget {
  const _WallpaperLayer({
    required this.path,
    required this.wallpaper,
    required this.scrim,
  });

  final String path;
  final WallpaperConfig wallpaper;
  final Color scrim;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            enabled: wallpaper.blur > 0,
            imageFilter: ui.ImageFilter.blur(
              sigmaX: wallpaper.blur,
              sigmaY: wallpaper.blur,
            ),
            child: Image(
              // stamp 进 key：换壁纸是同名覆盖，不换 key 的话即使
              // evict 过缓存，这颗 Image 也可能停在旧的那一帧上。
              key: ValueKey(wallpaper.stamp),
              image: FileImage(File(path)),
              fit: BoxFit.cover,
              // 图没了不该整屏报错：文件可能被用户在系统文件管理器里删了，
              // 或者恢复了一个不含壁纸的旧备份。露出蒙版就行。
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
          ),
          ColoredBox(color: scrim.withValues(alpha: 1 - wallpaper.opacity)),
        ],
      ),
    );
  }
}

/// 在系统字号之上再乘一个应用自己的密度倍率。
///
/// 不能直接 `TextScaler.linear(density)` 把 MediaQuery 里的值换掉——那会把
/// 用户在系统设置里调大的字号一起吃掉，等于把无障碍设置关了。这里先按密度
/// 放大字号，再交给系统的缩放曲线（Android 14 起是非线性的），顺序也是对的：
/// 「应用的基准字号变大了，然后系统再缩放它」。
class _DensityTextScaler extends TextScaler {
  const _DensityTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize * factor);

  // `TextScaler` 仍把这个 getter 声明成抽象成员（虽然它自己标了 deprecated），
  // 不实现编译不过。转发给底层再乘上倍率，语义与 [scale] 一致。
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _DensityTextScaler &&
          other.base == base &&
          other.factor == factor);

  @override
  int get hashCode => Object.hash(base, factor);
}
