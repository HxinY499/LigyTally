import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'category_transactions_sheet.dart';
import 'stats_card.dart';
import 'stats_charts.dart';
import 'stats_design.dart';

/// 分类构成卡的内容：环形图 + 图例 + 排行榜。
///
/// 相比原实现的结构性改动：
/// - 环形图与图例「点选联动」：点扇区高亮对应排行行，反之亦然
/// - 排行行点击是**下钻**：弹出该分类的账单明细面板，不参与选中态。
///   汇总层已经有环形图 + 图例两处可以点选高亮，排行再做第三处等于
///   把用户锁在汇总层——看到某个分类偏高，下一步想问的是「哪几笔」
/// - 排行行重排为「图标 → 名称/进度条 → 金额/占比」，金额右对齐成一列，
///   原来金额和名称同行、进度条横跨整行，扫读时找不到数字在哪一列
/// - 排行默认只展开前 6 项，超出折叠，避免分类多时卡片长到失控
class CategoryComposition extends StatefulWidget {
  const CategoryComposition({
    super.key,
    required this.totals,
    required this.kind,
    required this.grouped,
    required this.range,
    required this.rangeLabel,
    required this.trendSpans,
    required this.trendCaption,
  });

  final List<CategoryTotal> totals;

  /// 0 = 支出，1 = 收入。
  final int kind;

  final bool grouped;

  /// 当前统计区间：点排行下钻明细时按同一区间查账单。
  final LedgerDateRange range;

  /// 区间文案，显示在明细面板头部，说明「这些账单来自哪一段时间」。
  final String rangeLabel;

  /// 下钻面板里那条走势的周期区间，直接沿用「周期对比」的那一组。
  final List<PeriodSpan> trendSpans;

  /// 走势的范围说明，如「最近 6 个月」。
  final String trendCaption;

  @override
  State<CategoryComposition> createState() => _CategoryCompositionState();
}

class _CategoryCompositionState extends State<CategoryComposition> {
  /// 当前选中的扇区下标；-1 表示未选中。
  int _selected = -1;

  /// 排行榜是否已展开全部。
  bool _expanded = false;

  /// 环形图最多画 5 片，其余合并成「其他」——细碎扇区既看不清也点不中。
  static const _maxSlices = 5;

  /// 排行榜折叠阈值。
  static const _collapsedRows = 6;

  @override
  void didUpdateWidget(CategoryComposition oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换收入/支出或时间区间后，分类列表整体变了，
    // 旧的选中下标会指向另一个分类，必须清掉。
    if (oldWidget.kind != widget.kind ||
        oldWidget.totals.length != widget.totals.length) {
      _selected = -1;
      _expanded = false;
    }
  }

  /// 把分类合计折成环形图扇区（含「其他」聚合）。
  List<CategorySlice> _buildSlices(StatsTokens stats) {
    final totals = widget.totals;
    if (totals.length <= _maxSlices) {
      return [
        for (var i = 0; i < totals.length; i++)
          CategorySlice(
            label: totals[i].name,
            cents: totals[i].totalCents,
            color: stats.categoryColor(i),
          ),
      ];
    }
    final slices = <CategorySlice>[
      for (var i = 0; i < _maxSlices; i++)
        CategorySlice(
          label: totals[i].name,
          cents: totals[i].totalCents,
          color: stats.categoryColor(i),
        ),
    ];
    final rest = totals
        .skip(_maxSlices)
        .fold<int>(0, (sum, item) => sum + item.totalCents);
    slices.add(
      CategorySlice(
        label: '其他 ${totals.length - _maxSlices} 项',
        cents: rest,
        color: stats.categoryRest,
      ),
    );
    return slices;
  }

  void _select(int index) {
    HapticFeedback.selectionClick();
    setState(() => _selected = index);
  }

