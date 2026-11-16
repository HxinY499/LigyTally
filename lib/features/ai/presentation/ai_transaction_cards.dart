import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/location/place_fix.dart';
import '../../../core/theme/app_density.dart';
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
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    return Material(
      color: colors.surface,
      shape: context.radii.cardShape(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 18,
                endIndent: 18,
                color: colors.fill,
              ),
            _CardRow(
              item: items[index],
              onTap: () => unawaited(_openTransaction(items[index])),
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
    final extra = item.transaction.locationAndNote;
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      item.transaction.occurredAt,
    );
    return InkWell(
      onTap: onTap,
      highlightColor: colors.pressed,
      splashColor: colors.ripple,
      hoverColor: colors.ripple,
      child: Padding(
        // 和首页账单行同一套尺寸：左右 18 是版面骨架不随密度缩，
        // 上下跟着密度档走。
        padding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: context.density.space(12),
        ),
        child: Row(
          children: [
            CategoryIconBadge(
              iconKey: item.category.iconKey,
              color: color,
              background: soft,
              diameter: CategoryIconBadge.large,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
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
                    extra.isEmpty
                        ? formatClock(occurredAt)
                        : '${formatClock(occurredAt)} · $extra',
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
}
