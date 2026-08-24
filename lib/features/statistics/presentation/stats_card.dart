import 'package:flutter/material.dart';

import 'stats_design.dart';

/// 统计页统一卡片壳：白面 + 大圆角 + 双层阴影，无描边。
///
/// 不复用 `AppCard`（forui FCard）的原因：FCard 是「描边 + 8px 圆角」的
/// 表单型卡片，用在图表区会显得局促且边线抢眼。统计页需要的是更舒展的
/// 「浮起卡片」，所以这里单独定义，样式集中在 [StatsTokens]。
class StatsCard extends StatelessWidget {
  const StatsCard({
    super.key,
    required this.child,
    this.padding = StatsTokens.padCard,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;

  /// 非空时整卡可点，并带水波反馈。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: stats.surface,
        borderRadius: BorderRadius.circular(stats.radiusCard),
        boxShadow: stats.shadowCard,
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(stats.radiusCard),
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onTap, child: content),
            ),
    );
  }
}

/// 卡片内的区块头：标题（+ 可选副标题）在左，操作区在右。
///
/// 统一标题字阶与右侧控件的对齐方式，避免每张卡各写一套 Row。
class StatsSectionHeader extends StatelessWidget {
  const StatsSectionHeader({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
  });

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: stats.titleSection),
              if (caption != null) ...[
                const SizedBox(height: 3),
                Text(
                  caption!,
                  style: stats.captionSection,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

/// 占比条：浅色底槽 + 主色进条，宽度带补间动画。
///
/// 不用 [LinearProgressIndicator]：它自带 Material 的不确定态与主题色逻辑，
/// 这里只需要一根纯色条和一个浅色槽。切换区间时是「长出来」而不是瞬间跳变。
class StatsRatioBar extends StatelessWidget {
  const StatsRatioBar({
    super.key,
    required this.ratio,
    required this.color,
    this.height = 5,
  });

  /// 0 ~ 1，超出会被夹住。
  final double ratio;

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: stats.fillMuted),
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
      ),
    );
  }
}

/// 胶囊切换器：浅色底槽 + 一块会滑过去的白色滑块。
///
/// 统计页卡头的收支切换、下钻面板的期段切换是同一种控件——就地换口径、
/// 不离开当前视图。两处各写一份，圆角、字号和动效很快就会漂开。
///
/// 滑块按下标等分轨道。四档及以上（日/周/月/年）走 [AppSegmentedControl]。
class StatsPillToggle extends StatelessWidget {
  const StatsPillToggle({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  }) : assert(labels.length >= 2, '至少两档才需要滑块');

  final List<String> labels;

  /// 选中项的下标。
  final int selected;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final trackRadius = stats.radiusInner;
    final last = labels.length - 1;
    return Container(
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: stats.fillMuted,
        borderRadius: BorderRadius.circular(trackRadius),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedAlign(
                duration: StatsTokens.durTap,
                curve: StatsTokens.curveEnter,
                alignment: Alignment(-1 + 2 * selected / last, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / labels.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: stats.surface,
                      borderRadius: BorderRadius.circular(
                        (trackRadius - 3).clamp(0.0, trackRadius),
                      ),
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
              ),
            ),
          ),
          // 两件事都由 IntrinsicWidth + Expanded 一起解决：
          //
          // 1. 轨道收成内容宽度。卡头里这颗控件嵌在 Row 中，拿到的是无界
          //    宽度，怎么排都按内容；一旦放进宽度有界的 Column（下钻面板），
          //    裸 Row 会被拉满整行，而滑块仍按等分定位，两者就错开。
          // 2. 各档等宽。滑块按份数切，而「本期 / 对照期」字数不同，
          //    按各自内容排同样会让滑块盖不准文字。
          IntrinsicWidth(
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: _PillChip(
                      label: labels[i],
                      active: selected == i,
                      onTap: () => onChanged(i),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: StatsTokens.durTap,
            curve: StatsTokens.curveEnter,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? stats.primary : stats.textMuted,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// 卡片内列表底部的「展开 / 收起」按钮：居中的小号文字按钮。
///
/// 分类构成与分类环比都要在列表底部折叠超出项。两处各写一份内联
/// TextButton 样式的话，字号、色值和内边距很快就会漂移成两套。
class StatsExpandToggle extends StatelessWidget {
  const StatsExpandToggle({
    super.key,
    required this.expanded,
    required this.collapsedLabel,
    required this.onChanged,
  });

  final bool expanded;

  /// 收起态的文案，例如「展开全部 12 个分类」。展开态固定显示「收起」。
  final String collapsedLabel;

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return Center(
      child: TextButton(
        onPressed: () => onChanged(!expanded),
        style: TextButton.styleFrom(
          foregroundColor: stats.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          expanded ? '收起' : collapsedLabel,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
