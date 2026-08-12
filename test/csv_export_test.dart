import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/export/csv_export_service.dart';
import 'package:ligy_tally/core/utils/ledger_date.dart';

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
    expect(text.startsWith('类型,金额,分类,日期,时间,备注,图片数量\r\n'), isTrue);
    expect(
      text,
      contains('支出,128.50,餐饮 / 三餐,2026-08-01,08:05,"咖啡, ""外卖""",2\r\n'),
    );
    expect(text, contains('收入,5000.00,工资,2026-08-15,12:00,,0\r\n'));
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
}
