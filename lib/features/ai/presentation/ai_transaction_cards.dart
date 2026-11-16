import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/providers.dart';
import '../../ledger/presentation/transaction_editor.dart';

/// AI 回答末尾 `<bills>` 标记点名的账单卡片，点击进详情页。
///
/// 样式对齐首页账单行，只留「图标 + 分类/备注 + 金额」，
/// 没有多选、背景图和长按。账单按 id 实时查库，看到的永远是
/// 最新数据；查不到的（刚被删、id 写错）整条跳过。
class AiTransactionCards extends ConsumerStatefulWidget {
  const AiTransactionCards({super.key, required this.ids});

  final List<String> ids;

  @override
  ConsumerState<AiTransactionCards> createState() => _AiTransactionCardsState();
}

class _AiTransactionCardsState extends ConsumerState<AiTransactionCards> {
  static const _collapsedCount = 5;

  bool _expanded = false;
  List<LedgerItem>? _items;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(AiTransactionCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sameIds(oldWidget.ids, widget.ids)) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    final items = await ref
        .read(databaseProvider)
        .transactionsByIds(widget.ids);
    if (!mounted) return;
    setState(() {
      // 保持模型给的顺序：最相关的在最前。
      final byId = {for (final item in items) item.transaction.id: item};
      _items = [
        for (final id in widget.ids)
          if (byId[id] != null) byId[id]!,
      ];
    });
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _openTransaction(LedgerItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TransactionEditor(existing: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final visible = _expanded
        ? items
        : items.take(_collapsedCount).toList();
    final hidden = items.length - visible.length;
    final collapsible = items.length > _collapsedCount;
    return Material(
      color: colors.surface,
      shape: context.radii.cardShape(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: colors.fill,
              ),
            _CardRow(
              item: visible[index],
              onTap: () => unawaited(_openTransaction(visible[index])),
            ),
          ],
          if (collapsible) ...[
            Divider(
              height: 1,
              thickness: 1,
              indent: 14,
              endIndent: 14,
              color: colors.fill,
            ),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              highlightColor: colors.pressed,
              splashColor: colors.ripple,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _expanded ? '收起' : '展开其余 $hidden 条',
                      style: TextStyle(fontSize: 13, color: colors.muted),
                    ),
                    Icon(
                      _expanded
                          ? FLucideIcons.chevronUp
                          : FLucideIcons.chevronDown,
                      size: 14,
                      color: colors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.item, required this.onTap});

  final LedgerItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isExpense = item.transaction.kind == 0;
    final color = isExpense ? colors.expense : colors.income;
    final soft = isExpense ? colors.expenseSoft : colors.incomeSoft;
    final note = item.transaction.note.trim();
    final subtitle = note.isEmpty
        ? _dayLabel(item.transaction.accountingDate)
        : '${_dayLabel(item.transaction.accountingDate)} · $note';
    return InkWell(
      onTap: onTap,
      highlightColor: colors.pressed,
      splashColor: colors.ripple,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CategoryIconBadge(
              iconKey: item.category.iconKey,
              color: color,
              background: soft,
              diameter: CategoryIconBadge.small,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${isExpense ? '-' : '+'}${formatMoney(item.transaction.amountCents)}',
              style: AppText.money(16, color: color, weight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  static String _dayLabel(String accountingDate) {
    final parsed = DateTime.tryParse(accountingDate);
    if (parsed == null) return accountingDate;
    final now = DateTime.now();
    if (parsed.year == now.year) return '${parsed.month} 月 ${parsed.day} 日';
    return '${parsed.year} 年 ${parsed.month} 月 ${parsed.day} 日';
  }
}
