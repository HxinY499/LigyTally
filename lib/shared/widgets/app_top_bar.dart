import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/theme/app_theme.dart';
import 'app_page_header.dart';

/// 应用统一页头（二级页面用）。
///
/// 与主页 `AppPageHeader` 同高（56）、同一标题样式（[kAppHeaderTitleStyle]）；
/// 返回按钮为墨色细箭头。所有带返回的二级页面都用它，想统一调整页头只改这一处。
///
/// 用法：`appBar: AppTopBar(title: '记一笔', actions: [...])`
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return AppBar(
      automaticallyImplyLeading: false,
      leadingWidth: 48,
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
      title: Text(title, style: kAppHeaderTitleStyle),
      actions: actions,
    );
  }
}
