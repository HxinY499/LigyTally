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
      await teardown(tester);
    });
  });
}
