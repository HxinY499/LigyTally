import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/providers.dart';
import '../../statistics/application/stats_exclusion.dart';
import '../../statistics/presentation/stats_card.dart';
import '../../statistics/presentation/stats_charts.dart';
import '../../statistics/presentation/stats_design.dart';
import '../../statistics/presentation/stats_exclusion.dart';
import '../application/ai_turn_format.dart';

/// AI 回答正文 `<chart>` 标记渲染的实时统计图卡。
///
/// 不接收模型手写的数据点，直接订阅本地 Drift 查询并复用统计页图表组件：
/// 账单增删改后聊天记录里的图表自动同步，无算术偏差。无数据时静默隐藏。
class AiChartCard extends ConsumerStatefulWidget {
  const AiChartCard({super.key, required this.spec});

  final AiChartSpec spec;

  @override
  ConsumerState<AiChartCard> createState() => _AiChartCardState();
}

class _AiChartCardState extends ConsumerState<AiChartCard> {
  Set<String>? _fallbackStatsExcluded;

  @override
  void initState() {
    super.initState();
    _ensureExclusionLoaded();
  }

  @override
  void didUpdateWidget(AiChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spec.useStatsExclusion && !oldWidget.spec.useStatsExclusion) {
      _ensureExclusionLoaded();
    }
  }

  void _ensureExclusionLoaded() {
    if (!widget.spec.useStatsExclusion) return;
    unawaited(
      readStatsExcludedIds().then((ids) {
        if (mounted) setState(() => _fallbackStatsExcluded = ids);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    final grouped = ref.watch(moneyGroupedProvider);
    final exclusionState = ref.watch(statsExclusionProvider);

    Set<String> statsIds = const {};
    if (widget.spec.useStatsExclusion) {
      if (exclusionState.ready) {
        statsIds = exclusionState.ids;
      } else if (_fallbackStatsExcluded != null) {
        statsIds = _fallbackStatsExcluded!;
      } else {
        return const SizedBox.shrink();
      }
    }
    final excludedIds = <String>{
      ...statsIds,
      ...widget.spec.excludedCategoryIds,
    };

    return StreamBuilder<List<CategoryEntry>>(
      stream: database.watchAllCategories(activeOnly: false),
      builder: (context, catSnap) {
        final categories = catSnap.data ?? const <CategoryEntry>[];
        return switch (widget.spec.type) {
          AiChartType.trend => _TrendCard(
            spec: widget.spec,
            database: database,
            categories: categories,
            excludedIds: excludedIds,
          ),
          AiChartType.category => _CategoryCard(
            spec: widget.spec,
            database: database,
            categories: categories,
            excludedIds: excludedIds,
            grouped: grouped,
          ),
          AiChartType.delta => _DeltaCard(
            spec: widget.spec,
            database: database,
            categories: categories,
            excludedIds: excludedIds,
            grouped: grouped,
          ),
        };
      },
    );
  }
}

class _ChartShell extends StatelessWidget {
  const _ChartShell({
    required this.title,
    required this.caption,
    required this.child,
  });

  final String title;
  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      shape: context.radii.cardShape(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            StatsSectionHeader(title: title, caption: caption),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.spec,
    required this.database,
    required this.categories,
    required this.excludedIds,
  });

  final AiChartSpec spec;
  final AppDatabase database;
  final List<CategoryEntry> categories;
  final Set<String> excludedIds;

  @override
  Widget build(BuildContext context) {
    final range = LedgerDateRange(
      spec.from,
      spec.to.add(const Duration(days: 1)),
    );
    final groupByMonth =
        spec.granularity == 'month' ||
        (spec.granularity == null && range.dayCount > 62);
    final catName = _categoryNameOf(categories, spec.categoryId);
    final exclusionLabel = _exclusionLabel(categories, excludedIds);
    final kindLabel = switch (spec.kind) {
      1 => '收入',
      2 => '结余',
      _ => '支出',
    };
    final defaultTitle = catName == null
        ? '$kindLabel趋势'
        : '$catName · $kindLabel趋势';
    final captionParts = <String>[
      _formatRange(spec.from, spec.to),
      groupByMonth ? '按月' : '按天',
      if (exclusionLabel.isNotEmpty) exclusionLabel,
    ];

    return StreamBuilder<List<TrendPoint>>(
      stream: database.watchTrend(
        range,
        groupByMonth: groupByMonth,
        categoryId: spec.categoryId,
        excludedCategoryIds: excludedIds,
      ),
      builder: (context, snapshot) {
        final raw = snapshot.data;
        if (raw == null || raw.isEmpty) return const SizedBox.shrink();

        if (groupByMonth) {
          final months = _monthsBetween(spec.from, spec.to);
          if (months.length >= 2 && months.length <= 12) {
            final byBucket = {for (final p in raw) p.bucket: p};
            final crossYear = months.first.year != months.last.year;
            final bars = [
              for (final m in months)
                () {
                  final key =
                      '${m.year.toString().padLeft(4, '0')}-'
                      '${m.month.toString().padLeft(2, '0')}';
                  final pt = byBucket[key];
                  return PeriodBar(
                    label: crossYear
                        ? '${m.year % 100}/${m.month}'
                        : '${m.month}月',
                    expenseCents: pt?.expenseCents ?? 0,
                    incomeCents: pt?.incomeCents ?? 0,
                  );
                }(),
            ];
            final hasData = bars.any((bar) {
              if (spec.kind == 2) {
                return bar.expenseCents > 0 || bar.incomeCents > 0;
              }
              return (spec.kind == 1 ? bar.incomeCents : bar.expenseCents) > 0;
            });
            if (!hasData) return const SizedBox.shrink();

            final now = DateTime.now();
            final lastMonth = months.last;
            final includesCurrent =
                lastMonth.year == now.year && lastMonth.month == now.month;

            return _ChartShell(
              title: spec.title ?? defaultTitle,
              caption: captionParts.join(' · '),
              child: SizedBox(
                height: 176,
                child: PeriodBarChart(
                  bars: bars,
                  kind: spec.kind,
                  highlightLastAsCurrent: includesCurrent,
                ),
              ),
            );
          }
        }

        final lineKind = spec.kind == 1 ? 1 : 0;
        final hasData = raw.any(
          (p) => (lineKind == 0 ? p.expenseCents : p.incomeCents) > 0,
        );
        if (!hasData) return const SizedBox.shrink();

        return _ChartShell(
          title: spec.title ?? defaultTitle,
          caption: captionParts.join(' · '),
          child: SizedBox(
            height: 168,
            child: TrendLineChart(points: raw, kind: lineKind),
          ),
        );
      },
    );
  }

  static List<DateTime> _monthsBetween(DateTime from, DateTime to) {
    final out = <DateTime>[];
    var cursor = DateTime(from.year, from.month);
    final end = DateTime(to.year, to.month);
    while (!cursor.isAfter(end)) {
      out.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return out;
  }
}

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({
    required this.spec,
    required this.database,
    required this.categories,
    required this.excludedIds,
    required this.grouped,
  });

  final AiChartSpec spec;
  final AppDatabase database;
  final List<CategoryEntry> categories;
  final Set<String> excludedIds;
  final bool grouped;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  int _selected = -1;
  static const _maxSlices = 5;

  @override
  void didUpdateWidget(_CategoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec.identityKey != widget.spec.identityKey) {
      _selected = -1;
    }
  }

  List<CategorySlice> _buildSlices(
    List<CategoryTotal> totals,
    StatsTokens stats,
  ) {
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
    final rest = totals
        .skip(_maxSlices)
        .fold<int>(0, (sum, item) => sum + item.totalCents);
    return [
      for (var i = 0; i < _maxSlices; i++)
        CategorySlice(
          label: totals[i].name,
          cents: totals[i].totalCents,
          color: stats.categoryColor(i),
        ),
      CategorySlice(
        label: '其他 ${totals.length - _maxSlices} 项',
        cents: rest,
        color: stats.categoryRest,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final kind = spec.kind == 1 ? 1 : 0;
    final range = LedgerDateRange(
      spec.from,
      spec.to.add(const Duration(days: 1)),
    );
    final parentName = _categoryNameOf(widget.categories, spec.categoryId);
    final exclusionLabel = _exclusionLabel(
      widget.categories,
      widget.excludedIds,
    );
    final kindLabel = kind == 0 ? '支出' : '收入';
    final defaultTitle = parentName == null
        ? '$kindLabel分类构成'
        : '$parentName · 二级构成';
    final captionParts = <String>[
      _formatRange(spec.from, spec.to),
      if (exclusionLabel.isNotEmpty) exclusionLabel,
    ];

    final stream = spec.categoryId != null
        ? widget.database.watchSubcategoryTotals(
            range,
            rootCategoryId: spec.categoryId!,
            kind: kind,
            excludedCategoryIds: widget.excludedIds,
          )
        : widget.database.watchCategoryTotals(
            range,
            kind,
            excludedCategoryIds: widget.excludedIds,
          );

    return StreamBuilder<List<CategoryTotal>>(
      stream: stream,
      builder: (context, snapshot) {
        final totals = snapshot.data;
        if (totals == null || totals.isEmpty) return const SizedBox.shrink();
        final stats = StatsTokens.of(context);
        final totalCents = totals.fold<int>(0, (s, item) => s + item.totalCents);
        if (totalCents <= 0) return const SizedBox.shrink();
        final slices = _buildSlices(totals, stats);
        final validSelected = _selected >= 0 && _selected < slices.length
            ? _selected
            : -1;

        return _ChartShell(
          title: spec.title ?? defaultTitle,
          caption: captionParts.join(' · '),
          child: Row(
            children: [
              SizedBox(
                width: 156,
                child: CategoryDonut(
                  slices: slices,
                  totalCents: totalCents,
                  centerLabel: parentName ?? '总$kindLabel',
                  selectedIndex: validSelected,
                  onSelect: (index) {
                    HapticFeedback.selectionClick();
                    setState(() => _selected = index);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < slices.length; i++)
                      _SliceLegendItem(
                        slice: slices[i],
                        ratio: slices[i].cents / totalCents,
                        dimmed: validSelected >= 0 && validSelected != i,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(
                            () => _selected = validSelected == i ? -1 : i,
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SliceLegendItem extends StatelessWidget {
  const _SliceLegendItem({
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
          padding: const EdgeInsets.symmetric(vertical: 3.5),
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
              const SizedBox(width: 7),
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

class _DeltaCard extends StatefulWidget {
  const _DeltaCard({
    required this.spec,
    required this.database,
    required this.categories,
    required this.excludedIds,
    required this.grouped,
  });

  final AiChartSpec spec;
  final AppDatabase database;
  final List<CategoryEntry> categories;
  final Set<String> excludedIds;
  final bool grouped;

  @override
  State<_DeltaCard> createState() => _DeltaCardState();
}

class _DeltaCardState extends State<_DeltaCard> {
  static const _collapsedLimit = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final compareFrom = spec.compareFrom;
    final compareTo = spec.compareTo;
    if (compareFrom == null || compareTo == null) {
      return const SizedBox.shrink();
    }
    final kind = spec.kind == 1 ? 1 : 0;
    final current = LedgerDateRange(
      spec.from,
      spec.to.add(const Duration(days: 1)),
    );
    final comparison = LedgerDateRange(
      compareFrom,
      compareTo.add(const Duration(days: 1)),
    );
    final exclusionLabel = _exclusionLabel(
      widget.categories,
      widget.excludedIds,
    );
    final kindLabel = kind == 0 ? '支出' : '收入';
    final captionParts = <String>[
      '${_formatRange(compareFrom, compareTo)} → ${_formatRange(spec.from, spec.to)}',
      if (exclusionLabel.isNotEmpty) exclusionLabel,
    ];

    return StreamBuilder<List<CategoryDelta>>(
      stream: widget.database.watchCategoryDeltas(
        current: current,
        comparison: comparison,
        kind: kind,
        excludedCategoryIds: widget.excludedIds,
      ),
      builder: (context, snapshot) {
        final deltas = snapshot.data;
        if (deltas == null) return const SizedBox.shrink();
        final changed = deltas.where((d) => d.deltaCents != 0).toList()
          ..sort((a, b) => b.deltaCents.abs().compareTo(a.deltaCents.abs()));
        if (changed.isEmpty) return const SizedBox.shrink();

        final visible = _expanded
            ? changed
            : changed.take(_collapsedLimit).toList();
        final stats = StatsTokens.of(context);

        return _ChartShell(
          title: spec.title ?? '$kindLabel分类变化',
          caption: captionParts.join(' · '),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in visible)
                _CompactDeltaRow(
                  item: item,
                  kind: kind,
                  grouped: widget.grouped,
                  stats: stats,
                ),
              if (changed.length > _collapsedLimit)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: StatsExpandToggle(
                    expanded: _expanded,
                    collapsedLabel: '展开全部 ${changed.length} 项变化',
                    onChanged: (value) => setState(() => _expanded = value),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CompactDeltaRow extends StatelessWidget {
  const _CompactDeltaRow({
    required this.item,
    required this.kind,
    required this.grouped,
    required this.stats,
  });

  final CategoryDelta item;
  final int kind;
  final bool grouped;
  final StatsTokens stats;

  String _magnitude() {
    if (item.comparisonCents == 0) return '新增';
    if (item.currentCents == 0) return '已归零';
    final percent = item.ratio!.abs() * 100;
    return '${percent.toStringAsFixed(percent >= 100 ? 0 : 1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final up = item.deltaCents > 0;
    final adverse = kind == 0 ? up : !up;
    final color = adverse ? stats.expense : stats.income;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CategoryIconBadge(
            iconKey: item.iconKey,
            color: color,
            background: color.withValues(alpha: 0.12),
          ),
          const SizedBox(width: 10),
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
                const SizedBox(height: 2),
                Text(
                  '${formatMoney(item.comparisonCents, grouped: grouped)} → '
                  '${formatMoney(item.currentCents, grouped: grouped)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: stats.rowMeta,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatMoney(item.deltaCents, signed: true, grouped: grouped),
                style: stats.rowAmount.copyWith(color: color),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    up ? FLucideIcons.arrowUp : FLucideIcons.arrowDown,
                    size: 10,
                    color: color,
                  ),
                  const SizedBox(width: 2),
                  Text(_magnitude(), style: stats.rowMeta.copyWith(color: color)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String? _categoryNameOf(List<CategoryEntry> categories, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final c in categories) {
    if (c.id == id) return c.name;
  }
  return null;
}

String _exclusionLabel(
  List<CategoryEntry> categories,
  Set<String> excludedIds,
) {
  if (excludedIds.isEmpty) return '';
  return statsExclusionCaption(
    resolveExcludedCategories(categories, excludedIds),
  );
}

String _formatRange(DateTime from, DateTime to) {
  final nowYear = DateTime.now().year;
  String fmt(DateTime d, {required bool forceYear}) {
    if (forceYear || d.year != nowYear) {
      return '${d.year}/${d.month}/${d.day}';
    }
    return '${d.month}/${d.day}';
  }

  if (from == to) return fmt(from, forceYear: false);
  final crossYear = from.year != to.year;
  return '${fmt(from, forceYear: crossYear)} - ${fmt(to, forceYear: crossYear)}';
}
