import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/backup/backup_service.dart';
import 'package:ligy_tally/core/category_config/category_config_service.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/core/utils/category_icons.dart';

/// 分类自定义图标的「可迁移」约束。
///
/// 图标从「一个内置 key」变成「一张用户上传的图片」之后，
/// 数据迁移多了一件必须做对的事：**图片得跟着走**。
/// 只搬 icon_key 不搬文件，换机后就是一片兜底图标——数据看着在，实际没了。
void main() {
  group('iconKey 的自定义图片编码', () {
    test('custom: 前缀与内置 key 不会互相误判', () {
      // 内置 key 全是 [a-z_]，冒号在其中不可能出现，两者天然隔离。
      // 这条守住「加前缀」这个决定：不用新开一列，老版本读到也只是回落。
      for (final key in categoryIconChoices) {
        expect(isCustomCategoryIcon(key), isFalse, reason: '$key 被误判为自定义');
        expect(customCategoryIconId(key), isNull);
      }
      final key = customCategoryIconKey('abc-123');
      expect(isCustomCategoryIcon(key), isTrue);
      expect(customCategoryIconId(key), 'abc-123');
    });

    test('非法 id 一律拒绝——它会被拼进文件名和备份包内路径', () {
      // 这不是洁癖：id 来自导入的备份文件，是外部输入。
      // 放行 `/` 或 `..` 等于允许一个精心构造的备份往目录外写文件。
      expect(isValidCustomIconId('11111111-2222-3333-4444-555555555555'), true);
      expect(isValidCustomIconId('../../etc/passwd'), isFalse);
      expect(isValidCustomIconId('a/b'), isFalse);
      expect(isValidCustomIconId(''), isFalse);
      expect(isValidCustomIconId('a' * 65), isFalse);
      // 前缀在但 id 非法时，customIconIdsOf 不该把它当成要打包的文件。
      expect(customIconIdsOf([customCategoryIconKey('../x')]), isEmpty);
    });

    test('同一张图被多个分类共用时只算一次', () {
      // 用户很可能给「餐饮」和它的子分类「三餐」选同一张图。
      // 不去重的话，备份 zip 里会出现两个同名条目。
      final key = customCategoryIconKey('same-id');
      expect(customIconIdsOf([key, key, 'restaurant']), {'same-id'});
    });
  });

  group('分类配置带图片迁移', () {
    /// 建一个「支出有张自定义图标、收入是内置图标」的库，并把图片写进磁盘。
    Future<
      ({
        AppDatabase database,
        ImageStorage storage,
        Directory dir,
        String iconId,
      })
    >
    setUpWithCustomIcon() async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final dir = await Directory.systemTemp.createTemp('ligy_icon_migration');
      final storage = ImageStorage.atRoot(dir.path);
      const iconId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      // 内容随便，但必须是可辨认的字节：往返后要逐字节比对。
      await storage.writeCategoryIcon(
        iconId: iconId,
        bytes: List<int>.generate(64, (i) => i),
      );
      await database.addCategory(
        id: 'with-image',
        kind: 0,
        name: '手作',
        iconKey: customCategoryIconKey(iconId),
      );
      return (database: database, storage: storage, dir: dir, iconId: iconId);
    }

    test('导出的 JSON 内嵌图片，导入后图片落盘且换了新 id', () async {
      final source = await setUpWithCustomIcon();
      addTearDown(source.database.close);
      addTearDown(() => source.dir.delete(recursive: true));

      final exported = File('${source.dir.path}/exported.json');
      await CategoryConfigService(
        source.database,
        source.storage,
      ).writeConfigTo(exported);

      final config = (jsonDecode(await exported.readAsString()) as Map)
          .cast<String, Object?>();
      expect(config['version'], CategoryConfigService.formatVersion);
      final expense = (config['expense'] as List).cast<Map<String, Object?>>();
      final custom = expense.singleWhere((n) => n['name'] == '手作');
      expect(custom['icon'], customCategoryIconKey(source.iconId));
      expect(custom['iconImage'], isA<String>());
      final builtin = expense.firstWhere((n) => n['name'] == '餐饮');
      expect(
        builtin.containsKey('iconImage'),
        isFalse,
        reason: '内置图标不该塞图片数据，否则配置文件白白变大',
      );

      // 换一台「设备」导入：新库、新目录。
      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      final targetDir = await Directory.systemTemp.createTemp('ligy_icon_dst');
      addTearDown(() => targetDir.delete(recursive: true));
      final targetStorage = ImageStorage.atRoot(targetDir.path);

      final service = CategoryConfigService(target, targetStorage);
      expect((await service.inspect(exported.path)).iconImageCount, 1);
      await service.importAndReplace(exported.path);

      final imported = (await target.exportCategories()).singleWhere(
        (row) => row.name == '手作',
      );
      final newId = customCategoryIconId(imported.iconKey);
      expect(newId, isNotNull, reason: '导入后仍应是自定义图标');
      // id 必须换：导入方本地可能已经有同 id 的文件（比如把自己导出的配置
      // 又导回来），沿用原 id 会互相覆盖。
      expect(newId, isNot(source.iconId));
      final restored = await targetStorage.resolve(
        categoryIconRelativePath(newId!),
      );
      expect(await restored.exists(), isTrue, reason: '图片必须真的落盘');
      expect(
        await restored.readAsBytes(),
        List<int>.generate(64, (i) => i),
        reason: '图片内容不能在往返中变形',
      );
    });

    test('v1 老配置照旧能导入，不会凭空造出图片', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final dir = await Directory.systemTemp.createTemp('ligy_icon_v1');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/v1.json');
      await file.writeAsString(
        jsonEncode({
          'format': 'ligy-tally-categories',
          'version': 1,
          'expense': [
            {'name': '通勤', 'icon': 'transport', 'children': <Object>[]},
          ],
          'income': [
            {'name': '薪资', 'icon': 'salary', 'children': <Object>[]},
          ],
        }),
      );

      final service = CategoryConfigService(
        database,
        ImageStorage.atRoot(dir.path),
      );
      final preview = await service.inspect(file.path);
      expect(preview.parentCount, 2);
      expect(preview.iconImageCount, 0);
      await service.importAndReplace(file.path);
      final active = (await database.exportCategories()).where(
        (row) => row.isActive,
      );
      expect(active.map((row) => row.iconKey), containsAll(['transport']));
    });

    test('声明了 custom: 但没带图片的配置回落到默认图标，而不是指向空文件', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final dir = await Directory.systemTemp.createTemp('ligy_icon_missing');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/broken.json');
      // 手改过的配置、或从别处半路截断的文件都会长这样。
      await file.writeAsString(
        jsonEncode({
          'format': 'ligy-tally-categories',
          'version': 2,
          'expense': [
            {'name': '手作', 'icon': 'custom:whatever', 'children': <Object>[]},
          ],
          'income': [
            {'name': '薪资', 'icon': 'salary', 'children': <Object>[]},
          ],
        }),
      );

      final service = CategoryConfigService(
        database,
        ImageStorage.atRoot(dir.path),
      );
      await service.importAndReplace(file.path);
      final imported = (await database.exportCategories()).singleWhere(
        (row) => row.name == '手作',
      );
      // 留着 custom: 前缀会让这个分类永远显示不出图标且无法自愈。
      expect(isCustomCategoryIcon(imported.iconKey), isFalse);
      expect(imported.iconKey, 'other');
    });

    test('版本比应用还新时，报「请升级」而不是「文件坏了」', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final dir = await Directory.systemTemp.createTemp('ligy_icon_future');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/future.json');
      await file.writeAsString(
        jsonEncode({
          'format': 'ligy-tally-categories',
          'version': CategoryConfigService.formatVersion + 1,
          'expense': <Object>[],
          'income': <Object>[],
        }),
      );

      final service = CategoryConfigService(
        database,
        ImageStorage.atRoot(dir.path),
      );
      await expectLater(
        service.inspect(file.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('升级'),
          ),
        ),
      );
    });
  });

  group('完整备份带图标迁移', () {
    test('图标文件进包、恢复后原样落回，manifest 计数正确', () async {
      final source = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(source.close);
      final sourceDir = await Directory.systemTemp.createTemp('ligy_bk_src');
      addTearDown(() => sourceDir.delete(recursive: true));
      final sourceStorage = ImageStorage.atRoot(sourceDir.path);
      const iconId = 'ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb';
      final bytes = List<int>.generate(48, (i) => 255 - i);
      await sourceStorage.writeCategoryIcon(iconId: iconId, bytes: bytes);
      await source.addCategory(
        id: 'icon-holder',
        kind: 0,
        name: '手作',
        iconKey: customCategoryIconKey(iconId),
      );

      final zip = File('${sourceDir.path}/backup.ligytally');
      await BackupService(source, sourceStorage).writeBackupTo(zip);

      // 恢复到一台「新设备」：新库、新的 support 根目录，图片必须自己长出来。
      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      final targetDir = await Directory.systemTemp.createTemp('ligy_bk_dst');
      addTearDown(() => targetDir.delete(recursive: true));
      final targetStorage = ImageStorage.atRoot(targetDir.path);
      final service = BackupService(target, targetStorage);

      final preview = await service.inspect(zip.path);
      expect(preview.categoryIconCount, 1);
      await service.restore(zip.path);

      final restored = (await target.exportCategories()).singleWhere(
        (row) => row.id == 'icon-holder',
      );
      // 完整备份是「换手机、原样搬」，所以这里和分类配置相反：id 不能变。
      // 整个库是逐行照搬的，改 id 就对不上 transactions 的外键了。
      expect(restored.iconKey, customCategoryIconKey(iconId));
      final file = await targetStorage.resolve(
        categoryIconRelativePath(iconId),
      );
      expect(await file.exists(), isTrue, reason: '恢复后图标文件必须存在');
      expect(await file.readAsBytes(), bytes);
    });

    test('v3 的老备份仍能恢复', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final dir = await Directory.systemTemp.createTemp('ligy_bk_v3');
      addTearDown(() => dir.delete(recursive: true));

      // v3 里 icon_key 不可能带 custom: 前缀，所以「包里没有图标文件」
      // 对它来说就是正确状态，不需要任何兼容分支——这条守住这个判断。
      final rows = await database.exportCategories();
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'format': 'ligy-tally-backup',
              'version': 3,
              'createdAt': DateTime.now().toIso8601String(),
              'categoryCount': rows.length,
              'transactionCount': 0,
              'imageCount': 0,
            }),
          ),
        )
        ..add(
          ArchiveFile.string(
            'data.json',
            jsonEncode({
              'categories': rows.map((row) => row.toJson()).toList(),
              'transactions': <Object>[],
              'images': <Object>[],
            }),
          ),
        );
      final zip = File('${dir.path}/legacy.ligytally');
      await zip.writeAsBytes(ZipEncoder().encodeBytes(archive), flush: true);

      final service = BackupService(database, ImageStorage.atRoot(dir.path));
      final preview = await service.inspect(zip.path);
      expect(preview.categoryIconCount, 0, reason: 'v3 没有这个字段，应缺省为 0');
      await service.restore(zip.path);
      expect(await database.exportCategories(), hasLength(rows.length));
    });

    test('导出时图标文件丢了要报错，不能悄悄少打一张', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final dir = await Directory.systemTemp.createTemp('ligy_bk_missing');
      addTearDown(() => dir.delete(recursive: true));
      // 建了引用但没写文件：模拟用户手动清了 app 数据、或同步工具漏了一个。
      await database.addCategory(
        id: 'dangling',
        kind: 0,
        name: '手作',
        iconKey: customCategoryIconKey('00000000-0000-0000-0000-000000000000'),
      );

      // 备份的承诺是「一字不差」。静默跳过会让用户到换机那天才发现图没了，
      // 那时源设备可能已经被清空，没有第二次机会。
      await expectLater(
        BackupService(
          database,
          ImageStorage.atRoot(dir.path),
        ).writeBackupTo(File('${dir.path}/x.ligytally')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('分类图标'),
          ),
        ),
      );
    });
  });

  group('图标文件的回收', () {
    test('没人引用的图标文件会被清掉，还在用的留着', () async {
      final dir = await Directory.systemTemp.createTemp('ligy_icon_prune');
      addTearDown(() => dir.delete(recursive: true));
      final storage = ImageStorage.atRoot(dir.path);
      await storage.writeCategoryIcon(iconId: 'keep-me', bytes: [1, 2, 3]);
      await storage.writeCategoryIcon(iconId: 'drop-me', bytes: [4, 5, 6]);

      // 用「扫目录对账」而不是「删分类时顺手删图」：需要删文件的路径有四条
      // （删分类、删一级连带子分类、换回内置图标、换成另一张图），
      // 逐条去记迟早漏一处，而漏掉的文件会一直躺在之后每一个备份包里。
      await storage.pruneCategoryIcons({'keep-me'});

      expect(
        await (await storage.resolve(
          categoryIconRelativePath('keep-me'),
        )).exists(),
        isTrue,
      );
      expect(
        await (await storage.resolve(
          categoryIconRelativePath('drop-me'),
        )).exists(),
        isFalse,
      );
    });
  });
}
