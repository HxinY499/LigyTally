import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../media/image_storage.dart';
import '../utils/category_icons.dart';

/// 分类配置的导出 / 导入。
///
/// ## 与完整备份的分工
///
/// 完整备份（[BackupService]）是「换手机、原样搬」；分类配置是「把我调好的
/// 一套分类给别人用」——只带分类，不带一分钱的账单。所以它是单个可读的
/// JSON 文件，导入时所有 id 都重新生成。
///
/// ## 自定义图标怎么跟着走
///
/// 分类图标支持用户上传图片后，纯 JSON 就不够了——图片是二进制。这里选择
/// **把图片 base64 内嵌进同一个 JSON**，而不是改成 zip：
///
/// - 单文件才守住了「一个能直接看、能发微信、能贴进聊天框」的定位，
///   换成 zip 就和完整备份长得一样，用户分不清该用哪个；
/// - 图标已经压到 256px / q88，一张几 KB，二三十个自定义图标也就几百 KB，
///   base64 撑大 33% 仍在可接受范围（真正大的是账单照片，那是备份的事）；
/// - 没有自定义图标时（绝大多数情况）产物与 v1 逐字节同构，只是 version 变 2。
class CategoryConfigService {
  CategoryConfigService(this.database, this.imageStorage);

  final AppDatabase database;
  final ImageStorage imageStorage;
  final Uuid _uuid = const Uuid();

  /// 当前导出的格式版本。
  ///
  /// v1 → v2 只是多了可选的 `iconImage` 字段，v1 的文件仍能原样导入
  /// （见 [_parse] 的版本判断）。
  static const formatVersion = 2;

  static const _format = 'ligy-tally-categories';

