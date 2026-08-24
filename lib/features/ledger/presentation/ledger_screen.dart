import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/database/app_database.dart';
import '../../../core/location/place_fix.dart';
import '../../../core/media/image_storage.dart';
import '../../../core/theme/app_density.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/image_backdrop.dart';
import '../../../shared/widgets/summary_band.dart';
import '../application/providers.dart';
import 'month_picker.dart';
import 'transaction_editor.dart';

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key, this.active = true});

  /// 当前是否停在记账 tab。底栏用 PageView，四页都挂在树上，
  /// 返回键只在本页可见且处于多选时拦截。
  final bool active;

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _searching = false;
  bool _selecting = false;
  bool _busy = false;
  String _query = '';
  final Set<String> _selected = {};
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;

  /// 当前列表真正看得见的账单（本月 × 搜索过滤）。
  ///
  /// 全选、删除、勾选清理都只对这份集合生效，不跨月、不碰被关键词滤掉的行。
  List<LedgerItem> _visibleItems = const [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
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

  void _setSelecting(bool value) {
    if (_selecting == value) return;
    setState(() {
      _selecting = value;
      if (!value) {
        _selected.clear();
        _busy = false;
      }
    });
    ref.read(ledgerSelectingProvider.notifier).state = value;
  }

  void _enterSelect() {
    HapticFeedback.selectionClick();
    _setSelecting(true);
  }

  void _exitSelect() => _setSelecting(false);

  void _toggleSelected(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _toggleAllVisible() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.length == _visibleItems.length &&
          _visibleItems.isNotEmpty) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_visibleItems.map((item) => item.transaction.id));
      }
    });
  }

  void _pruneSelection(List<LedgerItem> items) {
    final live = {for (final item in items) item.transaction.id};
    final stale = _selected.where((id) => !live.contains(id)).toList();
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selected.removeAll(stale));
    });
  }

  Future<void> _confirmDeleteSelected() async {
    final chosen = [
      for (final item in _visibleItems)
        if (_selected.contains(item.transaction.id)) item,
    ];
    if (chosen.isEmpty) return;
    final confirmed = await showAppConfirmDialog(
      context,
      message: chosen.length == 1
          ? '确定要删除该条账单吗？删除后不可恢复'
          : '删除这 ${chosen.length} 条账单？删除后不可恢复',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(ledgerServiceProvider).deleteAll(chosen);
      if (!mounted) return;
      _exitSelect();
      showAppToast(
        context,
        message: '已删除 ${chosen.length} 条账单',
        level: AppToastLevel.success,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showAppToast(
          context,
          message: '删除失败：$error',
          level: AppToastLevel.error,
        );
      }
    }
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
    return PopScope(
      canPop: !(_selecting && widget.active),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelect();
      },
      child: Stack(
        children: [
          AppPageHeader(
            // 非搜索/多选态走 title，享受大标题折叠；搜索和多选都改用
            // content，页头固定为紧凑高度（输入框和三栏操作条都不该被缩放）。
            title: _selecting || _searching ? null : '记账',
            content: _selecting
                    ? _SelectModeBar(
                        selectedCount: _selected.length,
                        allSelected:
                            _visibleItems.isNotEmpty &&
                            _selected.length == _visibleItems.length,
                        busy: _busy,
                        onCancel: _exitSelect,
                        onToggleAll: _toggleAllVisible,
                      )
                    : _searching
                    ? _SearchField(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => _query = value.trim()),
                      )
                    : null,
                actions: _selecting
                    ? const []
                    : [
                        AppHeaderAction(
                          icon: _searching
                              ? FLucideIcons.x
                              : FLucideIcons.search,
                          tooltip: _searching ? '关闭搜索' : '搜索',
                          onTap: _toggleSearch,
                        ),
                        AppHeaderAction(
                          icon: FLucideIcons.squareCheck,
                          tooltip: '批量选择',
                          onTap: _enterSelect,
                        ),
                      ],
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: StreamBuilder<LedgerSummary>(
                        stream: database.watchSummary(range),
                        builder: (context, snapshot) {
                          final summary =
                              snapshot.data ??
                              const LedgerSummary(
                                incomeCents: 0,
                                expenseCents: 0,
                                entryCount: 0,
                                activeDayCount: 0,
                              );
                          return SummaryBand(
                            summary: summary,
                            month: _month,
                            onPickMonth: _pickMonth,
                          );
                        },
                      ),
                    ),
                  ),
                  // 列表。图片路径单独订阅一条流：它变得远比账单本身少，
                  // 塞进 watchTransactions 会让每次记账都多 join 一次图片表。
                  StreamBuilder<Map<String, String>>(
                    stream: database.watchFirstImagePaths(range),
                    builder: (context, imageSnapshot) {
                      final imagePaths =
                          imageSnapshot.data ?? const <String, String>{};
                      return StreamBuilder<List<LedgerItem>>(
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
                            return SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 80,
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: context.colors.primary,
                                  ),
                                ),
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
                                          item.category.name
                                              .toLowerCase()
                                              .contains(keyword),
                                    )
                                    .toList();
                          _visibleItems = items;
                          _pruneSelection(items);
                          if (items.isEmpty) {
                            return SliverToBoxAdapter(
                              child: _MessageState(
                                icon: keyword.isEmpty
                                    ? FLucideIcons.receipt
                                    : FLucideIcons.searchX,
                                title: keyword.isEmpty ? '这个月还没有记录' : '没有匹配的账单',
                                detail: keyword.isEmpty
                                    ? '点击右下角加号记下第一笔'
                                    : '换一个关键词再试',
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
                            // 84 是避开居中悬浮的「记一笔」FAB（56 直径 + 16 浮起
                            // 边距 + 余量）。再加上 MediaQuery 的底部留白：贴底档下
                            // 它是 0（那块留白由底栏自己吃掉），悬浮档下它是
                            // 「胶囊盖住的高度 + 系统安全区」，见 `home_shell.dart`。
                            padding: EdgeInsets.fromLTRB(
                              16,
                              12,
                              16,
                              84 + MediaQuery.paddingOf(context).bottom,
                            ),
                            sliver: SliverList.builder(
                              itemCount: entries.length,
                              itemBuilder: (context, index) {
                                final group = entries[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _DayCard(
                                    day: dateFromKey(group.key),
                                    items: group.value,
                                    imagePaths: imagePaths,
                                    selecting: _selecting,
                                    selectedIds: _selected,
                                    onTapHeader: _selecting
                                        ? null
                                        : () => _addTransactionForDay(
                                            dateFromKey(group.key),
                                          ),
                                    onTapItem: _selecting
                                        ? (item) => _toggleSelected(
                                            item.transaction.id,
                                          )
                                        : _edit,
                                    onLongPressItem: _selecting
                                        ? null
                                        : (item) {
                                            HapticFeedback.mediumImpact();
                                            _confirmDelete(item);
                                          },
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              if (_selecting)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16 + MediaQuery.paddingOf(context).bottom,
                  child: _BatchDeleteBar(
                    enabled: _selected.isNotEmpty && !_busy,
                    onDelete: _confirmDeleteSelected,
                  ),
                ),
            ],
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
    final colors = context.colors;
    // 高38 而非 40：让搜索框在 56 的页头里上下各留 9，
    // 视觉重心与静态标题一致，切换时不会有「页头变胖」的错觉。
    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        autofocus: true,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 15,
          height: 1.2,
          letterSpacing: -0.1,
          color: colors.ink,
        ),
        cursorColor: colors.primary,
        cursorRadius: const Radius.circular(2),
        decoration: InputDecoration(
          filled: true,
          fillColor: colors.surface,
          hintText: '搜索备注或分类',
          hintStyle: TextStyle(
            color: colors.inactive,
            fontSize: 15,
            height: 1.2,
            letterSpacing: -0.1,
          ),
          prefixIcon: Icon(
            FLucideIcons.search,
            size: 16,
            color: colors.inactive,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.only(right: 12),
          border: _searchBorder(colors.line, context.radii.blockAll),
          enabledBorder: _searchBorder(colors.line, context.radii.blockAll),
          focusedBorder: _searchBorder(colors.primary, context.radii.blockAll),
        ),
      ),
    );
  }

  /// 搜索框描边：常态发丝灰、聚焦品牌蓝。
  /// 原来三态全是 `BorderSide.none`，白框浮在浅灰底上边界发虚。
  static OutlineInputBorder _searchBorder(Color color, BorderRadius radius) =>
      OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color),
      );
}

