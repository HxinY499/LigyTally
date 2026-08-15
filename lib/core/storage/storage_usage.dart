import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../media/image_storage.dart';
import '../update/update_service.dart';
import '../utils/category_icons.dart';

/// 恢复备份时用来暂存旧 media 的目录名（相对 support 目录）。
///
/// 正常路径下它在恢复结束前就被删掉了；进程恰好在换目录期间被杀才会留下。
/// 留下的是一整份旧图片副本，用户在应用里看不见也删不掉，所以这里要认得它。
const kMediaBeforeRestoreDirName = '.media_before_restore';

/// 孤儿文件的最小年龄。
///
/// `media/` 下「库里查不到」的文件不一定是垃圾：存图是先落盘、后写库，
/// 中间那一小段时间里文件就是查不到的。只把放了足够久的算成孤儿，
/// 避免把用户正在保存的照片当垃圾清掉。
const kOrphanMinAge = Duration(minutes: 10);

/// 应用私有数据的磁盘占用，按「能不能删」分成三类。
///
/// - 账本本体（[imageBytes] / [categoryIconBytes] / [databaseBytes]）：只能靠
///   删账单或删图腾出来。
/// - 缓存（[cacheBytes]）：本应用写进临时目录、已经完成使命的产物。
/// - 孤儿文件（[orphanBytes]）：本该跟着账单走却掉队的文件。
///
/// 缓存和孤儿分开列而不是合成一个「垃圾」：缓存是本来就打算丢的临时产物，
/// 孤儿是照片副本。混成一项，用户看到「缓存 200 MB」会不敢点。
class StorageUsage {
  const StorageUsage({
    required this.imageBytes,
    required this.imageCount,
    required this.categoryIconBytes,
    required this.databaseBytes,
    required this.cacheBytes,
    required this.orphanBytes,
    required this.orphanFileCount,
  });

  /// 库里有记录的账单原图与缩略图。
  final int imageBytes;

  /// 账单原图张数（不含缩略图）。
  final int imageCount;

  /// 仍被分类引用的自定义图标。
  final int categoryIconBytes;

  /// SQLite 主库 + WAL / SHM / journal。
  final int databaseBytes;

  /// 临时目录下本应用产出的可删文件：更新包、导出的备份 / CSV / 分类配置。
  final int cacheBytes;

  /// `media/` 下库里查不到的文件，以及恢复中断残留的旧 media 副本。
  final int orphanBytes;

  final int orphanFileCount;

  int get mediaBytes => imageBytes + categoryIconBytes;

  /// 账本本体：删缓存和孤儿之后仍会占着的部分。
  int get ledgerBytes => mediaBytes + databaseBytes;

  /// 一键就能腾出来的部分。
  int get reclaimableBytes => cacheBytes + orphanBytes;

  int get totalBytes => ledgerBytes + reclaimableBytes;

  /// 单张账单原图的平均大小；没有图时为 0。
  ///
  /// 用原图字节数而不是 [imageBytes]：后者含缩略图，除出来的数字和用户在
  /// 图库里看到的单张大小对不上。
  int averageImageBytes(int originalBytes) =>
      imageCount == 0 ? 0 : originalBytes ~/ imageCount;
}

class StorageUsageService {
  StorageUsageService(
    this.database,
    this.imageStorage, {
    Future<Directory> Function()? cacheRoot,
  }) : _cacheRoot = cacheRoot ?? getTemporaryDirectory;

  final AppDatabase database;
  final ImageStorage imageStorage;
  final Future<Directory> Function() _cacheRoot;

  Future<StorageUsage> measure() async {
    final support = await imageStorage.supportRoot();
    final live = await _livePaths();
    final media = Directory(p.join(support, kMediaDirName));

    var imageBytes = 0;
    var iconBytes = 0;
    var orphanBytes = 0;
    var orphanCount = 0;
    await for (final file in _files(media)) {
      final relative = p.relative(file.path, from: support);
      final bytes = await _fileBytes(file);
      if (live.images.contains(relative)) {
        imageBytes += bytes;
      } else if (live.icons.contains(relative)) {
        iconBytes += bytes;
      } else if (await _isOldEnough(file)) {
        orphanBytes += bytes;
        orphanCount++;
      }
    }

    final leftover = Directory(p.join(support, kMediaBeforeRestoreDirName));
    await for (final file in _files(leftover)) {
      orphanBytes += await _fileBytes(file);
      orphanCount++;
    }

    var cacheBytes = 0;
    await for (final file in _cacheFiles()) {
      cacheBytes += await _fileBytes(file);
    }

    return StorageUsage(
      imageBytes: imageBytes,
      imageCount: live.imageCount,
      categoryIconBytes: iconBytes,
      databaseBytes: await _databaseBytes(),
      cacheBytes: cacheBytes,
      orphanBytes: orphanBytes,
      orphanFileCount: orphanCount,
    );
  }

  /// 删掉临时目录里本应用产出的文件，返回释放的字节数。
  ///
  /// 不碰数据库、账单图和分类图标——那些不在临时目录里。
  Future<int> clearCache() async {
    var freed = 0;
    await for (final file in _cacheFiles()) {
      freed += await _deleteFile(file);
    }
    return freed;
  }

