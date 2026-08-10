import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/theme/app_theme.dart';

/// 应用统一页头（二级页面用）。
///
/// 统一了返回按钮（chevronLeft 细箭头 + 主色）、标题样式（走全局 appBarTheme）、
/// 高度与留白。所有带返回的二级页面都用它，想统一调整页头只改这一处。
///
/// 用法：`appBar: AppTopBar(title: '记一笔', actions: [...])`
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return AppBar(
      automaticallyImplyLeading: false,
      leadingWidth: 52,
      leading: canPop
          ? IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: '返回',
              splashRadius: 22,
              icon: const Icon(
                FLucideIcons.chevronLeft,
                color: AppColors.ink,
                size: 24,
              ),
            )
          : null,
      title: Text(title),
      actions: actions,
    );
  }
}
