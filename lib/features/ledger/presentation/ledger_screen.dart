import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/preferences/money_grouped.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/summary_band.dart';
import '../application/providers.dart';
import 'transaction_editor.dart';

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _searching = false;
  String _query = '';
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _edit(LedgerItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TransactionEditor(existing: item)),
    );
  }

  Future<void> _addTransactionForDay(DateTime day) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TransactionEditor(initialDate: dateOnly(day)),
      ),
    );
  }

  Future<void> _pickMonth() async {
    final picked = await showMonthPicker(context, initial: _month);
    if (picked != null && mounted) setState(() => _month = picked);
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  // 长按弹强确认框（共享的 showAppConfirmDialog：红描边胶囊「确定」+「取消」）。
  Future<void> _confirmDelete(LedgerItem item) async {
    final confirmed = await showAppConfirmDialog(
      context,
      message: '确定要删除该条账单吗？删除后不可恢复',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(ledgerServiceProvider).delete(item);
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          message: '删除失败：$error',
          level: AppToastLevel.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    final range = monthRange(_month);
    return SafeArea(
      bottom: false,
      child: AppPageHeader(
        // 非搜索态走 title，享受大标题折叠；搜索态改用 content 渲染输入框，
        // 页头固定为紧凑高度（输入框不该被缩放）。
        title: _searching ? null : '记账',
        content: _searching
            ? _SearchField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value.trim()),
              )
            : null,
        actions: [
          AppHeaderAction(
            icon: _searching ? FLucideIcons.x : FLucideIcons.search,
            tooltip: _searching ? '关闭搜索' : '搜索',
            onTap: _toggleSearch,
          ),
        ],
        body: StreamBuilder<LedgerSummary>(
          stream: database.watchSummary(range),
          builder: (context, summarySnapshot) {
            final summary =
                summarySnapshot.data ??
                const LedgerSummary(
                  incomeCents: 0,
                  expenseCents: 0,
                  entryCount: 0,
                );
            return CustomScrollView(
              slivers: [
                // 金色摘要卡（可跟随滚动上移）
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: SummaryBand(summary: summary),
                  ),
                ),
                // 吸顶月份/收支条：紧贴页头，粘在顶部。
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _MonthStickyBarDelegate(
                    month: _month,
                    summary: summary,
                    onPick: _pickMonth,
                  ),
                ),
                // 列表
                StreamBuilder<List<LedgerItem>>(
                  stream: database.watchTransactions(range),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return SliverToBoxAdapter(
                        child: _MessageState(
                          icon: FLucideIcons.circleAlert,
                          title: '账单加载失败',
                          detail: '${snapshot.error}',
                        ),
                      );
                    }
                    final allItems = snapshot.data;
                    if (allItems == null) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      );
                    }
                    final keyword = _query.toLowerCase();
                    final items = keyword.isEmpty
                        ? allItems
                        : allItems
                              .where(
                                (item) =>
                                    item.transaction.note
                                        .toLowerCase()
                                        .contains(keyword) ||
                                    item.category.name.toLowerCase().contains(
                                      keyword,
                                    ),
                              )
                              .toList();
                    if (items.isEmpty) {
                      return SliverToBoxAdapter(
                        child: _MessageState(
                          icon: keyword.isEmpty
                              ? FLucideIcons.receipt
                              : FLucideIcons.searchX,
                          title: keyword.isEmpty ? '这个月还没有记录' : '没有匹配的账单',
                          detail: keyword.isEmpty ? '点击右下角加号记下第一笔' : '换一个关键词再试',
                        ),
                      );
                    }
                    final groups = <String, List<LedgerItem>>{};
                    for (final item in items) {
                      groups
                          .putIfAbsent(
                            item.transaction.accountingDate,
                            () => [],
                          )
                          .add(item);
                    }
                    final entries = groups.entries.toList();
                    return SliverPadding(
                      // 底部留白只需避开居中悬浮的「记一笔」FAB
                      // （56 直径 + 16 浮起边距+ 余量）；
                      // 导航栏已贴底固定，不再覆盖列表。
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 84),
                      sliver: SliverList.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final group = entries[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _DayCard(
                              day: dateFromKey(group.key),
                              items: group.value,
                              onTapHeader: () =>
                                  _addTransactionForDay(dateFromKey(group.key)),
                              onTapItem: _edit,
                              onLongPressItem: (item) {
                                HapticFeedback.mediumImpact();
                                _confirmDelete(item);
                              },
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 搜索输入框：点击顶栏搜索图标展开，再次点击关闭并清空关键词。
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // 高38 而非 40：让搜索框在 56 的页头里上下各留 9，
    // 视觉重心与静态标题一致，切换时不会有「页头变胖」的错觉。
    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        autofocus: true,
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 15,
          height: 1.2,
          letterSpacing: -0.1,
          color: AppColors.ink,
        ),
        cursorColor: AppColors.primary,
        cursorRadius: const Radius.circular(2),
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.surface,
          hintText: '搜索备注或分类',
          hintStyle: const TextStyle(
            color: AppColors.inactive,
            fontSize: 15,
            height: 1.2,
            letterSpacing: -0.1,
          ),
          prefixIcon: const Icon(
            FLucideIcons.search,
            size: 16,
            color: AppColors.inactive,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.only(right: 12),
          border: _searchBorder(AppColors.line),
          enabledBorder: _searchBorder(AppColors.line),
          focusedBorder: _searchBorder(AppColors.primary),
        ),
      ),
    );
  }

  /// 搜索框描边：常态发丝灰、聚焦品牌蓝。
  /// 原来三态全是 `BorderSide.none`，白框浮在浅灰底上边界发虚。
  static OutlineInputBorder _searchBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(19),
    borderSide: BorderSide(color: color),
  );
}

