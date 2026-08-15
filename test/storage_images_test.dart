import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/utils/ledger_date.dart';
import 'package:ligy_tally/features/ledger/application/ledger_service.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/features/settings/presentation/storage_images_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> addTx(
    AppDatabase database, {
    required String id,
    required DateTime date,
    int imageCount = 0,
    int hour = 9,
    int imageBytes = 10,
    int width = 0,
    String note = '',
  }) async {
    final food = (await database.exportCategories()).firstWhere(
      (item) => item.name == '三餐',
    );
    final occurred = DateTime(date.year, date.month, date.day, hour);
    final now = occurred.millisecondsSinceEpoch;
    await database.saveTransaction(
      entry: TransactionsCompanion.insert(
        id: id,
        kind: 0,
        amountCents: 1200,
        categoryId: food.id,
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
            width: Value(width),
            height: Value(width),
            sizeBytes: imageBytes,
            sortOrder: Value(i),
            createdAt: now,
          ),
      ],
      removedImageIds: const {},
    );
  }

  group('账单图片查询与删除', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => database.close());

    test('列出全部账单图，新的在前，同一笔按 sortOrder', () async {
      await addTx(database, id: 'old', date: DateTime(2026, 7, 1), imageCount: 1);
      await addTx(
        database,
        id: 'new',
        date: DateTime(2026, 8, 15),
        imageCount: 2,
      );
      await addTx(database, id: 'plain', date: DateTime(2026, 8, 16));

      final items = await database.watchAllImages().first;
      expect(items.map((item) => item.image.id), [
        'new-img-0',
        'new-img-1',
        'old-img-0',
      ]);
    });

    test('每张图都带回它所属的分类，且不会因为连表多出行', () async {
      await addTx(
        database,
        id: 'tx',
        date: DateTime(2026, 8, 15),
        imageCount: 2,
        note: '和同事聚餐',
      );

      final items = await database.watchAllImages().first;
      // 连了 categories 之后最容易出的错是行数翻倍或丢行。
      expect(items, hasLength(2));
      expect(items.map((item) => item.category.name), ['三餐', '三餐']);
      expect(items.first.transaction.note, '和同事聚餐');
      // 组标题要跳到这笔账单，编辑页收的是完整的 LedgerItem。
      final ledger = items.first.ledgerItem;
      expect(ledger.transaction.id, 'tx');
      expect(ledger.category.name, '三餐');
    });

    test('删图片只去图，账单还在', () async {
      await addTx(
        database,
        id: 'keep',
        date: DateTime(2026, 8, 15),
        imageCount: 2,
      );
      await database.deleteImages({'keep-img-0'});

      final items = await database.watchAllImages().first;
      expect(items.map((item) => item.image.id), ['keep-img-1']);
      expect(await database.exportTransactions(), hasLength(1));
    });

    test('服务层删库记录后也删掉原图和缩略图', () async {
      final dir = await Directory.systemTemp.createTemp('ligy_storage_images');
      addTearDown(() => dir.delete(recursive: true));
      final storage = ImageStorage.atRoot(dir.path);
      final service = LedgerService(database, storage);

      await addTx(
        database,
        id: 'tx',
        date: DateTime(2026, 8, 15),
        imageCount: 1,
      );
      final image = File(p.join(dir.path, 'media/tx/0.jpg'));
      final thumb = File(p.join(dir.path, 'media/tx/0_thumb.jpg'));
      await image.create(recursive: true);
      await thumb.create(recursive: true);
      await image.writeAsBytes(const [1, 2, 3]);
      await thumb.writeAsBytes(const [4, 5]);

      final items = await database.watchAllImages().first;
      await service.deleteImages(items.map((item) => item.image));

      expect(await database.watchAllImages().first, isEmpty);
      expect(await image.exists(), isFalse);
      expect(await thumb.exists(), isFalse);
      expect(await database.exportTransactions(), hasLength(1));
    });
  });

  group('按大小排序', () {
    test('largest 把大图排到最前，跨账单也一样', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await addTx(
        database,
        id: 'old',
        date: DateTime(2026, 7, 1),
        imageCount: 1,
        imageBytes: 900,
      );
      await addTx(
        database,
        id: 'new',
        date: DateTime(2026, 8, 15),
        imageCount: 2,
        imageBytes: 100,
      );

      final newest = await database
          .watchAllImages(sort: LedgerImageSort.newest)
          .first;
      expect(newest.first.image.id, 'new-img-0');

      final largest = await database
          .watchAllImages(sort: LedgerImageSort.largest)
          .first;
      expect(largest.first.image.id, 'old-img-0');
      expect(largest.map((item) => item.image.sizeBytes), [900, 100, 100]);
    });
  });

  group('批量重压', () {
    late Directory dir;
    late AppDatabase database;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ligy_recompress');
      database = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('只挑长边超标和尺寸未知的，写回新体积', () async {
      await addTx(
        database,
        id: 'big',
        date: DateTime(2026, 8, 15),
        imageCount: 1,
        imageBytes: 1000,
        width: 3000,
      );
      await addTx(
        database,
        id: 'small',
        date: DateTime(2026, 8, 14),
        imageCount: 1,
        imageBytes: 200,
        width: 800,
      );

      final storage = _FakeStorage(dir.path, compressedBytes: 250);
      final service = LedgerService(database, storage);
      final result = await service.recompressLargeImages();

      expect(storage.touched, ['media/big/0.jpg']);
      expect(result.candidateCount, 1);
      expect(result.compressedCount, 1);
      expect(result.freedBytes, 750);

      final images = await database.exportImages();
      final big = images.firstWhere((row) => row.id == 'big-img-0');
      final small = images.firstWhere((row) => row.id == 'small-img-0');
      expect(big.sizeBytes, 250);
      expect(big.width, kRecompressMaxSide);
      expect(small.sizeBytes, 200);
    });

    test('压不出更小结果时保留原图，不写库也不算进节省', () async {
      await addTx(
        database,
        id: 'big',
        date: DateTime(2026, 8, 15),
        imageCount: 1,
        imageBytes: 1000,
        width: 3000,
      );

      final service = LedgerService(database, _FakeStorage(dir.path));
      final result = await service.recompressLargeImages();

      expect(result.candidateCount, 1);
      expect(result.compressedCount, 0);
      expect(result.freedBytes, 0);
      final row = (await database.exportImages()).single;
      expect(row.sizeBytes, 1000);
      expect(row.width, 3000);
    });

    test('进度从 0 报到总数，让页面能显示 n / N', () async {
      await addTx(
        database,
        id: 'big',
        date: DateTime(2026, 8, 15),
        imageCount: 2,
        imageBytes: 900,
        width: 3000,
      );

      final seen = <String>[];
      await LedgerService(
        database,
        _FakeStorage(dir.path, compressedBytes: 450),
      ).recompressLargeImages(onProgress: (done, total) {
        seen.add('$done/$total');
      });

      expect(seen, ['0/2', '1/2', '2/2']);
    });
  });

  group('账单图片页', () {
    void usePhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 2700);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    Future<void> pumpPage(WidgetTester tester, AppDatabase database) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: buildMaterialTheme(Brightness.light),
            builder: (context, child) => FTheme(
              data: buildForuiTheme(),
              child: FToaster(child: child!),
            ),
            home: const StorageImagesScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> teardown(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }

    testWidgets('没有图片时说明记账单可以加照片', (tester) async {
      usePhone(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pumpPage(tester, database);

      expect(find.text('还没有账单图片'), findsOneWidget);
      expect(find.text('选择'), findsNothing);
      // 一张图都没有时不该先摆出三个浏览方式让人选。
      expect(find.text('按账单'), findsNothing);
      await teardown(tester);
    });

  });
}

/// 只按固定比例「压缩」的假存储：真压缩要走 platform channel，单测里跑不了，
/// 而这里要守的是挑图规则和写回逻辑，不是 JPEG 编码本身。
class _FakeStorage extends ImageStorage {
  _FakeStorage(super.root, {this.compressedBytes}) : super.atRoot();

  /// 压完的体积；null 表示压不出更小的结果，走放弃分支。
  final int? compressedBytes;

  final List<String> touched = [];

  @override
  Future<({int sizeBytes, int width, int height})?> recompress({
    required String relativePath,
    int maxSide = kRecompressMaxSide,
    int quality = kRecompressQuality,
  }) async {
    touched.add(relativePath);
    final bytes = compressedBytes;
    if (bytes == null) return null;
    return (sizeBytes: bytes, width: maxSide, height: maxSide);
  }
}
