import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/backup/backup_service.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/core/utils/ledger_date.dart';
import 'package:ligy_tally/features/ledger/application/ledger_service.dart';

/// 记账模板的数据约束：怎么存、怎么套用、分类变动和备份时跟不跟着走。
void main() {
  late AppDatabase database;
  late Directory dir;
  late LedgerService service;

  // 备份恢复和升级两条用例都要同时开两个库。
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('ligy_template');
    service = LedgerService(database, ImageStorage.atRoot(dir.path));
  });

  tearDown(() async {
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<CategoryEntry> expenseLeaf() async {
    final rows = await database.exportCategories();
    return rows.firstWhere((row) => row.kind == 0 && row.level == 2);
  }

  Future<List<TemplateItem>> templates() => database.watchTemplates().first;

  test('新建排到最后，编辑原地覆盖', () async {
    final category = await expenseLeaf();
    await service.saveTemplate(
      kind: 0,
      amountCents: 300000,
      categoryId: category.id,
      note: ' 房租 ',
    );
    await service.saveTemplate(
      kind: 0,
      amountCents: 5900,
      categoryId: category.id,
      note: '',
    );
    var items = await templates();
    expect(items.map((item) => item.template.amountCents), [300000, 5900]);
    expect(items.first.title, '房租', reason: '备注要去掉首尾空白');
    expect(items.last.title, category.name, reason: '没写备注时用分类名');

    await service.saveTemplate(
      existing: items.first,
      kind: 0,
      amountCents: 320000,
      categoryId: category.id,
      note: '房租',
    );
    items = await templates();
    expect(items, hasLength(2));
    expect(items.first.template.amountCents, 320000, reason: '编辑不能变成新增');
  });

  test('套用模板记入今天，撤销后删回去', () async {
    final category = await expenseLeaf();
    await service.saveTemplate(
      kind: 0,
      amountCents: 5900,
      categoryId: category.id,
      note: '话费',
    );
    final item = (await templates()).single;
    final at = DateTime(2026, 10, 11, 9, 30);

    final id = await service.recordTemplate(item, at: at);
    final rows = await database.exportTransactions();
    final row = rows.single;
    expect(row.id, id);
    expect(row.kind, 0);
    expect(row.amountCents, 5900);
    expect(row.categoryId, category.id);
    expect(row.note, '话费');
    expect(row.accountingDate, dateKey(at));
    expect(row.occurredAt, at.millisecondsSinceEpoch);
    expect(row.locationLatitude, isNull, reason: '套用模板不取位置');

    await service.undoTemplateRecord(id);
    expect(await database.exportTransactions(), isEmpty);
    expect(await templates(), hasLength(1), reason: '撤销的是账单，模板要留着');
  });

  test('删分类时模板跟着删', () async {
    await database.addCategory(id: 'pet', kind: 0, name: '宠物');
    await service.saveTemplate(
      kind: 0,
      amountCents: 12000,
      categoryId: 'pet',
      note: '猫粮',
    );
    expect(await database.deleteCategory('pet'), CategoryDeleteResult.deleted);
    expect(await templates(), isEmpty);
  });

  test('导入分类配置时，模板用到的旧分类保留并停用，模板不丢', () async {
    await database.addCategory(id: 'pet', kind: 0, name: '宠物');
    await service.saveTemplate(
      kind: 0,
      amountCents: 12000,
      categoryId: 'pet',
      note: '猫粮',
    );
    final rows = await database.exportCategories();
    await database.replaceActiveCategoryConfig([
      for (final row in rows)
        if (row.id != 'pet') row,
    ]);

    final item = (await templates()).single;
    expect(item.category.id, 'pet');
    expect(item.category.isActive, isFalse);
  });

  test('完整备份带上模板，恢复后原样落回', () async {
    final category = await expenseLeaf();
    await service.saveTemplate(
      kind: 0,
      amountCents: 300000,
      categoryId: category.id,
      note: '房租',
    );
    final zip = File('${dir.path}/backup.ligytally');
    await BackupService(
      database,
      ImageStorage.atRoot(dir.path),
    ).writeBackupTo(zip);

    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    final targetDir = await Directory.systemTemp.createTemp('ligy_tpl_dst');
    addTearDown(() => targetDir.delete(recursive: true));
    final restore = BackupService(target, ImageStorage.atRoot(targetDir.path));

    final preview = await restore.inspect(zip.path);
    expect(preview.templateCount, 1);
    await restore.restore(zip.path);

    expect(await target.exportTemplates(), await database.exportTemplates());
  });

  test('从 v4 的库升级会建出模板表', () async {
    // 只有新表、没有改老表；但升级路径漏了 createTable 的话，老用户一打开
    // 模板入口就是「no such table」，新装用户却一切正常，很难发现。
    final file = File('${dir.path}/legacy.sqlite');
    final legacy = AppDatabase.forTesting(NativeDatabase(file));
    await legacy.exportCategories();
    await legacy.customStatement('DROP TABLE tally_templates');
    await legacy.customStatement('PRAGMA user_version = 4');
    await legacy.close();

    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(upgraded.close);
    final category = (await upgraded.exportCategories()).firstWhere(
      (row) => row.kind == 0,
    );
    await upgraded.saveTemplate(
      newId: 't1',
      kind: 0,
      amountCents: 100,
      categoryId: category.id,
      note: '',
    );
    expect(await upgraded.exportTemplates(), hasLength(1));
  });
}
