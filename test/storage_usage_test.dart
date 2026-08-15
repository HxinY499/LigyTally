import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/core/storage/storage_usage.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/utils/ledger_date.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/features/settings/presentation/settings_screen.dart';
import 'package:ligy_tally/features/settings/presentation/storage_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('formatStorageBytes', () {
    test('字节与进位边界', () {
      expect(formatStorageBytes(0), '0 B');
      expect(formatStorageBytes(1), '1 B');
      expect(formatStorageBytes(1023), '1023 B');
      expect(formatStorageBytes(1024), '1 KB');
      expect(formatStorageBytes(1536), '1.5 KB');
      expect(formatStorageBytes(1024 * 1024), '1 MB');
      expect(formatStorageBytes(12 * 1024 * 1024), '12 MB');
      expect(formatStorageBytes(13002342), '12.4 MB');
      expect(formatStorageBytes(1024 * 1024 * 1024), '1 GB');
      expect(formatStorageBytes(1024 * 1024 * 1024 * 1024), '1 TB');
    });

    test('负数按 0 显示，不把异常值铺到设置行', () {
      expect(formatStorageBytes(-8), '0 B');
    });
  });

  group('isAppCacheFileName', () {
    test('认得本应用四种导出物与安装包', () {
      expect(isAppCacheFileName('LigyTally-1.4.21.apk'), isTrue);
      expect(isAppCacheFileName('LigyTally-1.4.21.apk.part'), isTrue);
      expect(isAppCacheFileName('ligy-tally-20260815-101500.ligytally'), isTrue);
      expect(isAppCacheFileName('ligy-tally-all.csv'), isTrue);
      expect(isAppCacheFileName('ligy-categories-20260815-101500.json'), isTrue);
    });

    test('不认别人的临时文件，免得清缓存踩到 image_picker', () {
      expect(isAppCacheFileName('image_picker_ABC123.jpg'), isFalse);
      expect(isAppCacheFileName('scaled_9f8e7d.png'), isFalse);
      expect(isAppCacheFileName('somebody-else.json'), isFalse);
      expect(isAppCacheFileName('notes.csv'), isFalse);
    });
  });

  group('StorageUsageService', () {
    late Directory support;
    late Directory cache;
    late AppDatabase database;
    late StorageUsageService service;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('ligy_support');
      cache = await Directory.systemTemp.createTemp('ligy_cache');
      database = AppDatabase.forTesting(NativeDatabase.memory());
      service = StorageUsageService(
        database,
        ImageStorage.atRoot(support.path),
        cacheRoot: () async => cache,
      );
    });

    tearDown(() async {
      await database.close();
      for (final dir in [support, cache]) {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    Future<File> writeFile(Directory root, String relative, int bytes) async {
      final file = File(p.join(root.path, relative));
      await file.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(bytes, 1), flush: true);
      return file;
    }

    /// 把文件时间推老，越过 [kOrphanMinAge] 的保护期。
    Future<void> makeOld(File file) async {
      await file.setLastModified(
        DateTime.now().subtract(kOrphanMinAge * 2),
      );
    }

    /// 存一笔带图的账单，图片文件真落盘。
    Future<void> addTxWithImage(
      String txId, {
      required int imageBytes,
      required int thumbBytes,
    }) async {
      final food = (await database.exportCategories()).firstWhere(
        (item) => item.name == '三餐',
      );
      final now = DateTime(2026, 8, 15).millisecondsSinceEpoch;
      final imagePath = p.join(kMediaDirName, txId, 'a.jpg');
      final thumbPath = p.join(kMediaDirName, txId, 'a_thumb.jpg');
      await writeFile(support, imagePath, imageBytes);
      await writeFile(support, thumbPath, thumbBytes);
      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: txId,
          kind: 0,
          amountCents: 1200,
          categoryId: food.id,
          accountingDate: dateKey(DateTime(2026, 8, 15)),
          occurredAt: now,
          createdAt: now,
          updatedAt: now,
        ),
        newImages: [
          TransactionImagesCompanion.insert(
            id: '$txId-img',
            transactionId: txId,
            imagePath: imagePath,
            thumbnailPath: thumbPath,
            sizeBytes: imageBytes,
            createdAt: now,
          ),
        ],
        removedImageIds: const {},
      );
    }

    /// 让某个分类用上自定义图标，并把图标文件写进去。
    Future<void> useCustomIcon(String iconId, int bytes) async {
      final rows = await database.exportCategories();
      final target = rows.firstWhere((item) => item.name == '三餐');
      await database.replaceAllData(
        categoryRows: [
          for (final row in rows)
            if (row.id == target.id)
              row.copyWith(iconKey: 'custom:$iconId')
            else
              row,
        ],
        transactionRows: await database.exportTransactions(),
        imageRows: await database.exportImages(),
      );
      await writeFile(support, categoryIconRelativePath(iconId), bytes);
    }

    test('什么都没有时全是 0', () async {
      final usage = await service.measure();
      expect(usage.totalBytes, 0);
      expect(usage.imageCount, 0);
      expect(usage.orphanFileCount, 0);
    });

    test('库里有记录的图算账单图，图标单列，无关文件不算', () async {
      await addTxWithImage('tx-1', imageBytes: 100, thumbBytes: 40);
      await useCustomIcon('icon-1', 25);
      await writeFile(support, 'unrelated.bin', 80);

      final usage = await service.measure();
      expect(usage.imageBytes, 140);
      expect(usage.imageCount, 1);
      expect(usage.categoryIconBytes, 25);
      expect(usage.mediaBytes, 165);
      expect(usage.orphanBytes, 0);
    });

    test('media 下库里查不到的文件算孤儿，不混进账单图', () async {
      await addTxWithImage('tx-1', imageBytes: 100, thumbBytes: 40);
      await makeOld(await writeFile(support, 'media/tx-9/ghost.jpg', 70));

      final usage = await service.measure();
      expect(usage.imageBytes, 140);
      expect(usage.orphanBytes, 70);
      expect(usage.orphanFileCount, 1);
      expect(usage.reclaimableBytes, 70);
    });

    test('刚落盘的文件不算孤儿，避免删掉正在保存的图', () async {
      await writeFile(support, 'media/tx-new/fresh.jpg', 50);

      final usage = await service.measure();
      expect(usage.orphanBytes, 0);
      expect(usage.orphanFileCount, 0);
    });

    test('恢复中断残留的旧 media 整个算孤儿', () async {
      await writeFile(support, '$kMediaBeforeRestoreDirName/old.jpg', 200);

      final usage = await service.measure();
      expect(usage.orphanBytes, 200);
      expect(usage.orphanFileCount, 1);
    });

    test('缓存只认自己写的：安装包与四种导出物', () async {
      await writeFile(cache, 'updates/LigyTally-1.4.21.apk', 500);
      await writeFile(cache, 'updates/LigyTally-1.4.21.apk.part', 120);
      await writeFile(cache, 'ligy-tally-20260815-101500.ligytally', 300);
      await writeFile(cache, 'ligy-tally-all.csv', 60);
      await writeFile(cache, 'ligy-categories-20260815-101500.json', 20);
      await writeFile(cache, 'image_picker_XYZ.jpg', 9999);

      final usage = await service.measure();
      expect(usage.cacheBytes, 1000);
    });

    test('清缓存删掉导出物和安装包，账单图一张不动', () async {
      await addTxWithImage('tx-1', imageBytes: 100, thumbBytes: 40);
      await writeFile(cache, 'updates/LigyTally-1.4.21.apk', 500);
      await writeFile(cache, 'ligy-tally-20260815-101500.ligytally', 300);
      final foreign = await writeFile(cache, 'image_picker_XYZ.jpg', 70);

      expect(await service.clearCache(), 800);

      final usage = await service.measure();
      expect(usage.cacheBytes, 0);
      expect(usage.imageBytes, 140);
      expect(await foreign.exists(), isTrue);
      expect(await database.exportImages(), hasLength(1));
    });

    test('清孤儿只删掉队文件，在库的图和账单都留着', () async {
      await addTxWithImage('tx-1', imageBytes: 100, thumbBytes: 40);
      await useCustomIcon('icon-1', 25);
      final ghost = await writeFile(support, 'media/tx-9/ghost.jpg', 70);
      await makeOld(ghost);

      expect(await service.clearOrphans(), 70);

      expect(await ghost.exists(), isFalse);
      final usage = await service.measure();
      expect(usage.imageBytes, 140);
      expect(usage.categoryIconBytes, 25);
      expect(usage.orphanBytes, 0);
      expect(await database.exportTransactions(), hasLength(1));
      // 图片删空后留下的空目录也要收掉，否则每次扫描都越来越慢。
      expect(await Directory(p.join(support.path, 'media/tx-9')).exists(),
          isFalse);
    });

    test('清孤儿不碰还在保护期内的新文件', () async {
      final fresh = await writeFile(support, 'media/tx-new/fresh.jpg', 50);

      expect(await service.clearOrphans(), 0);
      expect(await fresh.exists(), isTrue);
    });

    test('文件库把主库和 wal/shm/journal 算进数据', () async {
      await database.close();
      final dbFile = File(p.join(support.path, 'ligy.sqlite'));
      database = AppDatabase.forTesting(NativeDatabase(dbFile));
      service = StorageUsageService(
        database,
        ImageStorage.atRoot(support.path),
        cacheRoot: () async => cache,
      );
      // 建表后主库一定落盘，否则后面的旁路文件没有对照。
      await database.exportCategories();

      await File('${dbFile.path}-wal').writeAsBytes(List.filled(30, 1));
      await File('${dbFile.path}-shm').writeAsBytes(List.filled(10, 1));
      await File('${dbFile.path}-journal').writeAsBytes(List.filled(7, 1));

      // 统计之后再对账：SQLite 自己会重写 -wal、并在事务收尾时删掉 -journal，
      // 所以这里按「当下还在的文件」求和，不能假定三个都在。
      final usage = await service.measure();
      var expected = await dbFile.length();
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final sidecar = File('${dbFile.path}$suffix');
        if (await sidecar.exists()) expected += await sidecar.length();
      }
      expect(usage.databaseBytes, expected);
      expect(usage.databaseBytes, greaterThan(await dbFile.length()));
      final reported = await database.mainDatabaseFilePath();
      expect(reported, isNotNull);
      expect(
        await File(reported!).resolveSymbolicLinks(),
        await dbFile.resolveSymbolicLinks(),
      );
    });

    test('删账单后压缩数据库，文件真的变小', () async {
      await database.close();
      final dbFile = File(p.join(support.path, 'ligy.sqlite'));
      database = AppDatabase.forTesting(NativeDatabase(dbFile));
      service = StorageUsageService(
        database,
        ImageStorage.atRoot(support.path),
        cacheRoot: () async => cache,
      );

      final food = (await database.exportCategories()).firstWhere(
        (item) => item.name == '三餐',
      );
      final now = DateTime(2026, 8, 15).millisecondsSinceEpoch;
      for (var i = 0; i < 400; i++) {
        await database.saveTransaction(
          entry: TransactionsCompanion.insert(
            id: 'tx-$i',
            kind: 0,
            amountCents: 1200,
            categoryId: food.id,
            accountingDate: dateKey(DateTime(2026, 8, 15)),
            occurredAt: now,
            note: Value('x' * 400),
            createdAt: now,
            updatedAt: now,
          ),
          newImages: const [],
          removedImageIds: const {},
        );
      }
      for (var i = 0; i < 400; i++) {
        await database.deleteTransaction('tx-$i');
      }

      final before = await service.measure();
      final freed = await service.compactDatabase();
      final after = await service.measure();

      expect(freed, greaterThan(0));
      expect(after.databaseBytes, lessThan(before.databaseBytes));
    });

    test('内存库没有文件，压缩是安全的空操作', () async {
      expect(await service.compactDatabase(), 0);
    });
  });

  group('占用空间页', () {
    Future<void> pumpPage(WidgetTester tester, AppDatabase database) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            storageUsageProvider.overrideWith(_FixedUsage.new),
          ],
          child: MaterialApp(
            theme: buildMaterialTheme(Brightness.light),
            builder: (context, child) => FTheme(
              data: buildForuiTheme(),
              child: FToaster(child: child!),
            ),
            home: const StorageScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('合计与可清理提示都在，四类明细各占一行', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 2700);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await pumpPage(tester, database);

      expect(find.text('7.5 MB'), findsOneWidget);
      expect(find.text('其中 2 MB 可以直接清掉'), findsOneWidget);
      expect(find.text('账单图片'), findsOneWidget);
      expect(find.text('12 张，可逐张浏览和删除'), findsOneWidget);
      expect(find.text('数据库'), findsOneWidget);
      // 「缓存」在图例里也有一处，用这一行独有的副标题定位。
      expect(
        find.text('更新安装包、导出后留下的备份与 CSV 副本'),
        findsOneWidget,
      );
      expect(find.text('3 个文件不属于任何账单'), findsOneWidget);
      expect(find.text('压缩数据库'), findsOneWidget);
      expect(find.text('压缩已有图片'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });

    testWidgets('清理前先说清楚账单和图片不会没', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 2700);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await pumpPage(tester, database);
      await tester.tap(find.text('无主文件'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('所有账单和它们的图片都会保留'),
        findsOneWidget,
      );

      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  });

  group('设置页占用空间', () {
    testWidgets('有可清理时报可清理，否则报图片与数据拆分', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            storageUsageProvider.overrideWith(_FixedUsage.new),
          ],
          child: MaterialApp(
            theme: buildMaterialTheme(Brightness.light),
            builder: (context, child) => FTheme(
              data: buildForuiTheme(),
              child: FToaster(child: child!),
            ),
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(find.text('占用空间'), 300);

      expect(find.text('占用空间'), findsOneWidget);
      expect(find.text('7.5 MB'), findsOneWidget);
      expect(find.text('2 MB 可清理'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  });
}

class _FixedUsage extends StorageUsageController {
  @override
  Future<StorageUsage> build() async {
    return const StorageUsage(
      imageBytes: 5 * 1024 * 1024,
      imageCount: 12,
      categoryIconBytes: 0,
      databaseBytes: 512 * 1024,
      cacheBytes: 1024 * 1024,
      orphanBytes: 1024 * 1024,
      orphanFileCount: 3,
    );
  }
}
