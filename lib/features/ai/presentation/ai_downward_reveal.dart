import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_motion.dart';

/// 从标题下面展开。
///
/// 高度用减速曲线，透明度更快到位，所以不是一块内容被线性拉开。
/// 列表贴在底部时，滚动位置和高度在同一帧里一起变，避免先顶上去再跳回来。
class AiDownwardReveal extends StatefulWidget {
  const AiDownwardReveal({super.key, required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  State<AiDownwardReveal> createState() => _AiDownwardRevealState();
}

class _AiDownwardRevealState extends State<AiDownwardReveal>
    with SingleTickerProviderStateMixin {
  static const _sizeCurve = Curves.easeOutCubic;
  static const _fadeCurve = Cubic(0.16, 1, 0.3, 1);

  late final AnimationController _controller;
  double _fullHeight = 0;
  double _shown = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: widget.open ? 1 : 0,
    )..addListener(_onTick);
    _shown = _fullHeight * _sizeCurve.transform(_controller.value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = context.motion(const Duration(milliseconds: 320));
    if (_controller.duration != duration) _controller.duration = duration;
  }

  @override
  void didUpdateWidget(AiDownwardReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (widget.open) {
      if (_fullHeight == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.open) _controller.forward();
        });
      } else {
        _controller.forward();
      }
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTick() {
    final shown = _fullHeight * _sizeCurve.transform(_controller.value);
    final delta = shown - _shown;
    _shown = shown;
    final position = Scrollable.maybeOf(context)?.position;
    if (position != null &&
        position.hasContentDimensions &&
        delta.abs() > 0.05) {
      final next = position.pixels + delta;
      if (next >= position.minScrollExtent) {
        position.correctPixels(next);
      }
    }
    setState(() {});
  }

  void _rememberHeight(double height) {
    _fullHeight = height;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open && _controller.value == 0) {
      return const SizedBox(width: double.infinity);
    }
    final t = _controller.value;
    return _RevealBox(
      heightFactor: _sizeCurve.transform(t),
      opacity: _fadeCurve.transform(t).clamp(0, 1),
      onMeasured: _rememberHeight,
      child: widget.child,
    );
  }
}

class _RevealBox extends SingleChildRenderObjectWidget {
  const _RevealBox({
    required this.heightFactor,
    required this.opacity,
    required this.onMeasured,
    required Widget child,
  }) : super(child: child);

  final double heightFactor;
  final double opacity;
  final void Function(double height) onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderReveal(
      heightFactor: heightFactor,
      opacity: opacity,
      onMeasured: onMeasured,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderReveal renderObject) {
    renderObject
      ..heightFactor = heightFactor
      ..opacity = opacity
      ..onMeasured = onMeasured;
  }
}

class _RenderReveal extends RenderProxyBox {
  _RenderReveal({
    required this._heightFactor,
    required this._opacity,
    required this._onMeasured,
  });

  double _heightFactor;
  double _opacity;
  void Function(double height) _onMeasured;

  set heightFactor(double value) {
    if (value == _heightFactor) return;
    _heightFactor = value;
    markNeedsLayout();
  }

  set opacity(double value) {
    if (value == _opacity) return;
    _opacity = value;
    markNeedsPaint();
  }

  set onMeasured(void Function(double height) value) => _onMeasured = value;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity),
      parentUsesSize: true,
    );
    _onMeasured(child.size.height);
    final revealed = child.size.height * _heightFactor.clamp(0, 1);
    size = constraints.constrain(Size(child.size.width, revealed));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_opacity <= 0 || size.height <= 0 || child == null) return;
    context.pushOpacity(offset, (_opacity * 255).round().clamp(0, 255), (
      ctx,
      off,
    ) {
      ctx.pushClipRect(needsCompositing, off, Offset.zero & size, super.paint);
    });
  }
}