  /// 下钻到某个分类的账单明细。
  ///
  /// 排行第 6 项之后也能点：它们是真实分类，只是环形图里被并进「其他」
  /// 才统一取灰色。颜色沿用排行行自身的色，面板与来源在视觉上对得上。
  void _openDetails(int index, StatsTokens stats) {
    HapticFeedback.selectionClick();
    final total = widget.totals[index];
    showCategoryTransactionsSheet(
      context,
      categoryId: total.categoryId,
      categoryName: total.name,
      // 只给本期：排行行讲的就是本期占比，这里没有对照期这个问题。
      periods: [
        StatsSheetPeriod(
          range: widget.range,
          rangeLabel: widget.rangeLabel,
          placeholderTotalCents: total.totalCents,
        ),
      ],
      placeholderEntryCount: total.entryCount,
      kind: widget.kind,
      color: index < _maxSlices
          ? stats.categoryColor(index)
          : stats.categoryRest,
      trendSpans: widget.trendSpans,
      trendCaption: widget.trendCaption,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final totals = widget.totals;
    final total = totals.fold<int>(0, (sum, item) => sum + item.totalCents);
    final slices = _buildSlices(stats);
    final visibleRows = _expanded
        ? totals.length
        : (totals.length <= _collapsedRows ? totals.length : _collapsedRows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // 环形图给固定宽度而不是 flex：flex 会让环随图例文字长度变形。
            SizedBox(
              width: 172,
              child: CategoryDonut(
                slices: slices,
                totalCents: total,
                centerLabel: widget.kind == 0 ? '总支出' : '总收入',
                selectedIndex: _selected,
                onSelect: _select,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < slices.length; i++)
                    _LegendRow(
                      slice: slices[i],
                      ratio: total == 0 ? 0 : slices[i].cents / total,
                      dimmed: _selected >= 0 && _selected != i,
                      onTap: () => _select(_selected == i ? -1 : i),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Divider(height: 20, color: stats.divider, thickness: 1),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${widget.kind == 0 ? '支出' : '收入'}排行',
            style: stats.captionSection.copyWith(
              fontWeight: FontWeight.w600,
              color: stats.textMuted,
            ),
          ),
        ),
        for (var i = 0; i < visibleRows; i++)
          CategoryRankRow(
            rank: i + 1,
            item: totals[i],
            totalCents: total,
            // 排行第 i 项与扇区第 i 片同色（超出 5 项后统一走「其他」灰），
            // 保证图例、扇区、排行三处颜色语义一致。
            color: i < _maxSlices ? stats.categoryColor(i) : stats.categoryRest,
            // 选中「其他」那一片时 _selected == _maxSlices，它对应的是聚合项，
            // 不是排行第 6 行那个具体分类，两处都要挡住越界的下标。
            highlighted: _selected == i && _selected < _maxSlices,
            dimmed: _selected >= 0 && _selected != i && _selected < _maxSlices,
            grouped: widget.grouped,
            onTap: () => _openDetails(i, stats),
          ),
        if (totals.length > _collapsedRows)
          StatsExpandToggle(
            expanded: _expanded,
            collapsedLabel: '展开全部 ${totals.length} 个分类',
            onChanged: (value) => setState(() => _expanded = value),
          ),
      ],
    );
  }
}

/// 图例行：色点 + 名称 + 占比，整行可点。
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.ratio,
    required this.dimmed,
    required this.onTap,
  });

  final CategorySlice slice;
  final double ratio;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: StatsTokens.durTap,
        opacity: dimmed ? 0.4 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: slice.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  slice.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: stats.legendLabel,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${(ratio * 100).toStringAsFixed(0)}%',
                style: stats.legendValue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分类排行行：图标底座 + 名称/进度条 + 右侧金额与占比 + 下钻箭头。
class CategoryRankRow extends StatelessWidget {
  const CategoryRankRow({
    super.key,
    required this.rank,
    required this.item,
    required this.totalCents,
    required this.color,
    required this.highlighted,
    required this.dimmed,
    required this.grouped,
    required this.onTap,
  });

  final int rank;
  final CategoryTotal item;
  final int totalCents;
  final Color color;

  /// 与环形图选中项联动的高亮态。
  final bool highlighted;

  /// 其他项被选中时的弱化态。
  final bool dimmed;

  final bool grouped;

  /// 下钻到该分类的账单明细。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final ratio = totalCents == 0 ? 0.0 : item.totalCents / totalCents;
    return AnimatedOpacity(
      duration: StatsTokens.durTap,
      opacity: dimmed ? 0.45 : 1,
      child: Material(
        color: highlighted ? color.withValues(alpha: 0.07) : Colors.transparent,
        borderRadius: BorderRadius.circular(stats.radiusInner),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(stats.radiusChip),
                  ),
                  child: CategoryIconView(
                    iconKey: item.iconKey,
                    size: 17,
                    // 外层是 34 的圆角方块。图片铺满它，圆形裁剪会把
                    // 底座那一圈圆角一并吃掉——一颗小点看着像加载失败，
                    // 满格的圆更接近「这是个图标」。
                    imageSize: 34,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: stats.rowTitle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            formatMoney(item.totalCents, grouped: grouped),
                            style: stats.rowAmount,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: StatsRatioBar(ratio: ratio, color: color),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${(ratio * 100).toStringAsFixed(1)}% · ${item.entryCount} 笔',
                            style: stats.rowMeta,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 可下钻的提示。点击行为从「就地高亮」换成「弹出明细」后，
                // 行内不再有任何即时视觉变化，没有这个箭头用户不会想到能点。
                const SizedBox(width: 2),
                Icon(
                  FLucideIcons.chevronRight,
                  size: 15,
                  color: stats.textFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
