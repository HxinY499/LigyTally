import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/app_database.dart';
import '../media/image_storage.dart';

class BackupService {
  BackupService(this.database, this.imageStorage);

  final AppDatabase database;
  final ImageStorage imageStorage;

  Future<void> exportAndShare({String? password}) async {
    final categories = await database.exportCategories();
    final transactions = await database.exportTransactions();
    final images = await database.exportImages();
    final now = DateTime.now();
    final archive = Archive();
    final manifest = <String, Object>{
      'format': 'ligy-tally-backup',
      'version': 3,
      'createdAt': now.toIso8601String(),
      'categoryCount': categories.length,
      'transactionCount': transactions.length,
      'imageCount': images.length,
    };
    final data = <String, Object>{
      'categories': categories.map((row) => row.toJson()).toList(),
      'transactions': transactions.map((row) => row.toJson()).toList(),
      'images': images.map((row) => row.toJson()).toList(),
    };
    archive.add(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
    archive.add(ArchiveFile.string('data.json', jsonEncode(data)));

    for (final image in images) {
      for (final relativePath in [image.imagePath, image.thumbnailPath]) {
        final file = await imageStorage.resolve(relativePath);
        if (!await file.exists()) {
          throw StateError('备份缺少图片：$relativePath');
        }
        final archivePath = 'files/${relativePath.replaceAll('\\', '/')}';
        archive.add(ArchiveFile.bytes(archivePath, await file.readAsBytes()));
      }
    }

    final encoded = ZipEncoder(
      password: password == null || password.isEmpty ? null : password,
    ).encodeBytes(archive);
    final cache = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(now);
    final file = File(p.join(cache.path, 'ligy-tally-$stamp.ligytally'));
    await file.writeAsBytes(encoded, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip')],
        subject: 'Ligy Tally 完整备份',
      ),
    );
  }

  Future<String?> pickBackupFile() async {
    const typeGroup = XTypeGroup(
      label: 'Ligy Tally 备份',
      mimeTypes: ['application/zip', 'application/octet-stream'],
      extensions: ['ligytally', 'zip'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    return file?.path;
  }

  Future<BackupPreview> inspect(String filePath, {String? password}) async {
    final archive = await _decode(filePath, password: password);
    final manifest = _jsonFile(archive, 'manifest.json');
    _validateManifest(manifest);
    return BackupPreview(
      createdAt: DateTime.parse(manifest['createdAt'] as String),
      transactionCount: manifest['transactionCount'] as int,
      imageCount: manifest['imageCount'] as int,
    );
  }

  Future<void> restore(String filePath, {String? password}) async {
    final archive = await _decode(filePath, password: password);
    final manifest = _jsonFile(archive, 'manifest.json');
    _validateManifest(manifest);
    final data = _jsonFile(archive, 'data.json');
    final categoryRows = (data['categories'] as List<Object?>)
        .map(
          (item) =>
              CategoryEntry.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList();
    final transactionRows = (data['transactions'] as List<Object?>)
        .map(
          (item) =>
              TransactionEntry.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList();
    final imageRows = (data['images'] as List<Object?>)
        .map(
          (item) => TransactionImageEntry.fromJson(
            (item as Map).cast<String, Object?>(),
          ),
        )
        .toList();

    if (transactionRows.length != manifest['transactionCount'] ||
        imageRows.length != manifest['imageCount']) {
      throw const FormatException('备份记录数量不一致');
    }

    final support = await getApplicationSupportDirectory();
    final stage = Directory(
      p.join(support.path, '.restore_${DateTime.now().millisecondsSinceEpoch}'),
    );
    await stage.create(recursive: true);
    try {
      for (final image in imageRows) {
        for (final relativePath in [image.imagePath, image.thumbnailPath]) {
          final normalized = p.normalize(relativePath);
          if (p.isAbsolute(normalized) || normalized.startsWith('..')) {
            throw const FormatException('备份包含非法图片路径');
          }
          final entry = archive.findFile(
            'files/${relativePath.replaceAll('\\', '/')}',
          );
          if (entry == null || !entry.isFile) {
            throw FormatException('备份缺少图片：$relativePath');
          }
          final output = File(p.join(stage.path, normalized));
          await output.parent.create(recursive: true);
          await output.writeAsBytes(entry.content, flush: true);
        }
      }

      final oldCategories = await database.exportCategories();
      final oldTransactions = await database.exportTransactions();
      final oldImages = await database.exportImages();
      await database.replaceAllData(
        categoryRows: categoryRows,
        transactionRows: transactionRows,
        imageRows: imageRows,
      );
      try {
        final currentMedia = Directory(p.join(support.path, 'media'));
        final oldMedia = Directory(
          p.join(support.path, '.media_before_restore'),
        );
        if (await oldMedia.exists()) await oldMedia.delete(recursive: true);
        if (await currentMedia.exists()) {
          await currentMedia.rename(oldMedia.path);
        }
        final stagedMedia = Directory(p.join(stage.path, 'media'));
        if (await stagedMedia.exists()) {
          await stagedMedia.rename(currentMedia.path);
        }
        if (await oldMedia.exists()) await oldMedia.delete(recursive: true);
      } catch (_) {
        final currentMedia = Directory(p.join(support.path, 'media'));
        final oldMedia = Directory(
          p.join(support.path, '.media_before_restore'),
        );
        if (await currentMedia.exists()) {
          await currentMedia.delete(recursive: true);
        }
        if (await oldMedia.exists()) {
          await oldMedia.rename(currentMedia.path);
        }
        await database.replaceAllData(
          categoryRows: oldCategories,
          transactionRows: oldTransactions,
          imageRows: oldImages,
        );
        rethrow;
      }
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  Future<Archive> _decode(String path, {String? password}) async {
    final bytes = await File(path).readAsBytes();
    return ZipDecoder().decodeBytes(
      bytes,
      verify: true,
      password: password == null || password.isEmpty ? null : password,
    );
  }

  Map<String, Object?> _jsonFile(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null || !file.isFile) {
      throw FormatException('备份缺少 $name');
    }
    final decoded = jsonDecode(utf8.decode(file.content));
    if (decoded is! Map) throw FormatException('$name 格式错误');
    return decoded.cast<String, Object?>();
  }

  void _validateManifest(Map<String, Object?> manifest) {
    if (manifest['format'] != 'ligy-tally-backup' || manifest['version'] != 3) {
      throw const FormatException('不支持的备份格式或版本');
    }
  }
}

class BackupPreview {
  const BackupPreview({
    required this.createdAt,
    required this.transactionCount,
    required this.imageCount,
  });

  final DateTime createdAt;
  final int transactionCount;
  final int imageCount;
}
