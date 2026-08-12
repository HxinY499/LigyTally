import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/app_database.dart';
import '../utils/ledger_date.dart';

/// 按时间范围把账单导出成 CSV，给 Excel / Numbers 打开，不带图片。
///
/// 和 [BackupService] 分工不同：完整备份是换机恢复用的私有包，这份是给人
/// 和表格软件读的明文。所以金额不带 ¥、日期用 `yyyy-MM-dd`、文件头加 UTF-8
/// BOM——Windows 上的 Excel 不认 BOM 就会把中文头读成乱码。
class CsvExportService {
  CsvExportService(this.database);

  final AppDatabase database;

  static const _headers = ['类型', '金额', '分类', '日期', '时间', '备注', '图片数量'];

  /// UTF-8 BOM。Excel 靠它判断编码，缺了中文列名会花。
  static const _bom = [0xEF, 0xBB, 0xBF];

  Future<int> exportAndShare([LedgerDateRange? range]) async {
    final csv = await buildCsv(range);
    if (csv == null) return 0;
    final cache = await getTemporaryDirectory();
    final file = File(p.join(cache.path, _fileName(range)));
    await file.writeAsBytes(csv.bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: _subject(range),
      ),
    );
    return csv.rowCount;
  }

  static String _fileName(LedgerDateRange? range) {
    if (range == null) return 'ligy-tally-all.csv';
    final start = dateKey(range.start);
    final end = dateKey(range.endExclusive.subtract(const Duration(days: 1)));
    return 'ligy-tally-$start-$end.csv';
  }

  static String _subject(LedgerDateRange? range) {
    if (range == null) return 'Ligy Tally 全部账单';
    final start = dateKey(range.start);
    final end = dateKey(range.endExclusive.subtract(const Duration(days: 1)));
    return 'Ligy Tally 账单 $start ~ $end';
  }

  /// 编出带 BOM 的 CSV 字节。没有账单时返回 null，让调用方决定
  /// 是 toast 还是仍丢一个空文件出去——空表对用户没有意义，这里选择不写。
  ///
  /// [range] 为 null 表示全部账单。
  Future<({Uint8List bytes, int rowCount})?> buildCsv([
    LedgerDateRange? range,
  ]) async {
    final items = await database.transactionsIn(range);
    if (items.isEmpty) return null;
    final categories = await database.exportCategories();
    final byId = {for (final row in categories) row.id: row};
    final imageCounts = await database.imageCountsFor([
      for (final item in items) item.transaction.id,
    ]);
    final buffer = StringBuffer();
    buffer.write(_row(_headers));
    for (final item in items) {
      final tx = item.transaction;
      final occurred = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt);
      buffer.write(
        _row([
          tx.kind == 0 ? '支出' : '收入',
          _amount(tx.amountCents),
          _categoryLabel(item.category, byId),
          tx.accountingDate,
          formatClock(occurred),
          tx.note,
          '${imageCounts[tx.id] ?? 0}',
        ]),
      );
    }
    return (
      bytes: Uint8List.fromList([..._bom, ...utf8.encode(buffer.toString())]),
      rowCount: items.length,
    );
  }

  /// 金额写成 `12.34`：不带货币符号、不用千分位。Excel 才能当数字求和。
  /// 正负由「类型」列表达，这里只出绝对值，避免支出在表格里变成负数还要再解释。
  static String _amount(int cents) {
    final absolute = cents.abs();
    return '${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  }

  /// 二级分类带上一级名字。CSV 里没有图标，光写「三餐」看不出属于餐饮。
  static String _categoryLabel(
    CategoryEntry category,
    Map<String, CategoryEntry> byId,
  ) {
    final parentId = category.parentId;
    if (parentId == null) return category.name;
    final parent = byId[parentId];
    if (parent == null) return category.name;
    return '${parent.name} / ${category.name}';
  }

  static String _row(List<String> fields) =>
      '${fields.map(_field).join(',')}\r\n';

  /// RFC 4180：含逗号、引号或换行的字段用双引号包起来，内部引号写成两个。
  static String _field(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\r') ||
        value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