  Future<void> exportAndShare() async {
    final cache = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    final file = File(p.join(cache.path, 'ligy-categories-$stamp.json'));
    await writeConfigTo(file);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Ligy Tally 分类配置',
      ),
    );
  }

  /// 把当前分类配置写成 JSON 文件。
  ///
  /// 从 [exportAndShare] 里拆出来，是为了让「文件里有什么」可测：
  /// exportAndShare 末尾要弹系统分享面板，单测环境里拦不住，
  /// 而真正需要守住的契约恰恰是这份 JSON 的内容
  /// （自定义图标必须内嵌图片、内置图标必须不带，否则文件白白变大）。
  Future<void> writeConfigTo(File file) async {
    final rows = (await database.exportCategories())
        .where((category) => category.isActive)
        .toList();
    final images = await _collectIconImages(rows);
    final payload = <String, Object>{
      'format': _format,
      'version': formatVersion,
      'expense': _buildNodes(rows, 0, images),
      'income': _buildNodes(rows, 1, images),
    };
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(payload), flush: true);
  }

  /// 把用到的自定义图标读成 base64，key 是 iconKey。
  ///
  /// 文件丢了就跳过（而不是抛错）：分类本身是完好的，为一张缺失的图片
  /// 让整次导出失败不划算——导入方会看到这个分类回落到默认图标。
  /// 完整备份那边相反，缺图直接抛错，因为备份的承诺是「一字不差」。
  Future<Map<String, String>> _collectIconImages(
    List<CategoryEntry> rows,
  ) async {
    final result = <String, String>{};
    for (final row in rows) {
      final id = customCategoryIconId(row.iconKey);
      if (id == null || result.containsKey(row.iconKey)) continue;
      final file = await imageStorage.resolve(categoryIconRelativePath(id));
      if (!await file.exists()) continue;
      result[row.iconKey] = base64Encode(await file.readAsBytes());
    }
    return result;
  }

  Future<String?> pickConfigFile() async {
    const typeGroup = XTypeGroup(
      label: 'Ligy Tally 分类配置',
      mimeTypes: ['application/json', 'text/json'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    return file?.path;
  }

  Future<CategoryConfigPreview> inspect(String path) async {
    final parsed = await _parse(path);
    return CategoryConfigPreview(
      parentCount: parsed.rows.where((row) => row.level == 1).length,
      childCount: parsed.rows.where((row) => row.level == 2).length,
      iconImageCount: parsed.images.length,
    );
  }

  Future<void> importAndReplace(String path) async {
    final parsed = await _parse(path);
    // 先落盘图片再写库：反过来的话，写库成功而写图失败会留下一批
    // 指向不存在文件的分类，界面上是一片兜底图标且无法自愈。
    for (final entry in parsed.images.entries) {
      await imageStorage.writeCategoryIcon(
        iconId: entry.key,
        bytes: entry.value,
      );
    }
    await database.replaceActiveCategoryConfig(parsed.rows);
    // 替换掉的旧分类可能带着自己的图片，一起回收。
    final live = await database.exportCategories();
    await imageStorage.pruneCategoryIcons(
      customIconIdsOf(live.map((row) => row.iconKey)),
    );
  }

  List<Map<String, Object>> _buildNodes(
    List<CategoryEntry> rows,
    int kind,
    Map<String, String> images,
  ) {
    Map<String, Object> node(CategoryEntry row) => {
      'name': row.name,
      'icon': row.iconKey,
      // 没有图片时整个 entry 消失，产物与 v1 的 JSON 逐字节同构。
      'iconImage': ?images[row.iconKey],
    };

    final parents =
        rows.where((row) => row.kind == kind && row.level == 1).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return [
      for (final parent in parents)
        {
          ...node(parent),
          'children': [
            for (final child
                in (rows.where((row) => row.parentId == parent.id).toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))))
              node(child),
          ],
        },
    ];
  }

  Future<_ParsedConfig> _parse(String path) async {
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map) throw const FormatException('分类配置必须是 JSON 对象');
    final root = decoded.cast<String, Object?>();
    final version = root['version'];
    if (root['format'] != _format || version is! int || version < 1) {
      throw const FormatException('不支持的分类配置格式或版本');
    }
    if (version > formatVersion) {
      // 说清是「版本太新」而不是「文件坏了」，用户才知道该去升级应用。
      throw const FormatException('这份配置来自更新的版本，请先升级应用');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = <CategoryEntry>[];
    // iconId → 图片字节。同一张图被多个分类共用时只解一次。
    final images = <String, List<int>>{};

    /// 处理一个节点的图标：内置 key 原样返回；自定义图片则重新生成 id
    /// 并记下字节。**必须换 id**：导入方本地可能已经有同 id 的图标文件
    /// （比如把自己导出的配置又导回来，或两台设备各自生成过），
    /// 沿用原 id 会互相覆盖。
    String resolveIcon(Map<String, Object?> node) {
      final raw = node['icon'];
      final key = raw is String && raw.trim().isNotEmpty ? raw.trim() : 'other';
      if (!isCustomCategoryIcon(key)) return key;
      final encoded = node['iconImage'];
      // 有 custom: 前缀但没带图片：只能回落到默认图标，
      // 否则会指向一个本地根本不存在的文件。
      if (encoded is! String || encoded.isEmpty) return 'other';
      final List<int> bytes;
      try {
        bytes = base64Decode(encoded);
      } on FormatException {
        throw const FormatException('分类图标图片数据损坏');
      }
      if (bytes.isEmpty) return 'other';
      final id = _uuid.v4();
      images[id] = bytes;
      return customCategoryIconKey(id);
    }

    for (final group in [('expense', 0), ('income', 1)]) {
      final nodes = root[group.$1];
      if (nodes is! List) throw FormatException('${group.$1} 必须是数组');
      final parentNames = <String>{};
      for (var parentIndex = 0; parentIndex < nodes.length; parentIndex++) {
        final node = _asMap(nodes[parentIndex], '一级分类');
        final name = _requiredName(node['name']);
        if (!parentNames.add(name)) {
          throw FormatException('${group.$1} 中一级分类“$name”重复');
        }
        final parentId = _uuid.v4();
        rows.add(
          CategoryEntry(
            id: parentId,
            kind: group.$2,
            name: name,
            iconKey: resolveIcon(node),
            parentId: null,
            level: 1,
            sortOrder: parentIndex,
            isActive: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final children = node['children'] ?? const <Object>[];
        if (children is! List) {
          throw FormatException('“$name”的 children 必须是数组');
        }
        final childNames = <String>{};
        for (var childIndex = 0; childIndex < children.length; childIndex++) {
          final child = _asMap(children[childIndex], '二级分类');
          final childName = _requiredName(child['name']);
          if (!childNames.add(childName)) {
            throw FormatException('“$name”中二级分类“$childName”重复');
          }
          rows.add(
            CategoryEntry(
              id: _uuid.v4(),
              kind: group.$2,
              name: childName,
              iconKey: resolveIcon(child),
              parentId: parentId,
              level: 2,
              sortOrder: childIndex,
              isActive: true,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      }
    }
    if (!rows.any((row) => row.kind == 0 && row.level == 1) ||
        !rows.any((row) => row.kind == 1 && row.level == 1)) {
      throw const FormatException('收入和支出至少各需要一个一级分类');
    }
    return _ParsedConfig(rows: rows, images: images);
  }

  Map<String, Object?> _asMap(Object? value, String label) {
    if (value is! Map) throw FormatException('$label必须是对象');
    return value.cast<String, Object?>();
  }

  String _requiredName(Object? value) {
    if (value is! String || value.trim().isEmpty || value.trim().length > 12) {
      throw const FormatException('分类名称必须是 1 至 12 个字符');
    }
    return value.trim();
  }
}

/// 解析结果：待写库的分类 + 待落盘的图标（iconId → 字节）。
class _ParsedConfig {
  const _ParsedConfig({required this.rows, required this.images});

  final List<CategoryEntry> rows;
  final Map<String, List<int>> images;
}

class CategoryConfigPreview {
  const CategoryConfigPreview({
    required this.parentCount,
    required this.childCount,
    required this.iconImageCount,
  });

  final int parentCount;
  final int childCount;

  /// 配置里自带的自定义图标图片数量。
  final int iconImageCount;
}
