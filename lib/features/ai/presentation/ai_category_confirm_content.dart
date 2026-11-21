import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/category_icon_view.dart';
import '../application/ai_approval.dart';

/// 分类新建、修改、删除确认弹窗里的可视化预览区。
///
/// 嵌入 [showAppConfirmDialog] 的 `content`：把分类图标、收支语义色、归属层级
/// 与字段变动直观铺出来，用户无需盲猜图标 key 长什么样。
class AiCategoryConfirmContent extends StatelessWidget {
  const AiCategoryConfirmContent({super.key, required this.request});

  final ToolApprovalRequest request;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = request.title;
    final changes = request.changes;
    final footnote = request.footnote;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null && title.isNotEmpty) ...[
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 14),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.canvasBase,
              borderRadius: context.radii.blockAll,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < request.categories.length; i++) ...[
                    if (i > 0)
                      Divider(height: 12, thickness: 1, color: colors.lineSoft),
                    _CategoryPreviewRow(item: request.categories[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (changes.isNotEmpty) ...[
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.canvasBase,
              borderRadius: context.radii.blockAll,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < changes.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _ChangeLine(change: changes[i]),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (footnote != null && footnote.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            footnote,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: request.destructive ? colors.danger : colors.muted,
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryPreviewRow extends StatelessWidget {
  const _CategoryPreviewRow({required this.item});

  final ToolApprovalCategoryItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = item.kind == 0 ? colors.expense : colors.income;
    final accentSoft = item.kind == 0 ? colors.expenseSoft : colors.incomeSoft;
    final active = item.isActive;
    final circleSize = item.indent ? 32.0 : 36.0;
    final glyphSize = item.indent ? 17.0 : 19.0;

    return Padding(
      padding: EdgeInsets.only(left: item.indent ? 20 : 0),
      child: Row(
        children: [
          Container(
            width: circleSize,
            height: circleSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? accentSoft : colors.fill,
              shape: BoxShape.circle,
            ),
            child: CategoryIconView(
              iconKey: item.iconKey,
              size: glyphSize,
              imageSize: circleSize,
              color: active ? accent : colors.inactive,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: active ? colors.ink : colors.inactive,
                        ),
                      ),
                    ),
                    if (!active) ...[
                      const SizedBox(width: 6),
                      Text(
                        '已停用',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.inactive,
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeLine extends StatelessWidget {
  const _ChangeLine({required this.change});

  final ToolApprovalChange change;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            change.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.inactive,
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  change.before,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: colors.muted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  FLucideIcons.arrowRight,
                  size: 13,
                  color: colors.inactive,
                ),
              ),
              Flexible(
                child: Text(
                  change.after,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
