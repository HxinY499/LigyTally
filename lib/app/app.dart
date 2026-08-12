import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../core/preferences/theme_mode.dart';
import '../core/theme/app_theme.dart';
import '../core/update/update_banner.dart';
import 'home_shell.dart';

class LigyTallyApp extends ConsumerWidget {
  const LigyTallyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Ligy Tally',
      debugShowCheckedModeBanner: false,
      // Material 兜底组件（showDialog / 未迁移页面）沿用 forui 近似主题，
      // 保证 forui 与 Material 混用时观感一致。
      theme: buildMaterialTheme(Brightness.light),
      darkTheme: buildMaterialTheme(Brightness.dark),
      themeMode: ref.watch(appThemeModeProvider).materialMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        // forui 组件的本地化（日历、选择器等）
        FLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => _ThemedShell(child: child!),
      home: const UpdateNotificationLayer(child: HomeShell()),
    );
  }
}

/// 把 Material 主题解析出的亮度接到 forui 与系统状态栏上。
///
/// 必须是 MaterialApp 的**子级**而不是在上面直接算亮度：`themeMode.system`
/// 下真正生效的亮度由 MaterialApp 自己按平台亮度决定，只有在它下面
/// `Theme.of(context)` 才拿得到结果，否则 `ThemeMode.system` 会失效。
class _ThemedShell extends StatelessWidget {
  const _ThemedShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 项目没用 AppBar，状态栏图标明暗没人管，深色下会出现黑图标压深底。
      value: colors.systemOverlayStyle,
      // 用 FTheme 包裹整棵树，forui 组件才能读到品牌主题；
      // FToaster 为 forui 的 toast/sonner 提供挂载点。
      child: FTheme(
        data: foruiThemeFor(colors.brightness),
        child: FToaster(child: child),
      ),
    );
  }
}
