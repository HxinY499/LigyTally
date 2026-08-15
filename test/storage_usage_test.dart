import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/core/storage/storage_usage.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/features/settings/presentation/settings_screen.dart';
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

  group('StorageUsageService', () {
    late Directory dir;
    late AppDatabase database;
    late StorageUsageService service;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ligy_storage_usage');
      database = AppDatabase.forTesting(NativeDatabase.memory());
      service = StorageUsageService(database, ImageStorage.atRoot(dir.path));
    });

    tearDown(() async {
      await database.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<void> writeFile(String relative, int bytes) async {
      final file = File(p.join(dir.path, relative));
      await file.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(bytes, 1), flush: true);
    }

    test('没有 media 目录时图片为 0，内存库数据为 0', () async {
      final usage = await service.measure();
      expect(usage.imageBytes, 0);
      expect(usage.categoryIconBytes, 0);
      expect(usage.databaseBytes, 0);
      expect(usage.totalBytes, 0);
    });

    test('账单图和分类图标分开，support 根下的其它文件不算', () async {
      await writeFile('media/tx-1/a.jpg', 100);
      await writeFile('media/tx-1/a_thumb.jpg', 40);
      await writeFile('media/category_icons/icon.jpg', 25);
      await writeFile('unrelated.bin', 80);
      await writeFile('.media_before_restore/old.jpg', 200);

      final usage = await service.measure();
      expect(usage.imageBytes, 140);
      expect(usage.categoryIconBytes, 25);
      expect(usage.mediaBytes, 165);
      expect(usage.databaseBytes, 0);
      expect(usage.totalBytes, 165);
    });

    test('文件库把主库和 wal/shm/journal 算进数据', () async {
      await database.close();
      final dbFile = File(p.join(dir.path, 'ligy.sqlite'));
      database = AppDatabase.forTesting(NativeDatabase(dbFile));
      service = StorageUsageService(database, ImageStorage.atRoot(dir.path));
      // 建表后主库一定落盘，否则后面的旁路文件没有对照。
      await database.exportCategories();

      await File('${dbFile.path}-wal').writeAsBytes(List.filled(30, 1));
      await File('${dbFile.path}-shm').writeAsBytes(List.filled(10, 1));
      await File('${dbFile.path}-journal').writeAsBytes(List.filled(7, 1));

      final usage = await service.measure();
      var expected = await dbFile.length();
      for (final suffix in ['-wal', '-shm', '-journal']) {
        expected += await File('${dbFile.path}$suffix').length();
      }
      expect(usage.databaseBytes, expected);
      final reported = await database.mainDatabaseFilePath();
      expect(reported, isNotNull);
      expect(
        await File(reported!).resolveSymbolicLinks(),
        await dbFile.resolveSymbolicLinks(),
      );
    });
  });

  group('设置页占用空间', () {
    testWidgets('数据分组展示合计和图片/数据拆分', (tester) async {
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
      expect(find.text('5.5 MB'), findsOneWidget);
      expect(find.text('图片 5 MB · 数据 512 KB'), findsOneWidget);

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
      categoryIconBytes: 0,
      databaseBytes: 512 * 1024,
    );
  }
}
