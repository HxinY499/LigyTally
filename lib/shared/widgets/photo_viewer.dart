import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 全屏图片查看器：黑底、捏合缩放、双击放大、多图左右翻页。
///
/// 没有引第三方图片浏览库：需要的能力 [InteractiveViewer] 已经给全了，
/// 缺的只是「双击缩放」和「放大后不翻页」两条粘合逻辑，为这点东西多背一个
/// 依赖不划算。
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

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pageController;
  late int _index;

  /// 当前页是否处于放大状态。翻页手势与页码条都看它。
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.images.length;
    final topInset = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: count,
            // 放大后横向拖动应该是平移图片而不是翻页。两个识别器同时在场时
            // 谁赢取决于滑动方向，会出现「想平移却跳到下一张」，索性放大期间
            // 直接把翻页关掉。
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, i) => _ZoomablePhoto(
              image: widget.images[i],
              active: i == _index,
              // 离屏页复位时也会回调，不加这道判断会把当前页的放大状态清掉。
              onZoomChanged: (zoomed) {
                if (i != _index || zoomed == _zoomed) return;
                setState(() => _zoomed = zoomed);
              },
              onDismiss: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            top: topInset + 4,
            left: 4,
            child: _GlassButton(
              icon: FLucideIcons.x,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          if (count > 1)
            Positioned(
              top: topInset + 4,
              right: 0,
              left: 0,
              child: Center(child: _PageBadge(label: '${_index + 1} / $count')),
            ),
        ],
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
    required this.onZoomChanged,
    required this.onDismiss,
  });

  final ImageProvider image;

  /// 是否是当前页。翻走时要复位，且不该再上报缩放状态。
  final bool active;
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

  bool get _isZoomed =>
      _transform.value.getMaxScaleOnAxis() > _kZoomedEpsilon;

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
    _zoomTween = Matrix4Tween(begin: _transform.value, end: end).animate(
      CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic),
    );
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
        child: Center(child: Image(image: widget.image, fit: BoxFit.contain)),
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
