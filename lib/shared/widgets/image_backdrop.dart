import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 把一张账单图片化成版面的背板。
///
/// 不直接拿照片当墙纸：先高斯模糊，再用一道透明度渐变把它从 [begin] 一侧化开、
/// 到 [end] 一侧完全隐入底色。照片只留下色调与光影，压在上面的正文照样读得
/// 清。记账页铺满整页、明细列表铺单行，区别只在渐变方向与浓度。
class ImageBackdrop extends StatelessWidget {
  const ImageBackdrop({
    super.key,
    required this.image,
    required this.blurSigma,
    this.maxOpacity = 0.4,
    this.begin = Alignment.topCenter,
    this.end = Alignment.bottomCenter,
    this.stops = const [0, 0.34, 0.66],
    this.alignment = Alignment.topCenter,
  });

  /// 为 null 时什么都不画，露出底下的页面底色。
  final ImageProvider? image;

  final double blurSigma;

  /// [begin] 一侧的浓度。0.4 是正文压在最坏那张照片上仍能勉强达到 WCAG AA
  /// 的上限，再浓就得让正文改色了。
  ///
  /// 「最坏」在两套皮肤下是反的：浅色皮肤怕深色照片压住深色正文，深色皮肤
  /// 怕亮色照片压住浅色正文。40% 叠加后两边的对比度落在同一档，所以这个
  /// 上限不需要按皮肤分开取值。
  final double maxOpacity;

  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  /// 三段渐变的位置：满浓度 → 半浓度 → 全透明。
  final List<double> stops;

  /// 图片在背板框里的对齐方式。
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    return IgnorePointer(
      // 首帧与换图都走淡入：编辑页异步读出图片、多图轮播都不该是硬切。
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 460),
        // 默认 layoutBuilder 给的是松约束，图会缩成固有大小杵在正中。
        // 背板必须吃满可用空间，渐变的起止才对得上版面。
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: image == null
            ? const SizedBox.shrink()
            // 模糊会溢出边界糊到邻居身上——在列表里就是糊到上下两行去。
            : ClipRect(
                key: ValueKey(image),
                // 宿主每次重建都重跑一遍模糊太贵，隔离出去。
                child: RepaintBoundary(
                  child: ShaderMask(
                    // dstIn 只取 src 的 alpha，色彩通道整条丢弃：下面这三档白
                    // 是纯粹的遮罩载体，不是往图上盖一层白。图片被抹到透明后
                    // 露出的是它下面那层页面底色，因此深浅两套皮肤都自动成立，
                    // 不要把它改成 canvas —— 换成任何颜色渲染结果都一模一样。
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => LinearGradient(
                      begin: begin,
                      end: end,
                      colors: [
                        Colors.white.withValues(alpha: maxOpacity),
                        Colors.white.withValues(alpha: maxOpacity * 0.5),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: stops,
                    ).createShader(rect),
                    child: ImageFiltered(
                      enabled: blurSigma > 0,
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: blurSigma,
                        sigmaY: blurSigma,
                      ),
                      child: Image(
                        image: image,
                        fit: BoxFit.cover,
                        alignment: alignment,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
