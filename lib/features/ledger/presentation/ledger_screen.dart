import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/ledger_date.dart';
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ligy Tally',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _searching = !_searching;
                      if (!_searching) _query = '';
                    });
                  },
                  tooltip: _searching ? '关闭搜索' : '搜索',
                  icon: Icon(
                    _searching ? Icons.close_rounded : Icons.search_rounded,
                  ),
                ),
                IconButton(
                  onPressed: () => _changeMonth(-1),
                  tooltip: '上个月',
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                SizedBox(
                  width: 112,
                  child: Text(
                    formatMonth(_month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _changeMonth(1),
                  tooltip: '下个月',
                  icon: const Icon(Icons.chevron_right_rounded),
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
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: const InputDecoration(
                  hintText: '搜索备注或分类',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<LedgerFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: LedgerFilter.all, label: Text('全部')),
                  ButtonSegment(value: LedgerFilter.expense, label: Text('支出')),
                  ButtonSegment(value: LedgerFilter.income, label: Text('收入')),
                ],
                selected: {_filter},
                onSelectionChanged: (value) {
                  setState(() => _filter = value.first);
                },
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<LedgerItem>>(
              stream: database.watchTransactions(range, kind: _kind),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _MessageState(
                    icon: Icons.error_outline_rounded,
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
                        ? Icons.receipt_long_outlined
                        : Icons.search_off_rounded,
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
                      Card(
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < group.value.length;
                              index++
                            ) ...[
                              _LedgerTile(
                                item: group.value[index],
                                onTap: () => _edit(group.value[index]),
                                confirmDismiss: () =>
                                    _confirmDelete(group.value[index]),
                              ),
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

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({
    required this.item,
    required this.onTap,
    required this.confirmDismiss,
  });

  final LedgerItem item;
  final VoidCallback onTap;
  final Future<bool> Function() confirmDismiss;

  @override
  Widget build(BuildContext context) {
    final isExpense = item.transaction.kind == 0;
    final color = isExpense ? AppColors.expense : AppColors.income;
    final soft = isExpense ? AppColors.expenseSoft : AppColors.incomeSoft;
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      item.transaction.occurredAt,
    );
    return Dismissible(
      key: ValueKey(item.transaction.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        color: AppColors.expense,
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
                child: Icon(
                  categoryIcon(item.category.iconKey),
                  color: color,
                  size: 21,
                ),
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
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.transaction.note.isEmpty
                          ? formatClock(occurredAt)
                          : '${item.transaction.note} · ${formatClock(occurredAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${isExpense ? '-' : '+'}${formatMoney(item.transaction.amountCents)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
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
