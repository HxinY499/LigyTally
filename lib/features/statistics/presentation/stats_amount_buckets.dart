import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/ledger_date.dart';
import 'stats_card.dart';
import 'stats_design.dart';
import 'stats_states.dart';

/// 单笔金额分布：每个档位画「金额占比」和「笔数占比」两条。
///
/// 两条必须同时出现才有意义。只看金额条的话，「小额档只占 6%」得不出结论；
/// 配上笔数条才能看出这 6% 是 18 笔攒出来的——金额条短、笔数条长就是
/// 小额高频，反过来就是被几笔大额吃掉。单独任何一条都只是排行。
class AmountBucketList extends StatelessWidget {
  const AmountBucketList({
    super.key,
    required this.buckets,
    required this.kind,
    required this.grouped,
  });

  /// 查询只返回有账单的档位。
  final List<AmountBucket> buckets;

  /// 0 = 支出，1 = 收入。
  final int kind;

  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    if (buckets.isEmpty) {
      // 文案不能和分类构成卡的空态重复。同一屏出现两句一模一样的提示，
      // 读起来像同一块内容被渲染了两遍。
      return StatsEmpty(
        icon: FLucideIcons.chartBarBig,
        title: '没有可分档的${kind == 0 ? '支出' : '收入'}',
        body: '记一笔账单后就能看出钱花在多少笔上',
        height: 168,
      );
    }

    // 空档位补零，让五档始终占同样的位置：档位缺席时整张卡的行数变化，
    // 翻月份时同一档会上下跳。
    final byIndex = {for (final bucket in buckets) bucket.index: bucket};
    final totalCents = buckets.fold<int>(
      0,
      (sum, item) => sum + item.totalCents,
    );
    final totalCount = buckets.fold<int>(
      0,
      (sum, item) => sum + item.entryCount,
    );
    final dominant = buckets.reduce(
      (a, b) => b.totalCents > a.totalCents ? b : a,
    );
    final color = kind == 0 ? stats.expense : stats.income;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Summary(
          label: AmountBucket.labelOf(dominant.index),
          ratio: totalCents == 0 ? 0 : dominant.totalCents / totalCents,
          kind: kind,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < AmountBucket.count; i++)
          _BucketRow(
            label: AmountBucket.labelOf(i),
            bucket: byIndex[i],
            totalCents: totalCents,
            totalCount: totalCount,
            color: color,
            grouped: grouped,
          ),
        const SizedBox(height: 10),
        _Legend(color: color),
      ],
    );
  }
}

/// 结论行：金额最集中的那一档及其占比。
///
/// 五行条形图要用户自己比长短才能得出结论，这里先把答案说出来。
class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.ratio,
    required this.kind,
  });

  final String label;
  final double ratio;
  final int kind;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return Text.rich(
      TextSpan(
        style: stats.captionSection.copyWith(color: stats.textMuted),
        children: [
          TextSpan(text: '${kind == 0 ? '支出' : '收入'}金额最集中在 '),
          TextSpan(
            text: label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: stats.textStrong,
            ),
          ),
          TextSpan(text: '，占 ${(ratio * 100).toStringAsFixed(0)}%'),
        ],
      ),
    );
  }
}

class _BucketRow extends StatelessWidget {
  const _BucketRow({
    required this.label,
    required this.bucket,
    required this.totalCents,
    required this.totalCount,
    required this.color,
    required this.grouped,
  });

  final String label;

  /// null 表示这一档没有账单。
  final AmountBucket? bucket;

  final int totalCents;
  final int totalCount;
  final Color color;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final cents = bucket?.totalCents ?? 0;
    final count = bucket?.entryCount ?? 0;
    final empty = bucket == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              maxLines: 1,
              style: stats.rowMeta.copyWith(
                fontWeight: FontWeight.w600,
                color: empty ? stats.textFaint : stats.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                StatsRatioBar(
                  ratio: totalCents == 0 ? 0 : cents / totalCents,
                  color: color,
                  height: 6,
                ),
                const SizedBox(height: 3),
                StatsRatioBar(
                  ratio: totalCount == 0 ? 0 : count / totalCount,
                  color: color.withValues(alpha: 0.35),
                  height: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatMoney(cents, grouped: grouped),
                    maxLines: 1,
                    style: stats.rowMeta.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: empty ? stats.textFaint : stats.textStrong,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text('$count 笔', style: stats.rowMeta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 两条条形的图例。缺了它，粗细两条只是装饰。
class _Legend extends StatelessWidget {
  const _Legend({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 70),
        _LegendItem(color: color, height: 6, label: '金额占比'),
        const SizedBox(width: 14),
        _LegendItem(
          color: color.withValues(alpha: 0.35),
          height: 4,
          label: '笔数占比',
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.height,
    required this.label,
  });

  final Color color;
  final double height;
  final String label;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return Row(
      children: [
        Container(
          width: 14,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: stats.rowMeta),
      ],
    );
  }
}

/// 单笔金额分布的加载骨架：五行「标签 + 两条」的轮廓。
class StatsBucketSkeleton extends StatelessWidget {
  const StatsBucketSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < AmountBucket.count; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == AmountBucket.count - 1 ? 0 : 14,
            ),
            child: Row(
              children: [
                const StatsSkeleton(width: 52, height: 11),
                const SizedBox(width: 18),
                const Expanded(
                  child: StatsSkeleton(width: double.infinity, height: 6),
                ),
                const SizedBox(width: 10),
                const StatsSkeleton(width: 62, height: 11),
              ],
            ),
          ),
      ],
    );
  }
}
