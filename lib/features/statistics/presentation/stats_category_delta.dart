import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'stats_card.dart';
import 'stats_design.dart';
import 'stats_states.dart';

/// 分类环比：本期相对对照期，哪几个分类花得更多、哪几个更少。
///
/// 存在的理由是概览卡的环比只到总额层面——看到「较上月同期 +12%」之后，
/// 用户下一句要问的是「涨在哪」，而分类构成卡只给当期占比，两期之间的
/// 差额在页面上原本无处可见。
///
/// 只显示有变化的分类，默认每个方向 3 行、超出折叠：差额榜的价值集中在头部，
/// 十几个分类的零碎变化全列出来反而盖住真正的信号。但折叠不能是静默的——
/// 底部始终给出「一共有多少项变化」和展开入口，否则用户无法判断
/// 自己看到的是全部还是片段。
class CategoryDeltaList extends StatefulWidget {
  const CategoryDeltaList({
    super.key,
    required this.deltas,
    required this.kind,
    required this.grouped,
  });

  final List<CategoryDelta> deltas;

  /// 0 = 支出，1 = 收入。决定「增加」是负面还是正面信号。
  final int kind;

  final bool grouped;

  @override
  State<CategoryDeltaList> createState() => _CategoryDeltaListState();
}

class _CategoryDeltaListState extends State<CategoryDeltaList> {
  /// 折叠态下每个方向显示的行数。
  static const _maxRows = 3;

  bool _expanded = false;

  List<CategoryDelta> _visible(List<CategoryDelta> items) =>
      _expanded ? items : items.take(_maxRows).toList();

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final deltas = widget.deltas;
    final kind = widget.kind;
    final grouped = widget.grouped;
    final label = kind == 0 ? '支出' : '收入';
    // 查询只会返回两个区间里出现过的分类，所以空列表意味着两期都没有记录，
    // 这和「有记录但金额一样」是两回事，不能共用一句文案。
    if (deltas.isEmpty) {
      return StatsEmpty(
        title: '本期与对照期都没有$label',
        body: '积累两个周期的记录后即可看到分类增减',
        height: 148,
      );
    }
    final changed = deltas.where((item) => item.deltaCents != 0).toList();
    if (changed.isEmpty) {
      return StatsEmpty(
        icon: FLucideIcons.equal,
        title: '与对照期没有差异',
        body: '各分类$label与上一周期持平',
        height: 148,
      );
    }

    final increased = changed.where((item) => item.deltaCents > 0).toList()
      ..sort((a, b) => b.deltaCents.compareTo(a.deltaCents));
    final decreased = changed.where((item) => item.deltaCents < 0).toList()
      ..sort((a, b) => a.deltaCents.compareTo(b.deltaCents));

    // 是否存在被折叠的项。它不能由「当前可见行数」反推——展开之后
    // 隐藏数归零，按钮会连同收起入口一起消失。
    final overflowing =
        increased.length > _maxRows || decreased.length > _maxRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (increased.isNotEmpty)
          _Group(
            label: '$label增加',
            items: _visible(increased),
            kind: kind,
            grouped: grouped,
          ),
        if (increased.isNotEmpty && decreased.isNotEmpty)
          Divider(height: 18, color: stats.divider, thickness: 1),
        if (decreased.isNotEmpty)
          _Group(
            label: '$label减少',
            items: _visible(decreased),
            kind: kind,
            grouped: grouped,
          ),
        if (overflowing)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: StatsExpandToggle(
              expanded: _expanded,
              collapsedLabel: '展开全部 ${changed.length} 项变化',
              onChanged: (value) => setState(() => _expanded = value),
            ),
          ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.label,
    required this.items,
    required this.kind,
    required this.grouped,
  });

  final String label;
  final List<CategoryDelta> items;
  final int kind;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            label,
            style: stats.captionSection.copyWith(
              fontWeight: FontWeight.w600,
              color: stats.textMuted,
            ),
          ),
        ),
        for (final item in items)
          _DeltaRow(item: item, kind: kind, grouped: grouped),
      ],
    );
  }
}

/// 单个分类的变化行：图标 → 名称 / 两期金额 → 差额 / 幅度。
class _DeltaRow extends StatelessWidget {
  const _DeltaRow({
    required this.item,
    required this.kind,
    required this.grouped,
  });

  final CategoryDelta item;
  final int kind;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final up = item.deltaCents > 0;
    // 支出变多、收入变少都是负面信号，两者共用支出红；反之走收入绿。
    final adverse = kind == 0 ? up : !up;
    final color = adverse ? stats.expense : stats.income;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: CategoryIconView(
              iconKey: item.iconKey,
              size: 17,
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
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: stats.rowTitle,
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatMoney(item.comparisonCents, grouped: grouped)}'
                  ' → ${formatMoney(item.currentCents, grouped: grouped)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: stats.rowMeta,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatMoney(item.deltaCents, signed: true, grouped: grouped),
                style: stats.rowAmount.copyWith(color: color),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    up ? FLucideIcons.arrowUp : FLucideIcons.arrowDown,
                    size: 10,
                    color: color,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _magnitude(item),
                    style: stats.rowMeta.copyWith(color: color),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 变化幅度文案。
///
/// 对照期为 0 时没有基数可比，只能说「新增」；本期归零时百分比恒为 100%，
/// 说「已归零」信息量更大。其余情况才给百分比。
String _magnitude(CategoryDelta item) {
  if (item.comparisonCents == 0) return '新增';
  if (item.currentCents == 0) return '已归零';
  final percent = (item.ratio!.abs()) * 100;
  return '${percent.toStringAsFixed(percent >= 100 ? 0 : 1)}%';
}

/// 分类环比的加载骨架：三行「图标 + 两行文字」的轮廓。
class StatsDeltaSkeleton extends StatelessWidget {
  const StatsDeltaSkeleton({super.key, this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == rows - 1 ? 0 : 14),
            child: Row(
              children: [
                const StatsSkeleton(width: 34, height: 34, radius: 11),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatsSkeleton(width: i.isEven ? 76 : 60, height: 12),
                      const SizedBox(height: 6),
                      const StatsSkeleton(width: 116, height: 10),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const StatsSkeleton(width: 58, height: 12),
              ],
            ),
          ),
      ],
    );
  }
}
