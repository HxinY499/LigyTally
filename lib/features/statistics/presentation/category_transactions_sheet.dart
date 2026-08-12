import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/preferences/money_grouped.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/providers.dart';
import '../../ledger/presentation/transaction_editor.dart';
import 'stats_design.dart';
import 'stats_states.dart';

/// 从底部弹出某个一级分类在当前统计区间内的账单明细。
///
/// 排行行只给出「合计 + 占比」，看到一个异常高的分类时下一步必然是
/// 「到底哪几笔」。之前点排行只是高亮环形图，等于把用户挡在汇总层。
Future<void> showCategoryTransactionsSheet(
  BuildContext context, {
  required CategoryTotal category,
  required LedgerDateRange range,
  required String rangeLabel,
  required int kind,
  required Color color,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // 圆角与安全区由内容自己画，外层必须透明，否则圆角外会露出白直角。
    backgroundColor: Colors.transparent,
    // 明细可能很长，需要自己控制高度上限。
    isScrollControlled: true,
    builder: (_) => _CategoryTransactionsSheet(
      category: category,
      range: range,
      rangeLabel: rangeLabel,
      kind: kind,
      color: color,
    ),
  );
}

class _CategoryTransactionsSheet extends ConsumerWidget {
  const _CategoryTransactionsSheet({
    required this.category,
    required this.range,
    required this.rangeLabel,
    required this.kind,
    required this.color,
  });

  final CategoryTotal category;
  final LedgerDateRange range;
  final String rangeLabel;

  /// 0 = 支出，1 = 收入。
  final int kind;

  /// 与环形图扇区、排行行同一个分类色。
  final Color color;

  /// 面板高度上限。留出约三成屏幕看得见背后的统计页，
  /// 明白这是一层浮层而不是新页面。
  static const _maxHeightRatio = 0.72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = StatsTokens.of(context);
    final database = ref.watch(databaseProvider);
    final grouped = ref.watch(moneyGroupedProvider);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * _maxHeightRatio,
      ),
      child: Material(
        color: stats.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: StreamBuilder<List<LedgerItem>>(
            stream: database.watchCategoryTransactions(
              range,
              rootCategoryId: category.categoryId,
              kind: kind,
            ),
            builder: (context, snapshot) {
              final items = snapshot.data;
              // 首帧还没数据时，头部先用排行行上的合计占位，
              // 避免金额从空白跳到数字。
              final totalCents = items == null
                  ? category.totalCents
                  : items.fold<int>(
                      0,
                      (sum, item) => sum + item.transaction.amountCents,
                    );
              final entryCount = items?.length ?? category.entryCount;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Grabber(),
                  _Header(
                    category: category,
                    color: color,
                    kind: kind,
                    rangeLabel: rangeLabel,
                    totalCents: totalCents,
                    entryCount: entryCount,
                    grouped: grouped,
                  ),
                  Divider(height: 1, thickness: 1, color: stats.divider),
                  Flexible(
                    child: _Body(
                      items: items,
                      error: snapshot.error,
                      grouped: grouped,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: colors.line,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 面板头：色点+分类名 → 区间·笔数 → 大号合计，整体居中。
///
/// 刻意与下面的明细行**结构相反**。原来这里是「左图标 + 两行文字 +
/// 右侧金额」，和明细行是同一套排布，只是金额粗一点——读起来就是
/// 「列表第一行」，分不清是汇总还是某一笔。
///
/// 现在换成居中、无图标底座、标签在上大数字在下：这是全应用汇总语义的
/// 写法（同概览 Hero 卡），列表行不可能长成这样。居中标题也和项目其他
/// 底部面板（分类编辑、图标选择）的壳一致。
///
/// 色点沿用图例那颗 8×8 方点，而不是明细行的圆形图标底座：既指回环形图
/// 里对应的那一片，又不会和下面的图标列撞形状。
class _Header extends StatelessWidget {
  const _Header({
    required this.category,
    required this.color,
    required this.kind,
    required this.rangeLabel,
    required this.totalCents,
    required this.entryCount,
    required this.grouped,
  });

  final CategoryTotal category;
  final Color color;
  final int kind;
  final String rangeLabel;
  final int totalCents;
  final int entryCount;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: stats.textStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '$rangeLabel · 共 $entryCount 笔',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: stats.rowMeta,
          ),
          const SizedBox(height: 5),
          // 金额位数多时整体缩小而不是换行或被截断——合计数字断掉最难接受。
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatMoney(totalCents, grouped: grouped),
              style: TextStyle(
                fontSize: 27,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: kind == 0 ? colors.expense : colors.income,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.items,
    required this.error,
    required this.grouped,
  });

  final List<LedgerItem>? items;
  final Object? error;
  final bool grouped;

  /// 三种非列表状态共用一个高度，切换时面板不会跳动。
  static const _stateHeight = 168.0;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    if (error != null) {
      return StatsError(body: '$error', height: _stateHeight);
    }
    final items = this.items;
    if (items == null) {
      return const SizedBox(
        height: _stateHeight,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // 打开面板后这个分类的账单被删空（从明细里逐条删、或别处改了分类）。
    if (items.isEmpty) {
      return const StatsEmpty(
        icon: FLucideIcons.receipt,
        title: '这个分类下已没有账单',
        height: _stateHeight,
      );
    }
    return ListView.separated(
      // shrinkWrap 让面板贴合内容：只有两三笔时不该撑满七成屏。
      // 它仍是懒构建——填满高度上限就停，长列表不会全量 build。
      shrinkWrap: true,
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        thickness: 1,
        indent: 18,
        endIndent: 18,
        color: stats.divider,
      ),
      itemBuilder: (context, index) =>
          _TransactionRow(item: items[index], grouped: grouped),
    );
  }
}

/// 明细行：图标 + 二级分类名 + 日期/时间·备注 + 金额。
///
/// 与账单页的行刻意不同：这里整屏都属于同一个一级分类，主标题给
/// **二级分类名**（「餐饮」下的「外卖」「聚餐」）才有区分度；日期挪进副行，
/// 因为面板里是跨天的一段区间，缺了日期无法定位到具体某笔。
class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.item, required this.grouped});

  final LedgerItem item;
  final bool grouped;

  Future<void> _openEditor(BuildContext context) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    await navigator.push<void>(
      MaterialPageRoute(builder: (_) => TransactionEditor(existing: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final colors = context.colors;
    final isExpense = item.transaction.kind == 0;
    final color = isExpense ? colors.expense : colors.income;
    final soft = isExpense ? colors.expenseSoft : colors.incomeSoft;
    final day = dateFromKey(item.transaction.accountingDate);
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      item.transaction.occurredAt,
    );
    final note = item.transaction.note.trim();
    final meta = '${formatDay(day)} ${formatClock(occurredAt)}';

    return InkWell(
      onTap: () => _openEditor(context),
      highlightColor: colors.pressed,
      splashColor: colors.ripple,
      hoverColor: colors.ripple,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
              child: CategoryIconView(
                iconKey: item.category.iconKey,
                color: color,
                size: 19,
                imageSize: 36,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: stats.rowTitle,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    note.isEmpty ? meta : '$meta · $note',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: stats.rowMeta,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatMoney(item.transaction.amountCents, grouped: grouped),
              style: TextStyle(
                fontSize: 15,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
