import 'dart:io';

import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../media/image_storage.dart';

/// 应用私有数据的磁盘占用。
///
/// 只统计本应用自己写的账单数据：`media/` 下的图片，以及 SQLite 主库和
/// 它的旁路文件。不含安装包、更新缓存、备份临时文件——那些不是「账本变大」。
class StorageUsage {
  const StorageUsage({
    required this.imageBytes,
    required this.categoryIconBytes,
    required this.databaseBytes,
  });

  /// 账单原图和缩略图。
  final int imageBytes;

  /// 分类自定义图标。
  final int categoryIconBytes;

  /// SQLite 主库 + WAL / SHM / journal。
  final int databaseBytes;

  int get mediaBytes => imageBytes + categoryIconBytes;

  int get totalBytes => mediaBytes + databaseBytes;
}

class StorageUsageService {
  StorageUsageService(this.database, this.imageStorage);

  final AppDatabase database;
  final ImageStorage imageStorage;

  Future<StorageUsage> measure() async {
    final support = await imageStorage.supportRoot();
    final media = Directory(p.join(support, kMediaDirName));
    final icons = Directory(p.join(media.path, kCategoryIconDirName));
    final iconBytes = await _directoryBytes(icons);
    final mediaBytes = await _directoryBytes(media);
    return StorageUsage(
      imageBytes: mediaBytes - iconBytes,
      categoryIconBytes: iconBytes,
      databaseBytes: await _databaseBytes(),
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

Future<int> _directoryBytes(Directory directory) async {
  if (!await directory.exists()) return 0;
  var total = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) {
      total += await _fileBytes(entity);
    }
  }
  return total;
}

Future<int> _fileBytes(File file) async {
  try {
    if (await file.exists()) return await file.length();
  } on FileSystemException {
    // 枚举和读长度之间文件可能被删掉，跳过这一项，不让整次统计失败。
  }
  return 0;
}
