import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_theme.dart';

/// 应用统一开关：果冻开关。
///
/// 圆点滑向另一端时，前沿先冲到终点、后沿按弹簧追上：途中被拉成胶囊，
/// 后沿越过终点时被压扁，再回弹成正圆。轨道底色同步渐变到主题色。
///
/// 布局尺寸就是轨道本身（[_kTrackWidth] × [_kTrackHeight]），没有隐形留白，
/// 行尾直接放即可与 chevron 右缘对齐。业务页一律用 [AppSwitch]。
class AppSwitch extends StatefulWidget {
  const AppSwitch({super.key, required this.value, required this.onChange});

  final bool value;
  final ValueChanged<bool> onChange;

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

const double _kTrackWidth = 51;
const double _kTrackHeight = 31;
const double _kInset = 2;
const double _kThumb = _kTrackHeight - _kInset * 2;
const double _kThumbLeft = _kInset;
const double _kThumbRight = _kTrackWidth - _kInset - _kThumb;
const Duration _kDuration = Duration(milliseconds: 350);

/// 前沿：前 35% 时长内减速冲到终点，之后贴住轨道端不动。
const Curve _kLeadCurve = Interval(0, 0.35, curve: Curves.easeOutCubic);

/// 后沿：欠阻尼弹簧，约 65% 时长处越过终点 15% 后回落。
const Curve _kTrailCurve = _SpringCurve(damping: 0.5, peak: 0.65);

/// 欠阻尼弹簧的阶跃响应，`peak` 是第一次越过终点的时刻（占总时长比例）。
///
/// 弹簧在有限时长内不会精确停在 1，末尾按 t³ 把残差抹掉，
/// 否则最后一帧圆点会跳一下。
class _SpringCurve extends Curve {
  const _SpringCurve({required this.damping, required this.peak});

  final double damping;
  final double peak;

  double _raw(double t) {
    final wd = math.pi / peak;
    final decay = damping * wd / math.sqrt(1 - damping * damping);
    return 1 -
        math.exp(-decay * t) *
            (math.cos(wd * t) + decay / wd * math.sin(wd * t));
  }

  @override
  double transformInternal(double t) => _raw(t) - (_raw(1) - 1) * t * t * t;
}

class _AppSwitchState extends State<AppSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );

  /// 本段动画起点。中途再次切换时从当前画面接着走，不跳回端点。
  late double _fromLeft = _restLeft(widget.value);
  late double _fromRight = _fromLeft + _kThumb;
  late double _fromColor = widget.value ? 1 : 0;

  static double _restLeft(bool value) => value ? _kThumbRight : _kThumbLeft;

  @override
  void didUpdateWidget(AppSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    // 必须按旧目标求：widget 已换成新值，按新方向会算出一个从未画过的位置。
    final current = _frameToward(oldWidget.value);
    _fromLeft = current.left;
    _fromRight = current.right;
    _fromColor = current.color;
    _controller
      ..duration = context.motion(_kDuration)
      ..forward(from: 0);
  }

  /// 本段动画朝 [value] 走到 `_controller.value` 时的圆点左右沿与底色进度。
  ({double left, double right, double color}) _frameToward(bool value) {
    final t = _controller.value;
    final toLeft = _restLeft(value);
    final movingRight = toLeft > _fromLeft;
    final leftT = (movingRight ? _kTrailCurve : _kLeadCurve).transform(t);
    final rightT = (movingRight ? _kLeadCurve : _kTrailCurve).transform(t);
    final toColor = value ? 1.0 : 0.0;
    return (
      left: _fromLeft + (toLeft - _fromLeft) * leftT,
      right: _fromRight + (toLeft + _kThumb - _fromRight) * rightT,
      color: _fromColor + (toColor - _fromColor) * Curves.easeOut.transform(t),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trackOff = colors.primarySoft;
    final trackOn = colors.primary;
    // 不取 forui 的 background：壁纸模式下它是透明的，圆点会消失。
    final thumb = colors.brightness == Brightness.light
        ? colors.canvasBase
        : colors.ink;

    return Semantics(
      container: true,
      toggled: widget.value,
      enabled: true,
      onTap: () => widget.onChange(!widget.value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => widget.onChange(!widget.value),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final frame = _frameToward(widget.value);
            return CustomPaint(
              size: const Size(_kTrackWidth, _kTrackHeight),
              painter: _JellyPainter(
                left: frame.left,
                right: frame.right,
                track: Color.lerp(trackOff, trackOn, frame.color)!,
                thumb: thumb,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _JellyPainter extends CustomPainter {
  const _JellyPainter({
    required this.left,
    required this.right,
    required this.track,
    required this.thumb,
  });

  final double left;
  final double right;
  final Color track;
  final Color thumb;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.height / 2),
      ),
      Paint()..color = track,
    );

    // 体积近似守恒：拉长时略变扁，压扁时略变高，上限不碰轨道边。
    final width = right - left;
    final height =
        (width >= _kThumb
                ? _kThumb - (width - _kThumb) * 0.15
                : _kThumb + (_kThumb - width) * 0.5)
            .clamp(_kThumb - 4, _kTrackHeight - 1);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, (size.height - height) / 2, width, height),
      Radius.circular(math.min(width, height) / 2),
    );
    canvas.drawRRect(
      body.shift(const Offset(0, 1.5)),
      Paint()
        ..color = const Color(0x24000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawRRect(body, Paint()..color = thumb);
  }

  @override
  bool shouldRepaint(_JellyPainter old) =>
      old.left != left ||
      old.right != right ||
      old.track != track ||
      old.thumb != thumb;
}
