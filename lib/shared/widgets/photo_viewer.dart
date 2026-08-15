import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 全屏图片查看器：黑底、捏合缩放、双击放大、下滑关闭、多图左右翻页。
///
/// 没有引第三方图片浏览库：需要的能力 [InteractiveViewer] 已经给全了，
/// 缺的是几条粘合逻辑——双击缩放、放大后不翻页，以及下面两条手势仲裁。
///
/// **手势为什么绕开 GestureDetector 走 [Listener]**
///
/// [PageView] 的水平拖动识别器和 [InteractiveViewer] 的缩放识别器在同一个
/// 竞技场里。两指落下时通常是水平分开的，水平拖动先够到阈值、先胜出，捏合
/// 就再也收不到事件——表现为「只能双击放大，捏不动」。而「放大后才关翻页」
/// 解不开这个结：得先放大成功才关，可不关就放不大。
///
/// [Listener] 拿的是原始指针事件，不进竞技场、抢不走也被抢不掉。于是：
/// 第二根手指一按下就把翻页 physics 换成不可滚动，缩放独占；未放大时的单指
/// 垂直拖动也在这里量，不必和翻页争方向。
///
/// [images] 的顺序即翻页顺序，[initialIndex] 是首屏那张。传原图而不是缩略图
/// ——放大到 2.5 倍还糊着就失去了全屏查看的意义。
Future<void> showPhotoViewer(
  BuildContext context, {
  required List<ImageProvider> images,
  int initialIndex = 0,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      // 不透明会让底下的图片面板在转场期间就被整块丢掉，淡入时黑屏是突然砸下来的；
      // 保持透明，黑底随动画一起浮上来，观感上才像从面板里「放大」出来。
      opaque: false,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, _) => FadeTransition(
        opacity: animation,
        child: _PhotoViewer(images: images, initialIndex: initialIndex),
      ),
    ),
  );
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.images, required this.initialIndex});

  final List<ImageProvider> images;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late int _index;

  /// 当前页是否处于放大状态。翻页手势与页码条都看它。
  bool _zoomed = false;

  /// 当前按在屏幕上的手指数。到 2 就把翻页让给缩放。
  int _pointers = 0;

  /// 下滑关闭的累计位移。正数向下、负数向上，两个方向都能关。
  double _drag = 0;

  /// 本次触摸是否已判定为「垂直拖动」。
  ///
  /// 只在第一次移动时定一次方向：不锁的话斜着滑会边翻页边下滑，两种反馈叠在
  /// 一起像是漏了帧。判定为水平就整轮不再管，交给 [PageView]。
  bool? _draggingVertically;

  late final AnimationController _settle;
  Animation<double>? _settleTween;

  /// 松手后关闭的位移阈值。比常见的 100 略大一点：这个查看器的单击也是关闭，
  /// 手指按下后不小心带出的十几像素不该被当成想退出。
  static const double _kDismissDistance = 130;

  /// 位移到多少算「完全退出」，用来把缩放和背景透明度归一化。
  static const double _kDragRange = 320;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
    _settle =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          final value = _settleTween?.value;
          // 回弹途中可能已经因为别的原因退出了这一页。
          if (value != null && mounted) setState(() => _drag = value);
        });
  }

  @override
  void dispose() {
    _settle.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// 下滑进度 0~1，驱动图片缩小与黑底渐隐。
  double get _dragProgress => (_drag.abs() / _kDragRange).clamp(0.0, 1.0);

  bool get _canDragToDismiss => !_zoomed && _pointers <= 1;

  void _onPointerDown(PointerDownEvent event) {
    setState(() => _pointers++);
    // 第二根手指落下：这轮不再是下滑，已经拖出的位移弹回去，
    // 否则捏合放大时图片还歪在半路上。
    if (_pointers >= 2) {
      _draggingVertically = false;
      if (_drag != 0) _settleBack();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_canDragToDismiss) return;
    if (_draggingVertically == false) return;
    if (_draggingVertically == null) {
      final delta = event.delta;
      // 位移太小时方向没有意义，等下一帧再判。
      if (delta.distance < 0.5) return;
      _draggingVertically = delta.dy.abs() > delta.dx.abs();
      if (_draggingVertically == false) return;
    }
    _settle.stop();
    setState(() => _drag += event.delta.dy);
  }

  void _onPointerUp(PointerEvent event) {
    final wasVertical = _draggingVertically ?? false;
    setState(() {
      _pointers = _pointers > 0 ? _pointers - 1 : 0;
      // 手指全抬起才解除方向锁：捏合后先抬一根手指，剩下那根不该立刻变成下滑。
      if (_pointers == 0) _draggingVertically = null;
    });
    if (!wasVertical) return;
    if (_drag.abs() >= _kDismissDistance) {
      Navigator.of(context).maybePop();
      return;
    }
    _settleBack();
  }

  void _settleBack() {
    _settleTween = Tween<double>(begin: _drag, end: 0).animate(
      CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic),
    );
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.images.length;
    final topInset = MediaQuery.paddingOf(context).top;
    final progress = _dragProgress;
    // 跟手时图片缩到 0.85、黑底退到两成：路由本身是透明的，底下的页面透出来
    // 才有「往回收」的感觉，全黑到底就只是图片在动。
    final scale = 1 - progress * 0.15;
    final chromeOpacity = 1 - progress.clamp(0.0, 1.0);
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 1 - progress * 0.8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform.translate(
              offset: Offset(0, _drag),
              child: Transform.scale(
                scale: scale,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: count,
                  // 放大后横向拖动应该是平移图片而不是翻页；双指落下时也要让位，
                  // 否则水平拖动会先赢走竞技场，捏合根本收不到事件。
                  physics: _zoomed || _pointers >= 2
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, i) => _ZoomablePhoto(
                    image: widget.images[i],
                    active: i == _index,
                    // 未放大时不让它接管单指拖动，那是下滑关闭要用的。
                    panEnabled: _zoomed,
                    // 离屏页复位时也会回调，不加这道判断会把当前页的放大状态清掉。
                    onZoomChanged: (zoomed) {
                      if (i != _index || zoomed == _zoomed) return;
                      setState(() => _zoomed = zoomed);
                    },
                    onDismiss: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
            Positioned(
              top: topInset + 4,
              left: 4,
              child: Opacity(
                opacity: chromeOpacity,
                child: _GlassButton(
                  icon: FLucideIcons.x,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
            if (count > 1)
              Positioned(
                top: topInset + 4,
                right: 0,
                left: 0,
                child: Center(
                  child: Opacity(
                    opacity: chromeOpacity,
                    child: _PageBadge(label: '${_index + 1} / $count'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 单张可缩放的照片。
///
/// 缩放状态由自己持有的 [TransformationController] 掌管，双击的那段动画也在
/// 这里驱动——[InteractiveViewer] 只认最终矩阵，不管过渡过程。
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    required this.image,
    required this.active,
    required this.panEnabled,
    required this.onZoomChanged,
    required this.onDismiss,
  });

  final ImageProvider image;

  /// 是否是当前页。翻走时要复位，且不该再上报缩放状态。
  final bool active;

  /// 是否允许单指平移图片。
  ///
  /// 未放大时必须关掉：[InteractiveViewer] 的识别器会把单指拖动一并吃下，
  /// 那样下滑关闭就永远量不到位移。放大后它才是平移图片的正主。
  final bool panEnabled;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onDismiss;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  late final AnimationController _animation;
  Animation<Matrix4>? _zoomTween;

  /// 双击后的放大倍数。2.5 是「小票上的字能认出来」与「还看得出这是哪张图」
  /// 之间的折中；捏合仍可继续放到 [_kMaxScale]。
  static const double _kDoubleTapScale = 2.5;
  static const double _kMaxScale = 5;

  /// 判定「已放大」的阈值。缩放回落时浮点数很难精确等于 1，
  /// 直接比 `> 1` 会让翻页手势在复位后仍被锁着。
  static const double _kZoomedEpsilon = 1.01;

  /// 双击落点（相对视口）。放大要以它为锚，手指底下的内容才不会跑掉。
  Offset _anchor = Offset.zero;

  bool get _isZoomed => _transform.value.getMaxScaleOnAxis() > _kZoomedEpsilon;

  @override
  void initState() {
    super.initState();
    _animation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final value = _zoomTween?.value;
          if (value != null) _transform.value = value;
        });
    _transform.addListener(_reportZoom);
  }

  @override
  void didUpdateWidget(covariant _ZoomablePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 翻走的那一页复位：原生相册里每张都是从整图开始看的，
    // 翻回来还停在上次放大的位置会让人以为翻错了。
    if (oldWidget.active && !widget.active) {
      _animation.stop();
      _transform.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _transform.removeListener(_reportZoom);
    _animation.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _reportZoom() => widget.onZoomChanged(_isZoomed);

  void _toggleZoom() {
    final Matrix4 end;
    if (_isZoomed) {
      end = Matrix4.identity();
    } else {
      const scale = _kDoubleTapScale;
      // 先按锚点反向平移再缩放：变换后锚点仍落在原处。
      end = Matrix4.identity()
        ..translateByDouble(
          -_anchor.dx * (scale - 1),
          -_anchor.dy * (scale - 1),
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1);
    }
    _zoomTween = Matrix4Tween(
      begin: _transform.value,
      end: end,
    ).animate(CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic));
    _animation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 放大状态下的单击不退出：正看着细节时手一抖就被弹回去很恼火，
      // 此时要退出走左上角的关闭按钮或系统返回。
      //
      // 判断放在回调里而不是 `onTap: _isZoomed ? null : ...`：缩放只改
      // TransformationController，不会触发本组件重建，写在参数位上取到的
      // 会是上一次 build 时的旧状态。
      onTap: () {
        if (_isZoomed) return;
        widget.onDismiss();
      },
      onDoubleTapDown: (details) => _anchor = details.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: _kMaxScale,
        panEnabled: widget.panEnabled,
        child: Center(
          child: Image(image: widget.image, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// 浮在照片上的半透明圆钮。照片明暗不可控，纯白图标压在浅色照片上会看不见，
/// 垫一层半透明黑底才在两种极端下都读得出来。
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          color: Color(0x66000000),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}

/// 「2 / 3」页码胶囊。
class _PageBadge extends StatelessWidget {
  const _PageBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
