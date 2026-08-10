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
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StatsTokens.surface,
        borderRadius: BorderRadius.circular(StatsTokens.radiusCard),
        boxShadow: StatsTokens.shadowCard,
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(StatsTokens.radiusCard),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: StatsTokens.titleSection),
              if (caption != null) ...[
                const SizedBox(height: 3),
                Text(
                  caption!,
                  style: StatsTokens.captionSection,
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

/// 入场动画包装：淡入 + 轻微上移。
///
/// [index] 用来做阶梯延迟，让卡片自上而下依次落位，
/// 比整屏同时淡入更有秩序感。延迟封顶，避免卡片多时最后一张迟迟不出现。
class StatsEntrance extends StatefulWidget {
  const StatsEntrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

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
