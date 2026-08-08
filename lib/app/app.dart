import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:forui/forui.dart';

import '../core/theme/app_theme.dart';
import '../core/update/update_banner.dart';
import 'home_shell.dart';

class LigyTallyApp extends StatelessWidget {
  const LigyTallyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final foruiTheme = buildForuiTheme();
    return MaterialApp(
      title: 'Ligy Tally',
      debugShowCheckedModeBanner: false,
      // Material 兜底组件（showDialog / 未迁移页面）沿用 forui 近似主题，
      // 保证 forui 与 Material 混用时观感一致。
      theme: foruiTheme.toApproximateMaterialTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        // forui 组件的本地化（日历、选择器等）
        FLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 用 FTheme 包裹整棵树，forui 组件才能读到品牌主题；
      // FToaster 为 forui 的 toast/sonner 提供挂载点。
      builder: (context, child) => FTheme(
        data: foruiTheme,
        child: FToaster(child: child!),
      ),
      home: const UpdateNotificationLayer(child: HomeShell()),
    );
  }
}