/// 一天一张白色圆角大卡：顶部日期条+ 分割线 + 条目列。
class _DayCard extends ConsumerWidget {
  const _DayCard({
    required this.day,
    required this.items,
    required this.onTapHeader,
    required this.onTapItem,
    required this.onLongPressItem,
  });

  final DateTime day;
  final List<LedgerItem> items;
  final VoidCallback onTapHeader;
  final ValueChanged<LedgerItem> onTapItem;
  final ValueChanged<LedgerItem> onLongPressItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = ref.watch(moneyGroupedProvider);
    final expense = items
        .where((item) => item.transaction.kind == 0)
        .fold<int>(0, (sum, item) => sum + item.transaction.amountCents);
    final income = items
        .where((item) => item.transaction.kind == 1)
        .fold<int>(0, (sum, item) => sum + item.transaction.amountCents);
    final today = dateOnly(DateTime.now());
    final yesterday = dateOnly(today.subtract(const Duration(days: 1)));
    String suffix;
    if (day == today) {
      suffix = '今日';
    } else if (day == yesterday) {
      suffix = '昨日';
    } else {
      suffix = formatWeekday(day);
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        // 与统计页图表卡同一组阴影：两屏的卡片浮起高度必须一致，
        // 否则在底部导航来回切换时会觉得「其中一屏是平的」。
        boxShadow: AppShadows.card,
      ),
      // 白底必须由 Material 提供，不能用 Container(color:)。
      //
      // 水波是画在**最近的 Material 上、且在子节点之下**的
      // （`_RenderInkFeatures.paint` 先画 inkFeatures 再 super.paint）。
      // 原来这里是不透明白底的 Container，最近的 Material 是 Scaffold 那层，
      // 于是水波被白卡整块盖住——实测按下时像素零变化，点击毫无反馈。
      // 换成 Material 后卡片自身就是水波画布，反馈才看得见。
      //
      // clipBehavior 让水波贴合圆角，不会在四角溢出成方块。
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: onTapHeader,
              // 卡片头点击加一笔，反馈配色与账单行统一。
              // 只圆上边两角：卡片头贴着卡片顶部，下边是分割线不该有圆角。
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              highlightColor: AppColors.pressed,
              splashColor: AppColors.ripple,
              hoverColor: AppColors.ripple,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: Row(
                  children: [
                    Text(
                      formatDay(day),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      suffix,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '支 ${formatMoney(expense, grouped: grouped)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '收 ${formatMoney(income, grouped: grouped)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 18,
                  endIndent: 18,
                  color: Color(0xFFF1F4F2),
                ),
              _LedgerRow(
                item: items[index],
                grouped: grouped,
                onTap: () => onTapItem(items[index]),
                onLongPress: () => onLongPressItem(items[index]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.item,
    required this.grouped,
    required this.onTap,
    required this.onLongPress,
  });

  final LedgerItem item;
  final bool grouped;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isExpense = item.transaction.kind == 0;
    final color = isExpense ? AppColors.expense : AppColors.income;
    final soft = isExpense ? AppColors.expenseSoft : AppColors.incomeSoft;
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      item.transaction.occurredAt,
    );
    final note = item.transaction.note.trim();
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      // 账单行的点击反馈。
      //
      // 不设 borderRadius：行是卡片中间的一段，四角都不该圆
      // （首行/末行的圆角由外层 Material 的 clipBehavior 统一裁）。
      highlightColor: AppColors.pressed,
      splashColor: AppColors.ripple,
      hoverColor: AppColors.ripple,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
              child: CategoryIconView(
                iconKey: item.category.iconKey,
                color: color,
                size: 21,
                // 外层是 40 的圆底，图片铺满它。
                imageSize: 40,
              ),
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    note.isEmpty
                        ? formatClock(occurredAt)
                        : '${formatClock(occurredAt)} · $note',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${isExpense ? '-' : '+'}${formatMoney(item.transaction.amountCents, grouped: grouped)}',
              style: TextStyle(
                fontSize: 16,
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
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
    );
  }
}

/// 吸顶月份/收支条：与页头一体感——底色沿用页面 canvas，无卡片描边。
///
/// pinned 状态下贴在页头下沿。滚动前它作为常规项占位，滚动到与页头
/// 齐平时锁在原地。左侧「年月⌄」可点，唤起月份选择器；右侧显示
/// 本月「支 xx / 收 xx」（跟随 `moneyGroupedProvider` 显示千分位）。
class _MonthStickyBarDelegate extends SliverPersistentHeaderDelegate {
  _MonthStickyBarDelegate({
    required this.month,
    required this.summary,
    required this.onPick,
  });

