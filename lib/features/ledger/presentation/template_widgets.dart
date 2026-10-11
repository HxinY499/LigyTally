import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_density.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';

/// 一个模板的行：分类图标 + 名称 + 金额。记账面板和模板管理页共用，
/// 两处长得一样，用户在管理页看到的就是记账时点的那一行。
///
/// 长相对齐明细页的账单行（同尺寸底座、同字号、同金额样式）：模板点下去
/// 就变成一笔账单，两者看起来该是同一种东西。
class TemplateTile extends StatelessWidget {
  const TemplateTile({
    super.key,
    required this.item,
    required this.grouped,
    required this.onTap,
    this.trailing,
    this.iconBadge,
  });

  final TemplateItem item;
  final bool grouped;
  final VoidCallback? onTap;

  /// 金额右侧的附加内容：管理页放 chevron。
  final Widget? trailing;

  /// 压在分类图标右上角的角标：记账面板用它标「已记」。
  ///
  /// 放在图标上而不是金额右边：角标一出现就把金额往左推，用户正盯着的
  /// 那串数字跟着跳，看着像金额变了。
  final Widget? iconBadge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final template = item.template;
    final isExpense = template.kind == 0;
    final active = item.category.isActive;
    final color = !active
        ? colors.inactive
        : (isExpense ? colors.expense : colors.income);
    final soft = !active
        ? colors.fill
        : (isExpense ? colors.expenseSoft : colors.incomeSoft);
    final String? subtitle = !active
        ? '分类「${item.category.name}」已停用，点开重选'
        : (template.note.isEmpty ? null : item.category.name);
    return InkWell(
      onTap: onTap,
      highlightColor: colors.pressed,
      splashColor: colors.ripple,
      hoverColor: colors.ripple,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: context.density.space(12),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CategoryIconBadge(
                  iconKey: item.category.iconKey,
                  color: color,
                  background: soft,
                  diameter: CategoryIconBadge.large,
                ),
                if (iconBadge != null)
                  Positioned(top: -4, right: -4, child: iconBadge!),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: active ? colors.ink : colors.muted,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${isExpense ? '-' : '+'}'
              '${formatMoney(template.amountCents, grouped: grouped)}',
              style: AppText.money(16, color: color, weight: FontWeight.w800),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// 没有模板时的引导：说清模板是干什么的，并给出新建入口。
class TemplateEmptyState extends StatelessWidget {
  const TemplateEmptyState({
    super.key,
    required this.title,
    required this.detail,
    required this.onCreate,
  });

  final String title;
  final String detail;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FLucideIcons.layoutTemplate, size: 40, color: colors.muted),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 18),
          AppButton(
            onPress: onCreate,
            prefix: const Icon(FLucideIcons.plus),
            child: const Text('新建模板'),
          ),
        ],
      ),
    );
  }
}

/// 白底圆角卡，组内发丝分割线。模板列表用它装 [TemplateTile]。
///
/// 水波要画在卡自己的 [Material] 上，否则被白底盖住，点击没有反馈
/// （同明细页日卡的处理）。
class TemplateCard extends StatelessWidget {
  const TemplateCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              indent: 18,
              endIndent: 18,
              color: colors.fill,
            ),
          children[i],
        ],
      ],
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: radii.cardShape(),
        shadows: colors.shadowCard,
      ),
      child: Material(
        color: colors.surface,
        shape: radii.cardShape(),
        clipBehavior: Clip.antiAlias,
        child: column,
      ),
    );
  }
}
