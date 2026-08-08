import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

class CategoryConfigService {
  CategoryConfigService(this.database);

  final AppDatabase database;
  final Uuid _uuid = const Uuid();

  Future<void> exportAndShare() async {
    final rows = (await database.exportCategories())
        .where((category) => category.isActive)
        .toList();
    final payload = <String, Object>{
      'format': 'ligy-tally-categories',
      'version': 1,
      'expense': _buildNodes(rows, 0),
      'income': _buildNodes(rows, 1),
    };
    final cache = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    final file = File(p.join(cache.path, 'ligy-categories-$stamp.json'));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(payload), flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Ligy Tally 分类配置',
      ),
    );
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
      parentCount: parsed.where((row) => row.level == 1).length,
      childCount: parsed.where((row) => row.level == 2).length,
    );
  }

  Future<void> importAndReplace(String path) async {
    final rows = await _parse(path);
    await database.replaceActiveCategoryConfig(rows);
  }

  List<Map<String, Object>> _buildNodes(List<CategoryEntry> rows, int kind) {
    final parents =
        rows.where((row) => row.kind == kind && row.level == 1).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return [
      for (final parent in parents)
        {
          'name': parent.name,
          'icon': parent.iconKey,
          'children': [
            for (final child
                in (rows.where((row) => row.parentId == parent.id).toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))))
              {'name': child.name, 'icon': child.iconKey},
          ],
        },
    ];
  }

  Future<List<CategoryEntry>> _parse(String path) async {
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map) throw const FormatException('分类配置必须是 JSON 对象');
    final root = decoded.cast<String, Object?>();
    if (root['format'] != 'ligy-tally-categories' || root['version'] != 1) {
      throw const FormatException('不支持的分类配置格式或版本');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = <CategoryEntry>[];
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
            iconKey: _icon(node['icon']),
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
              iconKey: _icon(child['icon']),
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
    return rows;
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

  String _icon(Object? value) {
    if (value is! String || value.trim().isEmpty) return 'other';
    return value.trim();
  }
}

class CategoryConfigPreview {
  const CategoryConfigPreview({
    required this.parentCount,
    required this.childCount,
  });

  final int parentCount;
  final int childCount;
}