  /// 删掉 `media/` 下库里查不到的文件和恢复残留，返回释放的字节数。
  ///
  /// 每次都现查一遍库，不复用 [measure] 的结果：统计和点「清理」之间用户
  /// 可能刚记了一笔带图的账，拿旧集合去删会把新图当孤儿。
  Future<int> clearOrphans() async {
    final support = await imageStorage.supportRoot();
    final live = await _livePaths();
    final media = Directory(p.join(support, kMediaDirName));

    var freed = 0;
    await for (final file in _files(media)) {
      final relative = p.relative(file.path, from: support);
      if (live.images.contains(relative) || live.icons.contains(relative)) {
        continue;
      }
      if (!await _isOldEnough(file)) continue;
      freed += await _deleteFile(file);
    }

    final leftover = Directory(p.join(support, kMediaBeforeRestoreDirName));
    if (await leftover.exists()) {
      await for (final file in _files(leftover)) {
        freed += await _fileBytes(file);
      }
      try {
        await leftover.delete(recursive: true);
      } on FileSystemException {
        freed = 0;
      }
    }

    await _pruneEmptyDirectories(media);
    return freed;
  }

  /// 对数据库做 VACUUM，返回文件缩小的字节数。
  ///
  /// 删账单和删图只是把页标记为空闲，文件不会变小。没有这一步，用户删完
  /// 几百张图会发现「数据」那一行纹丝不动，以为没删掉。
  Future<int> compactDatabase() async {
    final path = await database.mainDatabaseFilePath();
    if (path == null) return 0;
    final before = await _databaseBytes();
    await database.compact();
    final after = await _databaseBytes();
    return after < before ? before - after : 0;
  }

  /// 库里仍在引用的相对路径。
  Future<({Set<String> images, Set<String> icons, int imageCount})>
  _livePaths() async {
    final images = await database.exportImages();
    final categories = await database.exportCategories();
    return (
      images: {
        for (final image in images) ...[image.imagePath, image.thumbnailPath],
      },
      icons: {
        for (final id in customIconIdsOf(categories.map((row) => row.iconKey)))
          categoryIconRelativePath(id),
      },
      imageCount: images.length,
    );
  }

  Future<int> _databaseBytes() async {
    final path = await database.mainDatabaseFilePath();
    if (path == null) return 0;
    var total = 0;
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      total += await _fileBytes(File('$path$suffix'));
    }
    return total;
  }

  /// 临时目录里本应用产出的文件。
  ///
  /// 只扫根目录和 `updates/`，且只认自己写过的命名——临时目录里还有
  /// image_picker 之类插件的中间文件，无差别清会在用户正选图时踩到。
  Stream<File> _cacheFiles() async* {
    final Directory root;
    try {
      root = await _cacheRoot();
    } on MissingPluginException {
      return;
    }
    for (final directory in [
      root,
      Directory(p.join(root.path, kUpdateCacheDirName)),
    ]) {
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && isAppCacheFileName(p.basename(entity.path))) {
          yield entity;
        }
      }
    }
  }

  Stream<File> _files(Directory directory) async* {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) yield entity;
    }
  }

  Future<bool> _isOldEnough(File file) async {
    try {
      final modified = await file.lastModified();
      return DateTime.now().difference(modified) >= kOrphanMinAge;
    } on FileSystemException {
      return false;
    }
  }

  Future<int> _deleteFile(File file) async {
    try {
      final bytes = await file.length();
      await file.delete();
      return bytes;
    } on FileSystemException {
      return 0;
    }
  }

  /// 清掉 `media/` 下已经空掉的账单目录。
  ///
  /// 删完图片如果不收目录，一个用过图片的账本会留下几百个空文件夹；它们不占
  /// 字节，但会让下一次扫描越来越慢。
  Future<void> _pruneEmptyDirectories(Directory root) async {
    if (!await root.exists()) return;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      if (p.basename(entity.path) == kCategoryIconDirName) continue;
      if (await entity.list().isEmpty) {
        try {
          await entity.delete();
        } on FileSystemException {
          // 并发写入时目录可能又有了文件，跳过即可。
        }
      }
    }
  }
}

/// 临时目录里这个文件名是不是本应用产出的、可安全删除的缓存。
///
/// 命名规则散在四个 service 里（更新包、备份、CSV、分类配置），收在这里
/// 判断，免得以后新增一种导出就多一类清不掉的文件。
bool isAppCacheFileName(String name) {
  if (name.endsWith('.apk') || name.endsWith('.part')) return true;
  if (name.startsWith('ligy-tally-')) {
    return name.endsWith('.ligytally') || name.endsWith('.csv');
  }
  return name.startsWith('ligy-categories-') && name.endsWith('.json');
}

/// 把字节数收成短标签：`512 B`、`1.2 KB`、`12 MB`。
///
/// 进位按 1024。整数部分满 10 仍保留一位小数（`12.4 MB`），整十则去掉
/// `.0`，避免设置行右侧被 `12.0 MB` 这种假精度拉长。
String formatStorageBytes(int bytes) {
  final safe = bytes < 0 ? 0 : bytes;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = safe.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit == 0) return '$safe B';
  final rounded = (value * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) {
    return '${rounded.toInt()} ${units[unit]}';
  }
  return '${rounded.toStringAsFixed(1)} ${units[unit]}';
}

Future<int> _fileBytes(File file) async {
  try {
    if (await file.exists()) return await file.length();
  } on FileSystemException {
    // 枚举和读长度之间文件可能被删掉，跳过这一项，不让整次统计失败。
  }
  return 0;
}
