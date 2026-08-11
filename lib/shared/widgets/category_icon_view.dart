import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/media/image_storage.dart';
import '../../core/utils/category_icons.dart';

/// 分类图标的唯一渲染入口：内置图标与用户上传的图片走同一个组件。
///
/// ## 为什么必须收口成一个组件
///
/// 分类图标出现在九个地方（账单列表、记账页的列表/网格两种选择器、
/// 统计页排行、分类管理页的卡头与子格、编辑面板的预览与选择器格子）。
/// 如果在每处写 `isCustom ? Image.file(...) : Icon(...)`，
/// 加一种图标来源就要改九处，必然漏。
///
/// ## [size] 与 [imageSize]：字形和图片不该一样大
///
/// 内置图标是线性字形，四周天生有留白，所以放在 40px 的圆底里只画 21px
/// 才显得端正。图片没有这层留白——同样按 21px 画，就成了「大圆底中央一颗
/// 小圆点」，看着像加载失败。所以凡是外面套了色底容器的调用点，都要把
/// 容器边长传给 [imageSize]，让图片铺满、由容器本身来定型。
///
/// ## 圆形裁剪
///
/// 上传的照片是矩形，统一裁成圆：分类图标的容器多数本就是圆片，
/// 而在无容器的裸图标场景（记账页网格），一张圆形小图看起来像「贴纸」，
/// 比方形照片更接近图标语义，也不会破坏原有的格子几何。
///
/// ## 为什么不用 [LocalImage]
///
/// 那个组件每次 build 都 `FutureBuilder` 去查 support 目录，
/// 在账单列表这种一屏几十行、滚动时反复重建的场景会闪一下空白。
/// 分类图标改走 [ImageStorage.resolveSyncPath] 的同步缓存路径，
/// 只在缓存未预热时（理论上只有极早期启动）才回退到异步。
class CategoryIconView extends StatelessWidget {
  const CategoryIconView({
    super.key,
    required this.iconKey,
    required this.size,
    required this.color,
    this.imageSize,
  });

  final String iconKey;

  /// 内置图标的字形边长。
  final double size;

  /// 自定义图片的边长。默认跟随 [size]。
  ///
  /// 外面套了色底容器时**必须**传容器的边长，否则图片会缩成中间一小点。
  final double? imageSize;

  /// 内置图标的着色。图片不染色——用户上传的是彩色照片，
  /// 染色会把它压成一块纯色，等于把图片弄没了。
  final Color color;

  @override
  Widget build(BuildContext context) {
    final id = customCategoryIconId(iconKey);
    if (id == null || !isValidCustomIconId(id)) {
      return Icon(categoryIcon(iconKey), size: size, color: color);
    }
    return _CustomIcon(
      iconId: id,
      size: imageSize ?? size,
      fallbackSize: size,
      fallbackColor: color,
    );
  }
}

class _CustomIcon extends StatelessWidget {
  const _CustomIcon({
    required this.iconId,
    required this.size,
    required this.fallbackSize,
    required this.fallbackColor,
  });

  final String iconId;
  final double size;
  final double fallbackSize;
  final Color fallbackColor;

  /// 图片文件不在了（备份缺图、换机后没跟过来、用户清了数据）时的兜底。
  /// 按字形尺寸画，才不会在容器里撑成一大块。
  Widget _fallback() =>
      Icon(categoryIcon('other'), size: fallbackSize, color: fallbackColor);

  Widget _image(String path) => ClipOval(
    child: Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.cover,
      // 缓存到实际显示尺寸：一张 256px 的源图在 24px 的格子里解码成全尺寸
      // 会白占十几倍内存，滚动长列表时很容易触发 GC 抖动。
      // 乘 3 是给高 DPR 屏留余量（本机 density 480 即 dpr 3）。
      cacheWidth: (size * 3).round(),
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => _fallback(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final relative = categoryIconRelativePath(iconId);
    final cached = ImageStorage.resolveSyncPath(relative);
    if (cached != null) return _image(cached);
    // 只有 support 目录还没预热时会走到这里。
    return FutureBuilder<File>(
      future: ImageStorage().resolve(relative),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return SizedBox.square(dimension: size);
        return _image(file.path);
      },
    );
  }
}
