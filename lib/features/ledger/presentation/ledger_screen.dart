import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/database/app_database.dart';
import '../../../core/media/image_storage.dart';
import '../../../core/theme/app_density.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/image_backdrop.dart';
import '../../../shared/widgets/summary_band.dart';
import '../application/providers.dart';
import 'month_calendar_dialog.dart';
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
  late final ScrollController _scrollController;

  /// 本次构建实际渲染出的按天分组，顺序与列表一致。
  ///
  /// 在 build 里记录：分组是「月度流 + 搜索关键词」的产物，只有渲染时才成型。
  /// 月历回调发生在渲染之后，读到的必然是最新一份。
  List<_DayGroup> _dayGroups = const [];

  /// 日期 key → 该天卡片的 GlobalKey，用于滚动对位。
  final Map<String, GlobalKey> _dayCardKeys = {};

  /// 正在高亮的日期 key。从月历跳过来时短暂点亮目标卡片，
  /// 否则滚动停下后用户还得自己找「刚才点的是哪张」。
  String? _highlightedDay;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
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
    if (picked != null && mounted) {
      setState(() {
        _month = picked;
        _dayCardKeys.clear();
        _highlightedDay = null;
      });
    }
  }

  /// 打开当月月历，并处理点选结果：
  /// 有记录的天滚动定位过去，没记录的天直接进「记一笔」。
  Future<void> _openCalendar() async {
    final day = await showMonthCalendar(context, month: _month);
    if (day == null || !mounted) return;
    // 搜索态下列表是过滤后的子集，而月历读的是全量数据：不先清掉关键词，
    // 一个「月历里有金额、列表里被过滤掉」的日子会被误判成没有记录。
    if (_query.isNotEmpty) {
      setState(() {
        _query = '';
        _searchController.clear();
      });
      // 过滤是同步的，一帧之后 _dayGroups 就是全量分组。
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final key = dateKey(day);
    final index = _dayGroups.indexWhere((group) => group.dayKey == key);
    if (index < 0) {
      await _addTransactionForDay(day);
      return;
    }
    setState(() => _highlightedDay = key);
    await _scrollToGroup(index);
    if (!mounted) return;
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightedDay = null);
    });
  }

  /// 把第 [index] 个日卡滚进视口。
  ///
  /// 明细是虚拟列表，目标卡不在视口附近时压根没被构建，拿不到 RenderObject，
  /// [Scrollable.ensureVisible] 也就无从下手。所以先按估高跳到目标附近让它
  /// 进入构建范围，再用 ensureVisible 精确对位——估高只决定「跳得准不准」，
  /// 不决定最终位置，因此不必精确。
  Future<void> _scrollToGroup(int index) async {
    // 页头与月份条都是 pinned sliver，它们盖住的那段视口不算「可见」，
    // 而 ensureVisible 的 alignment 只认视口比例、不认这些遮挡，
    // 所以要自己把遮挡高度折成比例让出来。
    final topInset =
        MediaQuery.paddingOf(context).top +
        kAppHeaderHeight +
        _kMonthBarHeight +
        _kRevealGap;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!_scrollController.hasClients) return;
      final target = _dayCardKeys[_dayGroups[index].dayKey]?.currentContext;
      // mounted 要问目标卡自己：上一轮 jumpTo 之后它可能已经被虚拟列表回收，
      // 此时它的 Element 还在 map 里挂着，但已经不在树上了。
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: topInset / _scrollController.position.viewportDimension,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      // 粗定位的 offset：目标卡在内容里的位置减去遮挡高度。
      // 状态栏留白与月份条在这两项里各出现一次，相减抵消，不必参与计算；
      // 剩下的就是页头折叠量 + 摘要卡区 + 列表上边距 + 前面所有日卡。
      var offset =
          kAppHeaderExpandedHeight -
          kAppHeaderHeight +
          _kSummaryBlockEstimate +
          _kListTopPadding -
          _kRevealGap;
      for (var i = 0; i < index; i++) {
        offset += _estimatedCardHeight(_dayGroups[i].rowCount);
      }
      _scrollController.jumpTo(
        offset.clamp(0, _scrollController.position.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
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
    // 摘要流挪到页头外层：页头现在是 pinned sliver，必须和内容同处一个
    // CustomScrollView（内容要能滚到它背后去，毛玻璃才有东西可模糊），
    // 于是它不能再把内容当 child 包进来。折叠进度由 sliver 的 shrinkOffset
    // 提供，不再是会被重建冲掉的 State，摘要每次到达都重建页头也无副作用。
    return StreamBuilder<LedgerSummary>(
      stream: database.watchSummary(range),
      builder: (context, summarySnapshot) {
        final summary =
            summarySnapshot.data ??
            const LedgerSummary(
              incomeCents: 0,
              expenseCents: 0,
              entryCount: 0,
              activeDayCount: 0,
            );
        return AppPageHeader(
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
          controller: _scrollController,
          slivers: [
            // 金色摘要卡（可跟随滚动上移）
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: SummaryBand(
                  summary: summary,
                  onOpenCalendar: _openCalendar,
                ),
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
                          padding: const EdgeInsets.symmetric(vertical: 80),
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
                    // 记下这一版分组，供月历跳转时定位（见 [_openCalendar]）。
                    _dayGroups = [
                      for (final entry in entries)
                        _DayGroup(
                          dayKey: entry.key,
                          rowCount: entry.value.length,
                        ),
                    ];
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
                            // GlobalKey 挂在最外层：滚动对位时要连卡片下方的
                            // 间距一起算，否则目标卡会紧贴上一张的底边。
                            key: _dayCardKeys.putIfAbsent(
                              group.key,
                              GlobalKey.new,
                            ),
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _DayCard(
                              day: dateFromKey(group.key),
                              items: group.value,
                              imagePaths: imagePaths,
                              highlighted: _highlightedDay == group.key,
                              onTapHeader: () => _addTransactionForDay(
                                dateFromKey(group.key),
                              ),
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
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// 列表里的一天：日期 key + 当天条目数。
///
/// 只留滚动定位需要的两样东西，不持有 [LedgerItem]——那会让这份缓存
/// 跟着账单数据一起变成第二份真相源。
class _DayGroup {
  const _DayGroup({required this.dayKey, required this.rowCount});

  final String dayKey;
  final int rowCount;
}

/// 吸顶月份条高度。滚动定位要减掉它盖住的那段视口，所以提到文件级，
/// 由 [_MonthStickyBarDelegate] 与 [_LedgerScreenState] 共用一个值。
const double _kMonthBarHeight = 44;

// ── 滚动定位用的估高 ──────────────────────────────────────
//
// 这几个值只用来「跳到目标附近，让虚拟列表把目标卡建出来」，
// 最终对位由 [Scrollable.ensureVisible] 完成，所以不必精确，
// 布局改动后也不需要跟着同步——差一点只是多跳一次。

/// 摘要卡区（含上下外边距）估高。
const double _kSummaryBlockEstimate = 201;

/// 明细列表的上边距，与 [SliverPadding] 保持一致。
const double _kListTopPadding = 12;

/// 定位后目标卡与遮挡下沿之间的呼吸距离。
const double _kRevealGap = 8;

/// 一张日卡的估高：卡头 + n 行 + 行间发丝线 + 卡片下外边距。
double _estimatedCardHeight(int rowCount) => 40 + 65 * rowCount + 14;

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

/// 一天一张白色圆角大卡：顶部日期条+ 分割线 + 条目列。
class _DayCard extends ConsumerWidget {
  const _DayCard({
    required this.day,
    required this.items,
    required this.imagePaths,
    required this.highlighted,
    required this.onTapHeader,
    required this.onTapItem,
    required this.onLongPressItem,
  });

  final DateTime day;
  final List<LedgerItem> items;

  /// 账单 id → 首图缩略图相对路径，没有图的账单不在表里。
  final Map<String, String> imagePaths;

  /// 刚从月历跳过来的那一天：短暂描边，让用户认出滚动停在了哪张卡。
  final bool highlighted;

  final VoidCallback onTapHeader;
  final ValueChanged<LedgerItem> onTapItem;
  final ValueChanged<LedgerItem> onLongPressItem;

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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: radii.cardAll,
        // 与统计页图表卡同一组阴影：两屏的卡片浮起高度必须一致，
        // 否则在底部导航来回切换时会觉得「其中一屏是平的」。
        boxShadow: colors.shadowCard,
      ),
      // 高亮描边画在前景，不进上面的 decoration：decoration 的 border 会把
      // 卡片内容向内挤 1.6px，于是「刚被定位到的那张卡」比其它卡窄一圈。
      foregroundDecoration: BoxDecoration(
        borderRadius: radii.cardAll,
        border: Border.all(
          color: highlighted ? colors.primary : Colors.transparent,
          width: 1.6,
        ),
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
    required this.imagePath,
    required this.onTap,
    required this.onLongPress,
  });

  final LedgerItem item;
  final bool grouped;

  /// 这条账单首图的缩略图相对路径，没配图的账单为 null。
  final String? imagePath;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isExpense = item.transaction.kind == 0;
    final color = isExpense ? colors.expense : colors.income;
    final soft = isExpense ? colors.expenseSoft : colors.incomeSoft;
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      item.transaction.occurredAt,
    );
    final note = item.transaction.note.trim();
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
                    note.isEmpty
                        ? formatClock(occurredAt)
                        : '${formatClock(occurredAt)} · $note',
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

/// 吸顶月份/收支条：与页头共用 [AppChromeGlass]。
///
/// pinned 状态下贴在页头下沿。滚动前它作为常规项占位，内容还没穿过，
/// 底板保持不透明；[shrinkOffset] 随自身滚出涨到条高，才挂上和页头
/// 同一套毛玻璃。左侧「年月⌄」可点，唤起月份选择器；右侧显示本月
/// 「支 xx / 收 xx」（跟随 `moneyGroupedProvider` 显示千分位）。
class _MonthStickyBarDelegate extends SliverPersistentHeaderDelegate {
  _MonthStickyBarDelegate({
    required this.month,
    required this.summary,
    required this.onPick,
  });

  final DateTime month;
  final LedgerSummary summary;
  final VoidCallback onPick;

  static const double _height = _kMonthBarHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colors = context.colors;
    return Consumer(
      builder: (context, ref, _) {
        final grouped = ref.watch(moneyGroupedProvider);
        return AppChromeGlass(
            translucency: (shrinkOffset / _height).clamp(0.0, 1.0),
            child: Material(
              // 水波画在毛玻璃这一层。底色交给 [AppChromeGlass]，
              // 这里再铺一层 canvas 会把背后刚模糊出来的内容盖死。
              type: MaterialType.transparency,
              child: SizedBox(
                height: _height,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: onPick,
                        borderRadius: context.radii.chipAll,
                        highlightColor: colors.pressed,
                        splashColor: colors.ripple,
                        hoverColor: colors.ripple,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Text(
                                formatMonth(month),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.ink,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                FLucideIcons.chevronDown,
                                size: 16,
                                color: colors.ink,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '支 ${formatMoney(summary.expenseCents, grouped: grouped)}',
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        '收 ${formatMoney(summary.incomeCents, grouped: grouped)}',
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                    ],
                  ),
                ),
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
    barrierColor: context.colors.barrier,
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
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Material(
          color: colors.surface,
          borderRadius: context.radii.sheetAll,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_year 年 $_month 月',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
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
                      foregroundColor: colors.primary,
                      side: BorderSide(color: colors.primary, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: context.radii.sheetAll,
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
                const SizedBox(height: 8),
                // 与「确定」同宽同高：一长一短会看着像没对齐，
                // 也和 showAppConfirmDialog 的按钮区保持一致。
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.ink,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: context.radii.sheetAll,
                      ),
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
    final colors = context.colors;
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
              color: colors.ink.withValues(alpha: alpha),
            ),
          ),
        );
      },
    );
  }
}
