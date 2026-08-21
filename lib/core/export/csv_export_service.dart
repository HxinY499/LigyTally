import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/app_database.dart';
import '../location/place_fix.dart';
import '../media/image_storage.dart';
import '../utils/ledger_date.dart';
import 'ledger_xlsx.dart';

/// 按时间范围把账单导出成表格，给 Excel / Numbers 打开。
///
/// 默认仍是 CSV、不带图片。勾选「同时导出图片」时改出 .xlsx，把每笔的图
/// 嵌进右侧单元格——CSV 塞不进图片，这是同一条导出路径上唯一能兑现
/// 「插到账单后面」的格式。
///
/// 和 [BackupService] 分工不同：完整备份是换机恢复用的私有包，这份是给人
/// 和表格软件读的明文。所以金额不带 ¥、日期用 `yyyy-MM-dd`、CSV 文件头加
/// UTF-8 BOM——Windows 上的 Excel 不认 BOM 就会把中文头读成乱码。
class CsvExportService {
  CsvExportService(this.database, [this.imageStorage]);

  final AppDatabase database;
  final ImageStorage? imageStorage;

  static const _headers = ['类型', '金额', '分类', '日期', '时间', '地点', '备注', '图片数量'];

  /// UTF-8 BOM。Excel 靠它判断编码，缺了中文列名会花。
  static const _bom = [0xEF, 0xBB, 0xBF];

  static const _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  Future<int> exportAndShare(
    LedgerDateRange? range, {
    bool includeImages = false,
  }) async {
    final built = includeImages
        ? await buildXlsx(range)
        : await buildCsv(range);
    if (built == null) return 0;
    final cache = await getTemporaryDirectory();
    final file = File(p.join(cache.path, _fileName(range, includeImages)));
    await file.writeAsBytes(built.bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: includeImages ? _xlsxMime : 'text/csv',
          ),
        ],
        subject: _subject(range),
      ),
    );
    return built.rowCount;
  }

  static String _fileName(LedgerDateRange? range, bool includeImages) {
    final ext = includeImages ? 'xlsx' : 'csv';
    if (range == null) return 'ligy-tally-all.$ext';
    final start = dateKey(range.start);
    final end = dateKey(range.endExclusive.subtract(const Duration(days: 1)));
    return 'ligy-tally-$start-$end.$ext';
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
    final table = <List<String>>[
      _headers,
      for (final item in items)
        [
          item.transaction.kind == 0 ? '支出' : '收入',
          _amount(item.transaction.amountCents),
          _categoryLabel(item.category, byId),
          item.transaction.accountingDate,
          formatClock(
            DateTime.fromMillisecondsSinceEpoch(item.transaction.occurredAt),
          ),
          item.transaction.locationLabel ?? '',
          item.transaction.note,
          '${imageCounts[item.transaction.id] ?? 0}',
        ],
    ];
    // 转义和拼字节放后台 isolate：账单多的时候主 isolate 会把设置页转圈卡住。
    final bytes = await Isolate.run(() => encodeCsvBytes(table));
    return (bytes: bytes, rowCount: items.length);
  }

  /// 编出带图片的 Excel。文件缺失的图跳过对应格子，不让一张丢图毁掉整次导出——
  /// 这不是备份，「能打开、其余行还在」比「一字不差」优先。
  Future<({Uint8List bytes, int rowCount})?> buildXlsx([
    LedgerDateRange? range,
  ]) async {
    final storage = imageStorage;
    if (storage == null) {
      throw StateError('导出图片需要 ImageStorage');
    }
    final items = await database.transactionsIn(range);
    if (items.isEmpty) return null;
    final categories = await database.exportCategories();
    final byId = {for (final row in categories) row.id: row};
    final ids = [for (final item in items) item.transaction.id];
    final grouped = await database.imagesGroupedFor(ids);
    final rows = <LedgerXlsxRow>[];
    for (final item in items) {
      final tx = item.transaction;
      final images = grouped[tx.id] ?? const [];
      final slots = List<LedgerXlsxImage?>.filled(kMaxTransactionImages, null);
      for (var i = 0; i < images.length && i < kMaxTransactionImages; i++) {
        final entry = images[i];
        final file = await storage.resolve(entry.imagePath);
        if (!await file.exists()) continue;
        slots[i] = (
          bytes: await file.readAsBytes(),
          width: entry.width,
          height: entry.height,
        );
      }
      final occurred = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt);
      rows.add((
        kind: tx.kind == 0 ? '支出' : '收入',
        amount: _amount(tx.amountCents),
        category: _categoryLabel(item.category, byId),
        date: tx.accountingDate,
        time: formatClock(occurred),
        location: tx.locationLabel ?? '',
        note: tx.note,
        imageCount: images.length,
        images: slots,
      ));
    }
    final bytes = await Isolate.run(() => encodeLedgerXlsx(rows));
    return (bytes: bytes, rowCount: items.length);
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

  /// 给 isolate 用：只收纯字符串表，不碰数据库。
  static Uint8List encodeCsvBytes(List<List<String>> rows) {
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.write(_row(row));
    }
    return Uint8List.fromList([..._bom, ...utf8.encode(buffer.toString())]);
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
