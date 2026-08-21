import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/export/csv_export_service.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/core/utils/ledger_date.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase database;
  late CsvExportService service;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    service = CsvExportService(database);
  });

  tearDown(() => database.close());

  Future<void> addTx({
    required String id,
    required int kind,
    required int amountCents,
    required String categoryId,
    required DateTime date,
    String note = '',
    String? locationName,
    double? locationLatitude,
    double? locationLongitude,
    int imageCount = 0,
    int hour = 9,
    int minute = 30,
  }) async {
    final occurred = DateTime(date.year, date.month, date.day, hour, minute);
    final now = occurred.millisecondsSinceEpoch;
    await database.saveTransaction(
      entry: TransactionsCompanion.insert(
        id: id,
        kind: kind,
        amountCents: amountCents,
        categoryId: categoryId,
        accountingDate: dateKey(date),
        occurredAt: occurred.millisecondsSinceEpoch,
        note: Value(note),
        locationLatitude: Value(locationLatitude),
        locationLongitude: Value(locationLongitude),
        locationName: Value(locationName),
        createdAt: now,
        updatedAt: now,
      ),
      newImages: [
        for (var i = 0; i < imageCount; i++)
          TransactionImagesCompanion.insert(
            id: '$id-img-$i',
            transactionId: id,
            imagePath: 'media/$id/$i.jpg',
            thumbnailPath: 'media/$id/${i}_thumb.jpg',
            sizeBytes: 10,
            sortOrder: Value(i),
            createdAt: now,
          ),
      ],
      removedImageIds: const {},
    );
  }

  String decode(List<int> bytes) {
    expect(bytes.take(3).toList(), [0xEF, 0xBB, 0xBF], reason: '必须带 UTF-8 BOM');
    return utf8.decode(bytes.sublist(3));
  }

  test('空区间返回 null，不编出只有表头的空表', () async {
    final csv = await service.buildCsv(monthRange(DateTime(2026, 8)));
    expect(csv, isNull);
  });

  test('按记账日过滤，金额、分类路径、图片数量、转义都正确', () async {
    final food = (await database.exportCategories()).singleWhere(
      (item) => item.name == '三餐',
    );
    final salary = (await database.exportCategories()).singleWhere(
      (item) => item.name == '工资',
    );

    await addTx(
      id: 'july',
      kind: 0,
      amountCents: 1200,
      categoryId: food.id,
      date: DateTime(2026, 7, 31),
    );
    await addTx(
      id: 'aug-1',
      kind: 0,
      amountCents: 12850,
      categoryId: food.id,
      date: DateTime(2026, 8, 1),
      note: '咖啡, "外卖"',
      imageCount: 2,
      hour: 8,
      minute: 5,
    );
    await addTx(
      id: 'aug-2',
      kind: 1,
      amountCents: 500000,
      categoryId: salary.id,
      date: DateTime(2026, 8, 15),
      hour: 12,
      minute: 0,
    );
    await addTx(
      id: 'sep',
      kind: 0,
      amountCents: 300,
      categoryId: food.id,
      date: DateTime(2026, 9, 1),
    );

    final csv = await service.buildCsv(monthRange(DateTime(2026, 8)));
    expect(csv, isNotNull);
    expect(csv!.rowCount, 2);
    final text = decode(csv.bytes);
    expect(text.startsWith('类型,金额,分类,日期,时间,地点,备注,图片数量\r\n'), isTrue);
    expect(
      text,
      contains('支出,128.50,餐饮 / 三餐,2026-08-01,08:05,,"咖啡, ""外卖""",2\r\n'),
    );
    expect(text, contains('收入,5000.00,工资,2026-08-15,12:00,,,0\r\n'));
    expect(text, isNot(contains('july')));
    expect(text, isNot(contains('2026-09-01')));
    expect(text, isNot(contains('¥')));
  });

  test('同一天按发生时间升序，方便表格从上往下读', () async {
    final food = (await database.exportCategories()).singleWhere(
      (item) => item.name == '三餐',
    );
    await addTx(
      id: 'later',
      kind: 0,
      amountCents: 200,
      categoryId: food.id,
      date: DateTime(2026, 8, 12),
      hour: 18,
    );
    await addTx(
      id: 'earlier',
      kind: 0,
      amountCents: 100,
      categoryId: food.id,
      date: DateTime(2026, 8, 12),
      hour: 8,
    );

    final csv = await service.buildCsv(monthRange(DateTime(2026, 8)));
    final text = decode(csv!.bytes);
    expect(text.indexOf('08:30'), lessThan(text.indexOf('18:30')));
  });

  test('不传区间就是全部账单', () async {
    final food = (await database.exportCategories()).singleWhere(
      (item) => item.name == '三餐',
    );
    await addTx(
      id: 'old',
      kind: 0,
      amountCents: 100,
      categoryId: food.id,
      date: DateTime(2025, 12, 31),
    );
    await addTx(
      id: 'now',
      kind: 0,
      amountCents: 200,
      categoryId: food.id,
      date: DateTime(2026, 8, 1),
    );

    final all = await service.buildCsv();
    expect(all!.rowCount, 2);
    final year = await service.buildCsv(yearRange(DateTime(2026, 8, 1)));
    expect(year!.rowCount, 1);
    expect(decode(year.bytes), isNot(contains('2025-12-31')));
  });

  test('地点列导出可读地名，没有地点就留空', () async {
    final food = (await database.exportCategories()).singleWhere(
      (item) => item.name == '三餐',
    );
    await addTx(
      id: 'with-place',
      kind: 0,
      amountCents: 8800,
      categoryId: food.id,
      date: DateTime(2026, 8, 19),
      locationLatitude: 32.04,
      locationLongitude: 118.78,
      locationName: '新街口',
    );
    await addTx(
      id: 'coords-only',
      kind: 0,
      amountCents: 1200,
      categoryId: food.id,
      date: DateTime(2026, 8, 19),
      hour: 12,
      locationLatitude: 32.05,
      locationLongitude: 118.79,
    );

    final csv = await service.buildCsv(monthRange(DateTime(2026, 8)));
    final text = decode(csv!.bytes);
    expect(text, contains(',新街口,'));
    expect(text, contains(',已记录位置,'));
  });

  group('带图片的 xlsx', () {
    late Directory support;

    /// 1×1 透明 PNG。excel_plus 靠文件头认格式，不看出路后缀。
    const png = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];

    setUp(() async {
      support = await Directory.systemTemp.createTemp('ligy_xlsx');
      service = CsvExportService(database, ImageStorage.atRoot(support.path));
    });

    tearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });

    Future<void> writePng(String relativePath) async {
      final file = File(p.join(support.path, relativePath));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png);
    }

    test('空区间返回 null', () async {
      final xlsx = await service.buildXlsx(monthRange(DateTime(2026, 8)));
      expect(xlsx, isNull);
    });

    test('图片嵌在账单右侧，缺文件的格子留空不让整次导出失败', () async {
      final food = (await database.exportCategories()).singleWhere(
        (item) => item.name == '三餐',
      );
      await addTx(
        id: 'with-photos',
        kind: 0,
        amountCents: 12850,
        categoryId: food.id,
        date: DateTime(2026, 8, 1),
        note: '咖啡',
        imageCount: 2,
      );
      await addTx(
        id: 'missing-file',
        kind: 0,
        amountCents: 300,
        categoryId: food.id,
        date: DateTime(2026, 8, 2),
        imageCount: 1,
        hour: 12,
      );
      await writePng('media/with-photos/0.jpg');
      await writePng('media/with-photos/1.jpg');

      final xlsx = await service.buildXlsx(monthRange(DateTime(2026, 8)));
      expect(xlsx, isNotNull);
      expect(xlsx!.rowCount, 2);

      final excel = Excel.decodeBytes(xlsx.bytes);
      final sheet = excel['账单'];
      expect(sheet.cell(CellIndex.indexByString('A1')).value.toString(), '类型');
      expect(sheet.cell(CellIndex.indexByString('I1')).value.toString(), '图片1');
      expect(sheet.cell(CellIndex.indexByString('M1')).value.toString(), '图片5');
      expect(sheet.cell(CellIndex.indexByString('A2')).value.toString(), '支出');
      expect(
        (sheet.cell(CellIndex.indexByString('B2')).value as DoubleCellValue)
            .value,
        128.5,
      );
      expect(
        (sheet.cell(CellIndex.indexByString('H2')).value as IntCellValue).value,
        2,
      );
      expect(sheet.images, hasLength(2));
      expect(
        sheet.images.map((image) => image.anchor.columnIndex).toList(),
        [8, 9],
      );
      expect(
        sheet.images.every((image) => image.anchor.rowIndex == 1),
        isTrue,
      );
    });
  });
}
