import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/ledger_date.dart';
import 'stats_design.dart';
import 'statistics_window.dart';

/// 周期选择器：白色轨道 + 滑动高亮胶囊。
///
/// 原来用一排outline / primary 按钮拼成分段器，五个按钮各带描边，
/// 视觉噪音大且切换时没有连续性（选中态在两个按钮间「闪」）。
/// 改成轨道 + 单个滑块后，切换是一段连续位移，也只剩一条外轮廓。
class StatsPeriodSelector extends StatelessWidget {
  const StatsPeriodSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final StatisticsPeriod selected;
  final ValueChanged<StatisticsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    const values = StatisticsPeriod.values;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: stats.fillMuted,
        borderRadius: BorderRadius.circular(StatsTokens.radiusPill),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = constraints.maxWidth / values.length;
          final index = values.indexOf(selected);
          return Stack(
            children: [
              // 高亮滑块：跟随选中项平移。
              AnimatedPositioned(
                duration: StatsTokens.durTap,
                curve: StatsTokens.curveEnter,
                left: slotWidth * index,
                top: 0,
                bottom: 0,
                width: slotWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: stats.surface,
                    borderRadius: BorderRadius.circular(StatsTokens.radiusPill),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14101828),
                        offset: Offset(0, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final value in values)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(value);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: StatsTokens.durTap,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: value == selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: value == selected
                                  ? stats.primary
                                  : stats.textMuted,
                            ),
                            child: Text(value.label),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 概览 Hero 卡：区间切换 + 支出大数字 + 环比 + 三项次级指标。
///
/// 设计意图：统计页最该被一眼看到的是「这段时间花了多少」，
/// 原实现把支出和收入并排放成两个同等大小的数字，加上下方一行小字，
/// 视觉上没有重心。这里改成单一 Hero 数字 +渐变底，
/// 其余指标降级为底部三等分小块，层级一次拉开。
class StatsOverviewCard extends StatelessWidget {
  const StatsOverviewCard({
    super.key,
    required this.window,
    required this.current,
    required this.previous,
    required this.grouped,
    required this.onShift,
    required this.onPickRange,
  });

  final StatisticsWindow window;

  /// 本期汇总；null 表示仍在加载。
  final LedgerSummary? current;

  /// 上期汇总；null 表示仍在加载。
  final LedgerSummary? previous;

  /// 是否按千分位分组展示金额（跟随全局设置）。
  final bool grouped;

  final ValueChanged<int> onShift;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final summary = current;
    final canGoForward = !window.includesToday;

    return Container(
      decoration: BoxDecoration(
        gradient: stats.heroGradient,
        borderRadius: BorderRadius.circular(StatsTokens.radiusCard),
        boxShadow: stats.shadowHero,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RangeSwitcher(
              label: window.rangeLabel,
              canGoForward: canGoForward,
              onShift: onShift,
              onPickRange: onPickRange,
              isCustom: window.period == StatisticsPeriod.custom,
            ),
            const SizedBox(height: 14),
            const Text('本期支出', style: StatsTokens.heroLabel),
            const SizedBox(height: 6),
            // 大数字：加载中给骨架条，避免先渲染 ¥0.00 再跳到真实值
            //（那一下跳变看着像数据出错）。
            if (summary == null)
              const _HeroBar(width: 168, height: 38)
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _heroMoney(summary.expenseCents, grouped: grouped),
                        maxLines: 1,
                        style: StatsTokens.heroAmount,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _DeltaBadge(
                      previousLabel: window.previousLabel,
                      currentCents: summary.expenseCents,
                      previousCents: previous?.expenseCents,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            Container(height: 1, color: StatsTokens.onHeroDivider),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _HeroMiniStat(
                    label: '本期收入',
                    value: summary == null
                        ? null
                        : _heroMoney(summary.incomeCents, grouped: grouped),
                  ),
                ),
                const _HeroMiniDivider(),
                Expanded(
                  child: _HeroMiniStat(
                    label: '净收支',
                    value: summary == null
                        ? null
                        : _heroMoney(
                            summary.netCents,
                            grouped: grouped,
                            signed: true,
                          ),
                  ),
                ),
                const _HeroMiniDivider(),
                Expanded(
                  child: _HeroMiniStat(
                    label: '日均支出',
                    value: summary == null
                        ? null
                        : _heroMoney(
                            summary.expenseCents ~/
                                math.max(1, window.range.dayCount),
                            grouped: grouped,
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  FLucideIcons.receipt,
                  size: 13,
                  color: StatsTokens.onHeroTertiary,
                ),
                const SizedBox(width: 5),
                Text(
                  summary == null
                      ? '统计中…'
                      : '共${summary.entryCount} 笔记录 · 跨 ${window.range.dayCount} 天',
                  style: StatsTokens.heroLabel.copyWith(
                    fontSize: 11,
                    color: StatsTokens.onHeroTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Hero 卡内的金额：不带 `¥`，让大数字更干净（卡内已有「支出」语义）。
String _heroMoney(int cents, {required bool grouped, bool signed = false}) {
  final text = formatMoney(cents, signed: signed, grouped: grouped);
  return text.replaceFirst('¥', '');
}

/// 区间切换条：左右箭头 + 中间可点的区间文案。
class _RangeSwitcher extends StatelessWidget {
  const _RangeSwitcher({
    required this.label,
    required this.canGoForward,
    required this.onShift,
    required this.onPickRange,
    required this.isCustom,
  });

  final String label;
  final bool canGoForward;
  final ValueChanged<int> onShift;
  final VoidCallback onPickRange;
  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RangeArrow(icon: FLucideIcons.chevronLeft, onTap: () => onShift(-1)),
        Expanded(
          child: GestureDetector(
            onTap: onPickRange,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: StatsTokens.onHeroPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                // 只有自定义模式点中间才会弹日期选择器，
                // 所以只在该模式给出「可点」的视觉暗示。
                if (isCustom) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    FLucideIcons.calendar,
                    size: 13,
                    color: StatsTokens.onHeroSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),
        _RangeArrow(
          icon: FLucideIcons.chevronRight,
          // 已经到「包含今天」的区间就不让继续往后翻。
          onTap: canGoForward ? () => onShift(1) : null,
        ),
      ],
    );
  }
}

class _RangeArrow extends StatelessWidget {
  const _RangeArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? const Color(0x1FFFFFFF) : Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: 17,
            color: enabled
                ? StatsTokens.onHeroPrimary
                : StatsTokens.onHeroTertiary.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

/// 环比徽章：半透明白底 + 箭头 + 百分比。
///
/// 支出场景下「涨」是负面信号，所以上涨用暖色（浅红），下降用浅绿。
/// 放在Hero 卡里不能用纯饱和红绿——在蓝底上会显得刺眼且降低可读性，
/// 因此选了两个偏亮的低饱和色。
class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({
    required this.previousLabel,
    required this.currentCents,
    required this.previousCents,
  });

  final String previousLabel;
  final int currentCents;

  /// null 表示上期数据还在加载。
  final int? previousCents;

  @override
  Widget build(BuildContext context) {
    final base = previousCents;
    if (base == null) return const SizedBox.shrink();

    final diff = currentCents - base;
    // 没有基数时算不出百分比：区分「上期也是0」和「上期为 0 但本期有支出」。
    if (base == 0) {
      final text = currentCents == 0
          ? '$previousLabel 持平'
          : '$previousLabel 新增';
      return _BadgeShell(
        icon: currentCents == 0 ? FLucideIcons.minus : FLucideIcons.arrowUp,
        text: text,
        color: currentCents == 0
            ? StatsTokens.onHeroSecondary
            : const Color(0xFFFFD5CE),
      );
    }
    if (diff == 0) {
      return _BadgeShell(
        icon: FLucideIcons.minus,
        text: '$previousLabel 持平',
        color: StatsTokens.onHeroSecondary,
      );
    }

    final up = diff > 0;
    final percent = diff.abs() / base * 100;
    return _BadgeShell(
      icon: up ? FLucideIcons.arrowUp : FLucideIcons.arrowDown,
      text: '${percent.toStringAsFixed(percent >= 100 ? 0 : 1)}%',
      color: up ? const Color(0xFFFFD5CE) : const Color(0xFFC8F0D4),
    );
  }
}

class _BadgeShell extends StatelessWidget {
  const _BadgeShell({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x24FFFFFF),
        borderRadius: BorderRadius.circular(StatsTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMiniStat extends StatelessWidget {
  const _HeroMiniStat({required this.label, required this.value});

  final String label;

  /// null 表示加载中。
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: StatsTokens.heroLabel.copyWith(fontSize: 11)),
        const SizedBox(height: 5),
        if (value == null)
          const _HeroBar(width: 56, height: 16)
        else
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value!, maxLines: 1, style: StatsTokens.heroMini),
          ),
      ],
    );
  }
}

class _HeroMiniDivider extends StatelessWidget {
  const _HeroMiniDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: StatsTokens.onHeroDivider,
    );
  }
}

/// Hero 卡内的加载条：半透明白，和蓝底同色系，不像灰骨架那样突兀。
class _HeroBar extends StatelessWidget {
  const _HeroBar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