  final DateTime month;
  final LedgerSummary summary;
  final VoidCallback onPick;

  static const double _height = 44;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final grouped = ref.watch(moneyGroupedProvider);
        return Material(
          // 吸顶条自己提供 Material：它铺的是页面灰底，
          // 若沿用 Container(color:) 则月份按钮的水波同样会被灰底盖掉。
          color: AppColors.canvas,
          child: Container(
            height: _height,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                InkWell(
                  onTap: onPick,
                  borderRadius: BorderRadius.circular(8),
                  highlightColor: AppColors.pressed,
                  splashColor: AppColors.ripple,
                  hoverColor: AppColors.ripple,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Text(
                          formatMonth(month),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          FLucideIcons.chevronDown,
                          size: 16,
                          color: AppColors.ink,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '支 ${formatMoney(summary.expenseCents, grouped: grouped)}',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(width: 14),
                Text(
                  '收 ${formatMoney(summary.incomeCents, grouped: grouped)}',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  double get maxExtent => _height;

  @override
  double get minExtent => _height;

  @override
  bool shouldRebuild(covariant _MonthStickyBarDelegate oldDelegate) {
    return oldDelegate.month != month ||
        oldDelegate.summary.expenseCents != summary.expenseCents ||
        oldDelegate.summary.incomeCents != summary.incomeCents;
  }
}

/// 从下方弹出的月份选择器：两列滚轮（年/月），iOS 风。
///
/// 用`showGeneralDialog` + 从下往上的 slide 动画，返回选中的 [DateTime]。
/// 参考图里样式：居中白卡、超大标题「YYYY 年 M 月」、下方两列滚轮
/// （当前项加粗黑、周边渐弱），底部蓝色描边胶囊「确定」+ 无边框「取消」。
Future<DateTime?> showMonthPicker(
  BuildContext context, {
  required DateTime initial,
}) {
  return showGeneralDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black45,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, a, b) => _MonthPickerDialog(initial: initial),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initial});

  final DateTime initial;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  /// 年份范围以「今年 ± 20」为窗口，够用又不至于滚太久。
  static const _yearsBack = 20;
  static const _yearsForward = 20;

  late final List<int> _years;
  late int _year;
  late int _month;
  late final FixedExtentScrollController _yearController;
  late final FixedExtentScrollController _monthController;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _years = [
      for (var y = now.year - _yearsBack; y <= now.year + _yearsForward; y++) y,
    ];
    _year = widget.initial.year;
    _month = widget.initial.month;
    final yearIndex = _years.indexOf(_year).clamp(0, _years.length - 1);
    _yearController = FixedExtentScrollController(initialItem: yearIndex);
    _monthController = FixedExtentScrollController(initialItem: _month - 1);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_year 年 $_month 月',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 190,
                  child: Row(
                    children: [
                      Expanded(
                        child: _WheelColumn(
                          controller: _yearController,
                          itemCount: _years.length,
                          onChanged: (index) =>
                              setState(() => _year = _years[index]),
                          labelBuilder: (index) => '${_years[index]}年',
                        ),
                      ),
                      Expanded(
                        child: _WheelColumn(
                          controller: _monthController,
                          itemCount: 12,
                          onChanged: (index) =>
                              setState(() => _month = index + 1),
                          labelBuilder: (index) =>
                              '${(index + 1).toString().padLeft(2, '0')}月',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(DateTime(_year, _month)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      '确定',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: 15, color: AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单列滚轮：iOS `CupertinoPicker` 风格。选中项加粗黑，周边项灰色渐弱。
class _WheelColumn extends StatefulWidget {
  const _WheelColumn({
    required this.controller,
    required this.itemCount,
    required this.onChanged,
    required this.labelBuilder,
  });

  final FixedExtentScrollController controller;
  final int itemCount;
  final ValueChanged<int> onChanged;
  final String Function(int index) labelBuilder;

  @override
  State<_WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<_WheelColumn> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.controller.initialItem;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPicker.builder(
      scrollController: widget.controller,
      itemExtent: 38,
      onSelectedItemChanged: (index) {
        setState(() => _selected = index);
        widget.onChanged(index);
      },
      childCount: widget.itemCount,
      selectionOverlay: const SizedBox.shrink(),
      itemBuilder: (context, index) {
        final offset = (index - _selected).abs();
        final selected = offset == 0;
        final alpha = selected
            ? 1.0
            : offset == 1
            ? 0.55
            : offset == 2
            ? 0.28
            : 0.14;
        return Center(
          child: Text(
            widget.labelBuilder(index),
            style: TextStyle(
              fontSize: selected ? 22 : 17,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: AppColors.ink.withValues(alpha: alpha),
            ),
          ),
        );
      },
    );
  }
}