/// 多选勾选槽宽。进出多选时按这个宽度把行内容往右挤。
const double _kSelectCheckSize = 22;
const double _kSelectCheckGap = 10;

/// 多选勾选槽：宽度从 0 动画到勾选框，把账单内容往右挤。
///
/// 日卡头传 [showIcon] false，只占位不对齐出空勾，日期和分类图标仍在一条竖线上。
class _SelectCheckSlot extends StatelessWidget {
  const _SelectCheckSlot({
    required this.selecting,
    this.selected = false,
    this.showIcon = true,
  });

  final bool selecting;
  final bool selected;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedSize(
      duration: context.motion(const Duration(milliseconds: 220)),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: selecting
          ? Padding(
              padding: const EdgeInsets.only(right: _kSelectCheckGap),
              child: SizedBox.square(
                dimension: _kSelectCheckSize,
                child: showIcon
                    ? Icon(
                        selected
                            ? FLucideIcons.squareCheck
                            : FLucideIcons.square,
                        size: _kSelectCheckSize,
                        color: selected ? colors.primary : colors.inactive,
                      )
                    : null,
              ),
            )
          : const SizedBox(width: 0, height: _kSelectCheckSize),
    );
  }
}

/// 多选态页头：左全选、中已选数量、右取消。
///
/// 数量放 Stack 正中，不跟两侧文字抢宽度——「全选」变成「取消全选」时标题不能漂。
class _SelectModeBar extends StatelessWidget {
  const _SelectModeBar({
    required this.selectedCount,
    required this.allSelected,
    required this.busy,
    required this.onCancel,
    required this.onToggleAll,
  });

