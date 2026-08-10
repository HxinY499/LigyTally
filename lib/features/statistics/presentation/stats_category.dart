import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/ledger_date.dart';
import 'stats_charts.dart';
import 'stats_design.dart';

/// 分类构成卡的内容：环形图 + 图例 + 排行榜。
///
/// 相比原实现的结构性改动：
/// - 环形图与图例改为「点选联动」：点扇区高亮对应排行行，反之亦然
/// - 排行行重排为「图标 → 名称/进度条 → 金额/占比」，金额右对齐成一列，
///   原来金额和名称同行、进度条横跨整行，扫读时找不到数字在哪一列
/// - 排行默认只展开前 6 项，超出折叠，避免分类多时卡片长到失控
class CategoryComposition extends StatefulWidget {
  const CategoryComposition({
    super.key,
    required this.totals,
    required this.kind,
    required this.grouped,
  });

  final List<CategoryTotal> totals;

  /// 0 = 支出，1 = 收入。
  final int kind;

  final bool grouped;

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
  List<CategorySlice> _buildSlices() {
    final totals = widget.totals;
    if (totals.length <= _maxSlices) {
      return [
        for (var i = 0; i < totals.length; i++)
          CategorySlice(
            label: totals[i].name,
            cents: totals[i].totalCents,
            color: StatsTokens.categoryColor(i),
          ),
      ];
    }
    final slices = <CategorySlice>[
      for (var i = 0; i < _maxSlices; i++)
        CategorySlice(
          label: totals[i].name,
          cents: totals[i].totalCents,
          color: StatsTokens.categoryColor(i),
        ),
    ];
    final rest = totals
        .skip(_maxSlices)
        .fold<int>(0, (sum, item) => sum + item.totalCents);
    slices.add(
      CategorySlice(
        label: '其他 ${totals.length - _maxSlices} 项',
        cents: rest,
        color: StatsTokens.categoryRest,
      ),
    );
    return slices;
  }

  void _select(int index) {
    HapticFeedback.selectionClick();
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final totals = widget.totals;
    final total = totals.fold<int>(0, (sum, item) => sum + item.totalCents);
    final slices = _buildSlices();
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
        const Divider(height: 20, color: StatsTokens.divider, thickness: 1),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${widget.kind == 0 ? '支出' : '收入'}排行',
            style: StatsTokens.captionSection.copyWith(
              fontWeight: FontWeight.w600,
              color: StatsTokens.textMuted,
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
            color: i < _maxSlices
                ? StatsTokens.categoryColor(i)
                : StatsTokens.categoryRest,
            highlighted: _selected == i,
            dimmed: _selected >= 0 && _selected != i && _selected < _maxSlices,
            grouped: widget.grouped,
            onTap: i < _maxSlices
                ? () => _select(_selected == i ? -1 : i)
                : null,
          ),
        if (totals.length > _collapsedRows)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                foregroundColor: StatsTokens.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _expanded ? '收起' : '展开全部 ${totals.length} 个分类',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
                  style: StatsTokens.legendLabel,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${(ratio * 100).toStringAsFixed(0)}%',
                style: StatsTokens.legendValue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分类排行行：图标底座 + 名称/进度条 + 右侧金额与占比。
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
    this.onTap,
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = totalCents == 0 ? 0.0 : item.totalCents / totalCents;
    return AnimatedOpacity(
      duration: StatsTokens.durTap,
      opacity: dimmed ? 0.45 : 1,
      child: Material(
        color: highlighted ? color.withValues(alpha: 0.07) : Colors.transparent,
        borderRadius: BorderRadius.circular(StatsTokens.radiusInner),
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
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    categoryIcon(item.iconKey),
                    size: 17,
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
                              style: StatsTokens.rowTitle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            formatMoney(item.totalCents, grouped: grouped),
                            style: StatsTokens.rowAmount,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: _RatioBar(ratio: ratio, color: color),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${(ratio * 100).toStringAsFixed(1)}% · ${item.entryCount} 笔',
                            style: StatsTokens.rowMeta,
                          ),
                        ],
                      ),
                    ],
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

/// 占比进度条：宽度带补间动画，切换区间时是「长出来」而不是瞬间跳变。
///
/// 不用 [LinearProgressIndicator]：它自带 Material 的不确定态与主题色逻辑，
/// 这里只需要一根纯色条 + 一个浅色槽。
class _RatioBar extends StatelessWidget {
  const _RatioBar({required this.ratio, required this.color});

  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 5,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: StatsTokens.fillMuted),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
          duration: StatsTokens.durChart,
          curve: StatsTokens.curveEnter,
          builder: (context, value, _) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            ),
          ),
        ),
      ),
    );
  }
}
