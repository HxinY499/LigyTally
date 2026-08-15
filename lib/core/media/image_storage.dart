import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StoredImage {
  const StoredImage({
    required this.imagePath,
    required this.thumbnailPath,
    required this.width,
    required this.height,
    required this.sizeBytes,
  });

  final String imagePath;
  final String thumbnailPath;
  final int width;
  final int height;
  final int sizeBytes;
}

class ImageStorage {
  ImageStorage() : _overrideRoot = null;

  /// 把根目录指到一个给定路径（测试用）。
  ///
  /// 生产路径走 `getApplicationSupportDirectory()`，那是个 platform channel，
  /// 在纯 Dart 单测里拿不到。备份/分类配置的往返测试必须能真读真写文件，
  /// 用 mock 替掉整个 ImageStorage 反而测不到路径拼接这类最容易错的部分。
  ImageStorage.atRoot(String root) : _overrideRoot = root;

  final String? _overrideRoot;

  /// support 目录的绝对路径缓存。
  ///
  /// 库里存的都是相对 support 目录的路径，渲染时要拼回绝对路径。
  /// 拿这个目录要走一次 platform channel，而分类图标会出现在账单列表、
  /// 统计列表这类高频重建的地方——每次重建都异步查一遍会让图标闪一下。
  /// 所以进程内缓存一份，配合 [warmUp] 让渲染路径变成同步的。
  static String? _supportPath;

  /// 预热 support 目录缓存，使 [resolveSyncPath] 可用。应用启动时调用一次。
  static Future<void> warmUp() async {
    _supportPath ??= (await getApplicationSupportDirectory()).path;
  }

  /// 同步拼出绝对路径。未预热时返回 null，调用方需回退到异步的 [resolve]。
  static String? resolveSyncPath(String relativePath) {
    final root = _supportPath;
    return root == null ? null : p.join(root, relativePath);
  }

  Future<String> _supportRoot() async {
    final override = _overrideRoot;
    if (override != null) return override;
    return _supportPath ??= (await getApplicationSupportDirectory()).path;
  }

  /// 所有相对路径的根。备份恢复要在它下面建暂存目录、整体换 media 目录。
  Future<String> supportRoot() => _supportRoot();

  Future<Directory> _root() async {
    final root = Directory(p.join(await _supportRoot(), kMediaDirName));
    await root.create(recursive: true);
    return root;
  }

  /// 落盘一张分类自定义图标图片，返回相对 support 目录的路径。
  ///
  /// 与账单图片分开放（`media/category_icons/`）而不是塞进某个 transactionId
  /// 目录：分类图标的生命周期跟着分类走，删账单时清理整个账单目录的逻辑
  /// 不该把它一起带走。压到 256px 是因为它最大只显示到 46px 的圆片，
  /// 存原图纯属浪费空间和备份体积。
  Future<String> storeCategoryIcon({
    required XFile source,
    required String iconId,
  }) async {
    final root = await _root();
    final directory = Directory(p.join(root.path, kCategoryIconDirName));
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, '$iconId.jpg'));
    final compressed = await FlutterImageCompress.compressAndGetFile(
      source.path,
      target.path,
      minWidth: 256,
      minHeight: 256,
      quality: 88,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (compressed == null) {
      throw StateError('图标图片处理失败');
    }
    return p.relative(target.path, from: await _supportRoot());
  }

  /// 直接用给定字节写入一张分类图标（导入 / 恢复时用，字节已是压好的）。
  Future<void> writeCategoryIcon({
    required String iconId,
    required List<int> bytes,
  }) async {
    final root = await _root();
    final directory = Directory(p.join(root.path, kCategoryIconDirName));
    await directory.create(recursive: true);
    await File(
      p.join(directory.path, '$iconId.jpg'),
    ).writeAsBytes(bytes, flush: true);
  }

  /// 删掉所有不在 [liveIconIds] 里的分类图标文件。
  ///
  /// 用「扫目录 + 对账」而不是「删分类时顺手删图」：需要删文件的路径有四条
  /// （删分类、删一级时连带子分类、把图片换回内置图标、编辑时换了另一张图），
  /// 每条都记得删迟早会漏一处，而漏掉的文件会一直躺在备份包里。
  /// 对账的成本是一次目录列举，这个目录通常只有几个文件。
  ///
  /// 参数是 id 而不是 iconKey：`custom:` 前缀的解析属于分类语义，
  /// 放在 `category_icons.dart`，存储层不该跟着懂它。
  Future<void> pruneCategoryIcons(Set<String> liveIconIds) async {
    final directory = Directory(
      p.join((await _root()).path, kCategoryIconDirName),
    );
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final id = p.basenameWithoutExtension(entity.path);
      if (!liveIconIds.contains(id)) await entity.delete();
    }
  }

  Future<StoredImage> store({
    required XFile source,
    required String transactionId,
    required String imageId,
  }) async {
    final root = await _root();
    final directory = Directory(p.join(root.path, transactionId));
    await directory.create(recursive: true);

    final imageFile = File(p.join(directory.path, '$imageId.jpg'));
    final thumbnailFile = File(p.join(directory.path, '${imageId}_thumb.jpg'));
    final compressed = await FlutterImageCompress.compressAndGetFile(
      source.path,
      imageFile.path,
      minWidth: 2048,
      minHeight: 2048,
      quality: 85,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (compressed == null) {
      throw StateError('图片压缩失败');
    }

    final thumbnail = await FlutterImageCompress.compressAndGetFile(
      compressed.path,
      thumbnailFile.path,
      minWidth: 320,
      minHeight: 320,
      quality: 76,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (thumbnail == null) {
      await imageFile.delete();
      throw StateError('缩略图生成失败');
    }

    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final support = await _supportRoot();
    final result = StoredImage(
      imagePath: p.relative(imageFile.path, from: support),
      thumbnailPath: p.relative(thumbnailFile.path, from: support),
      width: frame.image.width,
      height: frame.image.height,
      sizeBytes: await imageFile.length(),
    );
    frame.image.dispose();
    codec.dispose();
    return result;
  }

  Future<File> resolve(String relativePath) async {
    return File(p.join(await _supportRoot(), relativePath));
  }

  Future<void> deleteFile(String relativePath) async {
    final file = await resolve(relativePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteTransactionDirectory(String transactionId) async {
    final root = await _root();
    final directory = Directory(p.join(root.path, transactionId));
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

/// 账单图片与分类图标的根目录名（相对 support 目录）。
const kMediaDirName = 'media';

/// 分类图标目录名（相对 `media/`）。
const kCategoryIconDirName = 'category_icons';

/// 分类自定义图标的相对存储路径。
///
/// 路径由 iconId 纯计算得出、不查磁盘，所以库里只需要存 `custom:<iconId>`，
/// 不必额外开一列存路径 —— 少一列就少一次 drift 表结构迁移。
String categoryIconRelativePath(String iconId) =>
    p.join(kMediaDirName, kCategoryIconDirName, '$iconId.jpg');
