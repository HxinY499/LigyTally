import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/summary_band.dart';
import '../application/providers.dart';
import 'transaction_editor.dart';

enum LedgerFilter { all, expense, income }

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  LedgerFilter _filter = LedgerFilter.all;
  bool _searching = false;
  String _query = '';

  int? get _kind => switch (_filter) {
    LedgerFilter.all => null,
    LedgerFilter.expense => 0,
    LedgerFilter.income => 1,
  };

  void _changeMonth(int offset) {
    setState(() => _month = DateTime(_month.year, _month.month + offset));
  }

  Future<void> _edit(LedgerItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TransactionEditor(existing: item)),
    );
  }

  // 删除确认：forui 没有 showDialog 的直接替代，保留 Material AlertDialog 兜底。
  Future<bool> _confirmDelete(LedgerItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账单'),
        content: Text('确定删除“${item.category.name}”这笔账单吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    try {
      await ref.read(ledgerServiceProvider).delete(item);
      return true;
    } catch (error) {
      if (mounted) {
        showFToast(
          context: context,
          title: Text('删除失败：$error'),
          variant: FToastVariant.destructive,
          duration: const Duration(seconds: 4),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    final range = monthRange(_month);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // 顶部月份切换栏 —— 用 forui 图标按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                const Spacer(),
                AppIconButton(
                  onPress: () {
                    setState(() {
                      _searching = !_searching;
                      if (!_searching) _query = '';
                    });
                  },
                  icon: Icon(
                    _searching
                        ? FLucideIcons.x
                        : FLucideIcons.search,
                  ),
                ),
                const SizedBox(width: 4),
                AppIconButton(
                  onPress: () => _changeMonth(-1),
                  icon: const Icon(FLucideIcons.chevronLeft),
                ),
                SizedBox(
                  width: 108,
                  child: Text(
                    formatMonth(_month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                AppIconButton(
                  onPress: () => _changeMonth(1),
                  icon: const Icon(FLucideIcons.chevronRight),
                ),
              ],
            ),
          ),
          StreamBuilder<LedgerSummary>(
            stream: database.watchSummary(range),
            builder: (context, snapshot) {
              return SummaryBand(
                summary:
                    snapshot.data ??
                    const LedgerSummary(
                      incomeCents: 0,
                      expenseCents: 0,
                      entryCount: 0,
                    ),
              );
            },
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: AppTextField(
                autofocus: true,
                hint: '搜索备注或分类',
                onChange: (value) => setState(() => _query = value.trim()),
                prefixBuilder: (context, style, variants) =>
                    const Icon(FLucideIcons.search),
              ),
            ),
          // 全部 / 支出 / 收入 —— forui 分段选择器
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: AppSegmentedControl<LedgerFilter>(
              selected: _filter,
              onChanged: (value) => setState(() => _filter = value),
              segments: const [
                AppSegment(value: LedgerFilter.all, label: '全部'),
                AppSegment(value: LedgerFilter.expense, label: '支出'),
                AppSegment(value: LedgerFilter.income, label: '收入'),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<LedgerItem>>(
              stream: database.watchTransactions(range, kind: _kind),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _MessageState(
                    icon: FLucideIcons.circleAlert,
                    title: '账单加载失败',
                    detail: '${snapshot.error}',
                  );
                }
                final allItems = snapshot.data;
                if (allItems == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final keyword = _query.toLowerCase();
                final items = keyword.isEmpty
                    ? allItems
                    : allItems
                          .where(
                            (item) =>
                                item.transaction.note.toLowerCase().contains(
                                  keyword,
                                ) ||
                                item.category.name.toLowerCase().contains(
                                  keyword,
                                ),
                          )
                          .toList();
                if (items.isEmpty) {
                  return _MessageState(
                    icon: keyword.isEmpty
                        ? FLucideIcons.receipt
                        : FLucideIcons.searchX,
                    title: keyword.isEmpty ? '这个月还没有记录' : '没有匹配的账单',
                    detail: keyword.isEmpty ? '点击右下角加号记下第一笔' : '换一个关键词再试',
                  );
                }

                final groups = <String, List<LedgerItem>>{};
                for (final item in items) {
                  groups
                      .putIfAbsent(item.transaction.accountingDate, () => [])
                      .add(item);
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  children: [
                    for (final group in groups.entries) ...[
                      _DayHeader(
                        day: dateFromKey(group.key),
                        items: group.value,
                      ),
                      // forui 卡片包裹当天账单。因为要给每条加Dismissible 滑删
                      // （被包裹后不再是 FItemMixin，无法进 FItemGroup），
                      // 这里用 Column 手动排列 FItem + 分隔线。
                      AppCard(
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < group.value.length;
                              index++
                            ) ...[
                              _ledgerItem(group.value[index]),
                              if (index < group.value.length - 1)
                                const Divider(height: 1, indent: 66),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 单条账单：forui FItem，外面包 Dismissible 实现滑动删除（forui无对应物，Material 兜底）。
  Widget _ledgerItem(LedgerItem item) {
    final isExpense = item.transaction.kind == 0;
    final color = isExpense ? AppColors.expense : AppColors.income;
    final soft = isExpense ? AppColors.expenseSoft : AppColors.incomeSoft;
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      item.transaction.occurredAt,
    );
    return Dismissible(
      key: ValueKey(item.transaction.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(item),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        color: AppColors.expense,
        child: const Icon(FLucideIcons.trash2, color: Colors.white),
      ),
      child: FItem(
        onPress: () => _edit(item),
        prefix: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
          child: Icon(categoryIcon(item.category.iconKey), color: color, size: 21),
        ),
        title: Text(
          item.category.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          item.transaction.note.isEmpty
              ? formatClock(occurredAt)
              : '${item.transaction.note} · ${formatClock(occurredAt)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        suffix: Text(
          '${isExpense ? '-' : '+'}${formatMoney(item.transaction.amountCents)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.items});

  final DateTime day;
  final List<LedgerItem> items;

  @override
  Widget build(BuildContext context) {
    final expense = items
        .where((item) => item.transaction.kind == 0)
        .fold<int>(0, (sum, item) => sum + item.transaction.amountCents);
    final income = items
        .where((item) => item.transaction.kind == 1)
        .fold<int>(0, (sum, item) => sum + item.transaction.amountCents);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Row(
        children: [
          Text(
            '${formatDay(day)} ${formatWeekday(day)}',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            '支 ${formatMoney(expense)}  收 ${formatMoney(income)}',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.muted),
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
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
