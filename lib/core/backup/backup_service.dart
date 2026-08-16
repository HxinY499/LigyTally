import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../appearance/appearance.dart';
import '../database/app_database.dart';
import '../media/image_storage.dart';
import '../utils/category_icons.dart';

class BackupService {
  BackupService(this.database, this.imageStorage);

  final AppDatabase database;
  final ImageStorage imageStorage;

  /// 当前备份包的格式版本。
  ///
  /// - v3 → v4：多打包了分类自定义图标文件。v3 的包仍能恢复（见
  ///   [_validateManifest]）——那时的 `icon_key` 不可能是 `custom:` 前缀，
  ///   所以「没有图标文件」对 v3 来说是正确状态，不需要任何兼容分支。
  /// - v4 → v5：多带了整套外观配置（一个字符串）和壁纸图片。老包缺这两样，
  ///   恢复时保持当前外观不动即可——那正是「这个包里没有外观信息」的正确
  ///   处理，也不需要兼容分支。
  static const formatVersion = 5;

  /// 仍可恢复的历史版本。
  static const _supportedVersions = {3, 4, formatVersion};

  static const _format = 'ligy-tally-backup';

  Future<void> exportAndShare({
    String? password,
    AppearanceConfig? appearance,
  }) async {
    final cache = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    final file = File(p.join(cache.path, 'ligy-tally-$stamp.ligytally'));
    await writeBackupTo(file, password: password, appearance: appearance);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip')],
        subject: 'Ligy Tally 完整备份',
      ),
    );
  }

  /// 把完整备份写成 zip 文件。
  ///
  /// 从 [exportAndShare] 里拆出来是为了可测：exportAndShare 末尾要弹系统
  /// 分享面板，单测环境里拦不住，而「包里到底有没有把图片装进去」正是
  /// 这次改动最该被守住的东西。
  /// [appearance] 为 null 时包里不带外观（恢复方保持自己的外观不动）。
  Future<void> writeBackupTo(
    File target, {
    String? password,
    AppearanceConfig? appearance,
  }) async {
    final categories = await database.exportCategories();
    final transactions = await database.exportTransactions();
    final images = await database.exportImages();
    final iconPaths = _categoryIconPaths(categories);
    final archive = Archive();
    final manifest = <String, Object>{
      'format': _format,
      'version': formatVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'categoryCount': categories.length,
      'transactionCount': transactions.length,
      'imageCount': images.length,
      'categoryIconCount': iconPaths.length,
      'hasAppearance': appearance != null,
    };
    final data = <String, Object>{
      'categories': categories.map((row) => row.toJson()).toList(),
      'transactions': transactions.map((row) => row.toJson()).toList(),
      'images': images.map((row) => row.toJson()).toList(),
      // 整套外观就是一个字符串（见 [AppearanceConfig.encode]），所以往备份里
      // 加它只需要这一行。加进来的理由：用户花时间调出来的一套外观，
      // 换机恢复后账单全在、外观全丢，这件事对「这是我的 app」的伤害
      // 比少几个开关大得多。
      if (appearance != null) 'appearance': appearance.encode(),
    };
    archive.add(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
    archive.add(ArchiveFile.string('data.json', jsonEncode(data)));

    for (final image in images) {
      for (final relativePath in [image.imagePath, image.thumbnailPath]) {
        await _pack(archive, relativePath, label: '图片');
      }
    }
    for (final relativePath in iconPaths) {
      await _pack(archive, relativePath, label: '分类图标');
    }
    // 壁纸文件必须跟着走，否则恢复方拿到一份「说有壁纸、但文件不在」的配置。
    // 缺文件不算致命（用户可能在系统文件管理器里删过），跳过就是。
    if (appearance?.hasWallpaper ?? false) {
      await _pack(
        archive,
        kWallpaperRelativePath,
        label: '壁纸',
        required: false,
      );
    }

    final encoded = ZipEncoder(
      password: password == null || password.isEmpty ? null : password,
    ).encodeBytes(archive);
    await target.writeAsBytes(encoded, flush: true);
  }

  /// 把一个本地文件装进包。
  ///
  /// 默认缺文件直接抛错——备份的承诺是「一字不差」，悄悄少打一张图，
  /// 用户要到换机恢复那天才会发现。[required] 为 false 时缺文件静默跳过，
  /// 只给「丢了也不影响数据完整性」的附属文件（壁纸）用。
  Future<void> _pack(
    Archive archive,
    String relativePath, {
    required String label,
    bool required = true,
  }) async {
    final file = await imageStorage.resolve(relativePath);
    if (!await file.exists()) {
      if (!required) return;
      throw StateError('备份缺少$label：$relativePath');
    }
    archive.add(
      ArchiveFile.bytes(_archivePath(relativePath), await file.readAsBytes()),
    );
  }

  /// 分类里用到的自定义图标的相对路径（去重、顺序稳定）。
  ///
  /// 一级和二级分类可以指向同一张图（用户给「餐饮」和「三餐」选了同一张），
  /// 所以要按路径去重，否则 zip 里会出现同名条目。
  List<String> _categoryIconPaths(List<CategoryEntry> categories) {
    final ids = customIconIdsOf(categories.map((row) => row.iconKey));
    return [for (final id in ids) categoryIconRelativePath(id)];
  }

  /// zip 内路径：统一用 `/`，Windows 上导出的包在手机上也能找到。
  String _archivePath(String relativePath) =>
      'files/${relativePath.replaceAll('\\', '/')}';

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
      // v3 的包没这个字段，缺省当 0。
      categoryIconCount: manifest['categoryIconCount'] as int? ?? 0,
    );
  }

  /// 恢复整个备份，返回包里带的外观配置（老包 / 没带外观的包为 null）。
  ///
  /// 外观不在这里落地：这一层不认识 Riverpod，把它交回调用方，
  /// 由设置页在恢复成功后写进 `appearanceProvider`。
  ///
  /// 调用方还需要在成功后调一次 [ImageStorage.evictWallpaperCache]——
  /// 换过 media 目录之后壁纸文件已经是新的那张，但 Flutter 的图片缓存还按
  /// 老路径记着旧图。那件事要 `PaintingBinding`，属于 UI 层，不该由这一层
  /// 承担（本服务在纯 Dart 测试里跑，那里根本没有 binding）。
  Future<AppearanceConfig?> restore(
    String filePath, {
    String? password,
  }) async {
    final archive = await _decode(filePath, password: password);
    final manifest = _jsonFile(archive, 'manifest.json');
    _validateManifest(manifest);
    final data = _jsonFile(archive, 'data.json');
    final appearanceCode = data['appearance'];
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

    final support = await imageStorage.supportRoot();
    final stage = Directory(
      p.join(support, '.restore_${DateTime.now().millisecondsSinceEpoch}'),
    );
    await stage.create(recursive: true);
    try {
      for (final image in imageRows) {
        for (final relativePath in [image.imagePath, image.thumbnailPath]) {
          await _extractTo(stage, archive, relativePath, label: '图片');
        }
      }
      // 分类图标缺文件不算致命：分类本身在 data.json 里是完好的，
      // 缺图只会让那个分类回落到默认图标。为一张几 KB 的图让整次恢复
      // 失败，代价远大于收益——账单图片才必须一字不差。
      for (final relativePath in _categoryIconPaths(categoryRows)) {
        await _extractTo(
          stage,
          archive,
          relativePath,
          label: '分类图标',
          required: false,
        );
      }
      // 壁纸同理不算致命：包里没有就是没有，外观配置那边会因为文件不在而
      // 只显示蒙版（见 `_WallpaperLayer` 的 errorBuilder）。
      await _extractTo(
        stage,
        archive,
        kWallpaperRelativePath,
        label: '壁纸',
        required: false,
      );

      final oldCategories = await database.exportCategories();
      final oldTransactions = await database.exportTransactions();
      final oldImages = await database.exportImages();
      await database.replaceAllData(
        categoryRows: categoryRows,
        transactionRows: transactionRows,
        imageRows: imageRows,
      );
      try {
        final currentMedia = Directory(p.join(support, 'media'));
        final oldMedia = Directory(p.join(support, '.media_before_restore'));
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
        final currentMedia = Directory(p.join(support, 'media'));
        final oldMedia = Directory(p.join(support, '.media_before_restore'));
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
    // 只有走到这里才算恢复成功，外观才该跟着换——上面任何一步失败都会
    // 抛出去，调用方拿不到这个返回值，也就不会把外观改掉。
    if (appearanceCode is! String) return null;
    if (!AppearanceConfig.looksLikeCode(appearanceCode)) return null;
    return AppearanceConfig.decode(appearanceCode);
  }

  /// 把包内一个文件解到暂存目录。
  ///
  /// [required] 为 false 时，包里没有这个文件就静默跳过。
  Future<void> _extractTo(
    Directory stage,
    Archive archive,
    String relativePath, {
    required String label,
    bool required = true,
  }) async {
    final normalized = p.normalize(relativePath);
    // 备份文件是外部输入：不校验就等于允许它往 support 目录外面写。
    if (p.isAbsolute(normalized) || normalized.startsWith('..')) {
      throw FormatException('备份包含非法$label路径');
    }
    final entry = archive.findFile(_archivePath(relativePath));
    if (entry == null || !entry.isFile) {
      if (!required) return;
      throw FormatException('备份缺少$label：$relativePath');
    }
    final output = File(p.join(stage.path, normalized));
    await output.parent.create(recursive: true);
    await output.writeAsBytes(entry.content, flush: true);
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
    if (manifest['format'] != _format ||
        !_supportedVersions.contains(manifest['version'])) {
      throw const FormatException('不支持的备份格式或版本');
    }
  }
}

class BackupPreview {
  const BackupPreview({
    required this.createdAt,
    required this.transactionCount,
    required this.imageCount,
    required this.categoryIconCount,
  });

  final DateTime createdAt;
  final int transactionCount;
  final int imageCount;

  /// 包里带的分类自定义图标数量。v3 的老包恒为 0。
  final int categoryIconCount;
}