  final int selectedCount;
  final bool allSelected;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '已选择 $selectedCount 项',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
          Row(
            children: [
              _HeaderTextButton(
                label: allSelected ? '取消全选' : '全选',
                onTap: busy ? null : onToggleAll,
              ),
              const Spacer(),
              _HeaderTextButton(label: '取消', onTap: busy ? null : onCancel),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderTextButton extends StatelessWidget {
  const _HeaderTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 38,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: onTap == null ? colors.inactive : colors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 悬浮在页面底部的删除键。没有底板，列表从它背后穿过。
class _BatchDeleteBar extends StatelessWidget {
  const _BatchDeleteBar({required this.enabled, required this.onDelete});

  final bool enabled;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      elevation: 3,
      color: enabled ? colors.danger : colors.fill,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: context.radii.sheetAll,
      child: FilledButton(
        onPressed: enabled ? onDelete : null,
        style: FilledButton.styleFrom(
          backgroundColor: colors.danger,
          foregroundColor: colors.isDark ? colors.canvasBase : Colors.white,
          disabledBackgroundColor: colors.fill,
          disabledForegroundColor: colors.inactive,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: context.radii.sheetAll),
        ),
        child: const Text(
          '删除',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// 一天一张白色圆角大卡：顶部日期条+ 分割线 + 条目列。
class _DayCard extends ConsumerWidget {
  const _DayCard({
    required this.day,
    required this.items,
    required this.imagePaths,
    required this.selecting,
    required this.selectedIds,
    required this.onTapHeader,
    required this.onTapItem,
    required this.onLongPressItem,
  });

  final DateTime day;
  final List<LedgerItem> items;

  /// 账单 id → 首图缩略图相对路径，没有图的账单不在表里。
  final Map<String, String> imagePaths;

  final bool selecting;
  final Set<String> selectedIds;

  final VoidCallback? onTapHeader;
  final ValueChanged<LedgerItem> onTapItem;
  final ValueChanged<LedgerItem>? onLongPressItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
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
    final radii = context.radii;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radii.cardAll,
        // 与统计页图表卡同一组阴影：两屏的卡片浮起高度必须一致，
        // 否则在底部导航来回切换时会觉得「其中一屏是平的」。
        boxShadow: colors.shadowCard,
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
        color: colors.surface,
        borderRadius: radii.cardAll,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: onTapHeader,
              // 卡片头点击加一笔，反馈配色与账单行统一。
              // 只圆上边两角：卡片头贴着卡片顶部，下边是分割线不该有圆角。
              borderRadius: radii.cardTop,
              highlightColor: colors.pressed,
              splashColor: colors.ripple,
              hoverColor: colors.ripple,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: Row(
                  children: [
                    _SelectCheckSlot(selecting: selecting, showIcon: false),
                    Text(
                      formatDay(day),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      suffix,
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                    const Spacer(),
                    Text(
                      '支 ${formatMoney(expense, grouped: grouped)}',
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '收 ${formatMoney(income, grouped: grouped)}',
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                  ],
                ),
              ),
            ),
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 18,
                  endIndent: 18,
                  color: colors.fill,
                ),
              _LedgerRow(
                item: items[index],
                grouped: grouped,
                imagePath: imagePaths[items[index].transaction.id],
                selecting: selecting,
                selected: selectedIds.contains(items[index].transaction.id),
                onTap: () => onTapItem(items[index]),
                onLongPress: onLongPressItem == null
                    ? null
                    : () => onLongPressItem!(items[index]),
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
    required this.imagePath,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final LedgerItem item;
  final bool grouped;

  /// 这条账单首图的缩略图相对路径，没配图的账单为 null。
  final String? imagePath;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isExpense = item.transaction.kind == 0;
    final color = isExpense ? colors.expense : colors.income;
    final soft = isExpense ? colors.expenseSoft : colors.incomeSoft;
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      item.transaction.occurredAt,
    );
    final extra = item.transaction.locationAndNote;
    final row = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      // 账单行的点击反馈。
      //
      // 不设 borderRadius：行是卡片中间的一段，四角都不该圆
      // （首行/末行的圆角由外层 Material 的 clipBehavior 统一裁）。
      highlightColor: colors.pressed,
      splashColor: colors.ripple,
      hoverColor: colors.ripple,
      child: Padding(
        // 垂直内边距跟着显示密度缩：一屏能看几笔账单主要就由这一处和字号
        // 决定，这是「紧凑 / 宽松」这档设置真正要买的东西。
        // 水平不跟着缩——左右留白是版面骨架，与设置页的行同一条规则。
        padding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: context.density.space(12),
        ),
        child: Row(
          children: [
            _SelectCheckSlot(selecting: selecting, selected: selected),
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

    final relativePath = imagePath;
    if (relativePath == null) return row;
    final file = ImageStorage.resolveSyncPath(relativePath);
    if (file == null) return row;
    return Stack(
      children: [
        Positioned.fill(
          child: ImageBackdrop(
            image: ResizeImage(
              FileImage(File(file)),
              width: _kRowBackdropDecodeWidth,
              allowUpscaling: false,
            ),
            blurSigma: _kRowBackdropBlurSigma,
            maxOpacity: _kRowBackdropOpacity,
            // 横向渐隐：色从分类图标那侧化开，右边的金额留在干净底色上。
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            alignment: Alignment.center,
          ),
        ),
        row,
      ],
    );
  }
}

/// 行背板的解码宽度。一行才 60 出头的高度，再清晰也是浪费。
const int _kRowBackdropDecodeWidth = 240;

/// 行背板固定这一档模糊，不跟设置页的记账页背景走——列表要的是一眼扫过
/// 「这笔有照片」，不是看照片本身。
const double _kRowBackdropBlurSigma = 24;

/// 比记账页淡：行里挤着分类名、时间备注这些小字，浓了压不住。
const double _kRowBackdropOpacity = 0.3;

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
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: colors.muted),
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
        ],
      ),
    );
  }
}
