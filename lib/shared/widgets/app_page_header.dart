import 'package:flutter/material.dart';

/// 应用统一主页页头（一级 Tab 页用）。
///
/// 固定高度 56，左 20 / 右 12 留白，标题统一 headlineSmall + w800，
/// 支持右侧 actions；[content] 非空时替换标题区域（如记账页的搜索输入框）。
/// 二级页请用 `AppTopBar`。
///
/// 用法：`AppPageHeader(title: '设置')`
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({super.key, this.title, this.content, this.actions})
    : assert(title != null || content != null, 'title 与 content 至少提供一个');

  final String? title;

  /// 非空时替换标题区域。
  final Widget? content;

  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 20, right: 12),
      child: Row(
        children: [
          Expanded(
            child:
                content ??
                Text(
                  title!,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
          ),
          if (actions != null) ...[const SizedBox(width: 8), ...actions!],
        ],
      ),
    );
  }
}
