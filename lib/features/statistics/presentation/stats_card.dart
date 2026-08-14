import 'dart:async';

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

/// 入场动画包装：淡入 + 轻微上移。
///
/// [index] 用来做阶梯延迟，让卡片自上而下依次落位，
/// 比整屏同时淡入更有秩序感。延迟封顶，避免卡片多时最后一张迟迟不出现。
///
/// [skip] 为 true 时直接停在终态。明细页是虚拟列表，滑出再滑回会重建
/// 子项；父级用它记住「这一格已经播过」，避免同一张卡反复入场。
class StatsEntrance extends StatefulWidget {
  const StatsEntrance({
    super.key,
    required this.index,
    required this.child,
    this.skip = false,
  });

  final int index;
  final Widget child;
  final bool skip;

  @override
  State<StatsEntrance> createState() => _StatsEntranceState();
}

class _StatsEntranceState extends State<StatsEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  /// 阶梯延迟用的定时器。必须持有引用并在 dispose 时取消——
  /// 裸用 `Future.delayed` 的话，widget 提前销毁后定时器仍挂在事件循环上，
  /// 在 widget 测试里会直接触发「A Timer is still pending」断言。
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: StatsTokens.durEnter,
      vsync: this,
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: StatsTokens.curveEnter,
    );
    _fade = curve;
    _slide = Tween(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(curve);

    if (widget.skip) {
      _controller.value = 1;
      return;
    }

    // 阶梯延迟：每张卡晚 60ms，最多累到 240ms。
    final delay = Duration(milliseconds: 60 * widget.index.clamp(0, 4));
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _delay = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
