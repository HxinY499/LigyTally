import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_ai_tools/flutter_ai_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/location/place_fix.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/core/utils/category_icons.dart';
import 'package:ligy_tally/features/ai/application/ai_approval.dart';
import 'package:ligy_tally/features/ai/application/ai_chat_session.dart';
import 'package:ligy_tally/features/ai/application/ai_settings.dart';
import 'package:ligy_tally/features/ai/application/ledger_tools.dart';
import 'package:ligy_tally/features/ledger/application/ledger_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase database;
  late Directory mediaRoot;
  late LedgerToolService tools;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    mediaRoot = Directory.systemTemp.createTempSync('ligy_ai_tools_');
    tools = LedgerToolService(
      database,
      LedgerService(database, ImageStorage.atRoot(mediaRoot.path)),
      statsExcludedIds: const {'expense_housing'},
    );
    await database.exportCategories();
  });

  tearDown(() async {
    await database.close();
    mediaRoot.deleteSync(recursive: true);
  });

  test('汇总、二级分类下钻与统计排除口径一致', () async {
    await _saveFood(tools);
    // 同一一级分类下再记一笔直接挂在「餐饮」根分类上的账单，验证「未细分」归集
    await tools.ledgerService.save(
      kind: 0,
      amountCents: 1200,
      categoryId: 'expense_food',
      accountingDate: DateTime(2026, 10, 19),
      occurredAt: DateTime(2026, 10, 19, 8),
      note: '买早餐',
      pendingImages: const <XFile>[],
      existingImages: const <TransactionImageEntry>[],
      removedImageIds: const <String>{},
    );
    // 记一笔房租（用于验证统计排除口径）
    await tools.ledgerService.save(
      kind: 0,
      amountCents: 300000,
      categoryId: 'expense_housing_rent',
      accountingDate: DateTime(2026, 10, 05),
      occurredAt: DateTime(2026, 10, 05, 10),
      note: '10月房租',
      pendingImages: const <XFile>[],
      existingImages: const <TransactionImageEntry>[],
      removedImageIds: const <String>{},
    );

    final allSummary = await tools.summary({
      'from': '2026-10-01',
      'to': '2026-10-31',
    });
    expect(allSummary['expenseCents'], 304000);
    expect(allSummary['scope'], 'all_categories');

    final excludedSummary = await tools.summary({
      'from': '2026-10-01',
      'to': '2026-10-31',
      'useStatsExclusion': true,
    });
    expect(excludedSummary['expenseCents'], 4000);
    expect(excludedSummary['scope'], 'excluded_categories');
    expect(excludedSummary['excludedCategories'], contains('居住'));

    final breakdown = await tools.categoryBreakdown({
      'from': '2026-10-01',
      'to': '2026-10-31',
      'kind': 'expense',
      'useStatsExclusion': true,
    });
    final categories = breakdown['categories']! as List<Object?>;
    expect(categories, hasLength(1));
    final food = categories.single! as Map<String, Object?>;
    expect(food['categoryId'], 'expense_food');
    expect(food['totalCents'], 4000);
    final subs = food['subcategories']! as List<Object?>;
    expect(subs, hasLength(2));

    // 显式传 parentCategoryId 下钻二级分类
    final subDrill = await tools.categoryBreakdown({
      'from': '2026-10-01',
      'to': '2026-10-31',
      'kind': 'expense',
      'parentCategoryId': 'expense_food',
    });
    expect(subDrill['totalCents'], 4000);
    final subRows = subDrill['categories']! as List<Object?>;
    expect(subRows, hasLength(2));
    expect((subRows[0]! as Map)['name'], '三餐');
    expect((subRows[1]! as Map)['name'], '餐饮（未细分）');
  });

  test('趋势与两期环比工具返回准确序列及分类涨跌', () async {
    // 9 月：三餐 2000，打车 5000
    await tools.ledgerService.save(
      kind: 0,
      amountCents: 2000,
      categoryId: 'expense_food_meals',
      accountingDate: DateTime(2026, 9, 10),
      occurredAt: DateTime(2026, 9, 10, 12),
      note: '面条',
      pendingImages: const [],
      existingImages: const [],
      removedImageIds: const {},
    );
    await tools.ledgerService.save(
      kind: 0,
      amountCents: 5000,
      categoryId: 'expense_transport_taxi',
      accountingDate: DateTime(2026, 9, 12),
      occurredAt: DateTime(2026, 9, 12, 20),
      note: '打车',
      pendingImages: const [],
      existingImages: const [],
      removedImageIds: const {},
    );
    // 10 月：三餐 8000（上涨 6000），打车归零（减少 5000）
    await tools.ledgerService.save(
      kind: 0,
      amountCents: 8000,
      categoryId: 'expense_food_meals',
      accountingDate: DateTime(2026, 10, 10),
      occurredAt: DateTime(2026, 10, 10, 19),
      note: '聚餐',
      pendingImages: const [],
      existingImages: const [],
      removedImageIds: const {},
    );

    final trend = await tools.spendingTrend({
      'from': '2026-08-01',
      'to': '2026-10-31',
      'granularity': 'month',
    });
    final points = trend['points']! as List<Object?>;
    // 8、9、10 三个月齐全，8 月补 0
    expect(points, hasLength(3));
    expect((points[0]! as Map)['expenseCents'], 0);
    expect((points[1]! as Map)['expenseCents'], 7000);
    expect((points[2]! as Map)['expenseCents'], 8000);

    final cmp = await tools.comparePeriods({
      'from': '2026-10-01',
      'to': '2026-10-31',
      'compareFrom': '2026-09-01',
      'compareTo': '2026-09-30',
      'kind': 'expense',
    });
    final sum = cmp['summary']! as Map<String, Object?>;
    expect(sum['currentCents'], 8000);
    expect(sum['comparisonCents'], 7000);
    expect(sum['deltaCents'], 1000);

    final increased = cmp['increased']! as List<Object?>;
    final decreased = cmp['decreased']! as List<Object?>;
    expect((increased.single! as Map)['name'], '餐饮');
    expect((increased.single! as Map)['deltaCents'], 6000);
    expect((decreased.single! as Map)['name'], '交通');
    expect((decreased.single! as Map)['status'], 'cleared');

    // 重叠区间必须拦截
    await expectLater(
      tools.comparePeriods({
        'from': '2026-10-01',
        'to': '2026-10-31',
        'compareFrom': '2026-10-15',
        'compareTo': '2026-11-15',
      }),
      throwsArgumentError,
    );
  });

  test('搜索支持地点匹配、金额区间、排序方式及截断前总额统计', () async {
    await tools.ledgerService.save(
      kind: 0,
      amountCents: 68000,
      categoryId: 'expense_shopping',
      accountingDate: DateTime(2026, 10, 12),
      occurredAt: DateTime(2026, 10, 12, 15, 20),
      note: '买牛奶牛排',
      place: PlaceFix(
        latitude: 31.2,
        longitude: 121.4,
        capturedAt: DateTime(2026, 10, 12, 15, 20),
        name: '山姆会员商店',
      ),
      pendingImages: const [],
      existingImages: const [],
      removedImageIds: const {},
    );
    await tools.ledgerService.save(
      kind: 0,
      amountCents: 2800,
      categoryId: 'expense_food_meals',
      accountingDate: DateTime(2026, 10, 18),
      occurredAt: DateTime(2026, 10, 18, 12, 05),
      note: '午饭',
      place: PlaceFix(
        latitude: 31.2,
        longitude: 121.4,
        capturedAt: DateTime(2026, 10, 18, 12, 05),
        name: '万象城',
      ),
      pendingImages: const [],
      existingImages: const [],
      removedImageIds: const {},
    );
    await tools.ledgerService.save(
      kind: 0,
      amountCents: 120000,
      categoryId: 'expense_shopping_digital',
      accountingDate: DateTime(2026, 10, 02),
      occurredAt: DateTime(2026, 10, 02, 10, 00),
      note: '耳机',
      pendingImages: const [],
      existingImages: const [],
      removedImageIds: const {},
    );

    // 1. 地点 + 备注分词检索
    final byPlace = await tools.searchTransactions({
      'from': '2026-10-01',
      'to': '2026-10-31',
      'query': '山姆 牛排',
    });
    final placeRows = byPlace['transactions']! as List<Object?>;
    expect(placeRows, hasLength(1));
    final samRow = placeRows.single! as Map<String, Object?>;
    expect(samRow['location'], '山姆会员商店');
    expect(samRow['time'], '15:20');

    // 2. 金额区间 + 按金额降序 + 截断前全量合计
    final bigBills = await tools.searchTransactions({
      'from': '2026-10-01',
      'to': '2026-10-31',
      'minAmountCents': 50000,
      'sortBy': 'amount_desc',
      'limit': 1,
    });
    expect(bigBills['totalMatches'], 2);
    expect(bigBills['returned'], 1);
    expect(bigBills['truncated'], isTrue);
    // 即使只返回 1 条，matchedExpenseCents 仍统计全部 2 条（120000 + 68000）
    expect(bigBills['matchedExpenseCents'], 188000);
    final topRow =
        (bigBills['transactions']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(topRow['amountCents'], 120000);
  });

  test('批量记账确认摘要、就地微调落库与部分勾选剔除', () async {
    final call = const ToolCallPart(
      toolCallId: 'batch-1',
      toolName: 'save_transactions',
      args: {
        'items': [
          {
            'kind': 'expense',
            'amountCents': 2800,
            'categoryId': 'expense_food_meals',
            'accountingDate': '2026-10-19',
            'note': '午饭',
          },
          {
            'kind': 'expense',
            'amountCents': 1800,
            'categoryId': 'expense_transport_taxi',
            'accountingDate': '2026-10-19',
            'note': '打车',
          },
        ],
      },
      state: ToolCallState.inputAvailable,
    );

    final request = await tools.describe(call);
    expect(request, isNotNull);
    expect(request!.isBatch, isTrue);
    expect(request.title, '批量记账');
    expect(request.bills, hasLength(2));

    // 模拟用户在确认框中：把第 1 笔改成 32 元，取消勾选第 2 笔
    final editedFirst = request.bills[0].copyWith(amountCents: 3200);
    final result = await tools.commitSavedBills(
      [editedFirst],
      proposed: request.bills,
    );
    expect(result['ok'], isTrue);
    expect(result['proposedCount'], 2);
    expect(result['savedCount'], 1);
    expect(result['skippedByUserCount'], 1);
    expect(result['modifiedByUser'], isTrue);
    expect(result['amountCents'], 3200);

    final rows = await database.exportTransactions();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'ai-batch-1-0');
    expect(rows.single.amountCents, 3200);
  });

  test('同一个 toolCallId 重试不会写出两笔账', () async {
    final args = {
      'items': [
        {
          'kind': 'expense',
          'amountCents': 3550,
          'categoryId': 'expense_transport_taxi',
          'accountingDate': '2026-10-18',
          'note': '打车回家',
        },
      ],
    };
    await tools.saveTransactions(args, toolCallId: 'call-retry');
    await tools.saveTransactions(args, toolCallId: 'call-retry');

    final rows = await database.exportTransactions();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'ai-call-retry');
  });

  test('删除前校验 id，删除后账与图片目录都由 LedgerService 处理', () async {
    final id = await _saveFood(tools);
    final request = await tools.describe(
      ToolCallPart(
        toolCallId: 'call-2',
        toolName: 'delete_transactions',
        args: {
          'ids': [id],
        },
        state: ToolCallState.inputAvailable,
      ),
    );
    expect(request, isNotNull);
    expect(request!.confirmLabel, '确认删除');
    expect(request.destructive, isTrue);
    expect(request.message, contains('¥28.00'));

    final result = await tools.deleteTransactions({
      'ids': [id],
    });
    expect(result['deletedCount'], 1);
    expect(await database.exportTransactions(), isEmpty);
  });

  test('修改支持弹窗二次微调，且保留图片和位置', () async {
    final id = await tools.ledgerService.save(
      kind: 0,
      amountCents: 2800,
      categoryId: 'expense_food_meals',
      accountingDate: DateTime(2026, 10, 18),
      occurredAt: DateTime(2026, 10, 18, 12, 30),
      note: '午饭',
      place: PlaceFix(
        latitude: 31.2,
        longitude: 121.5,
        capturedAt: DateTime(2026, 10, 18, 12, 30),
        name: '公司',
      ),
      pendingImages: const <XFile>[],
      existingImages: const <TransactionImageEntry>[],
      removedImageIds: const <String>{},
    );
    await database
        .into(database.transactionImages)
        .insert(
          TransactionImagesCompanion.insert(
            id: 'img-1',
            transactionId: id,
            imagePath: 'x/a.jpg',
            thumbnailPath: 'x/a_thumb.jpg',
            sizeBytes: 10,
            createdAt: 1,
          ),
        );

    final request = await tools.describe(
      ToolCallPart(
        toolCallId: 'call-edit',
        toolName: 'update_transaction',
        args: {'id': id, 'amountCents': 3000},
        state: ToolCallState.inputAvailable,
      ),
    );
    expect(request, isNotNull);
    expect(request!.confirmLabel, '确认修改');
    expect(request.title, '修改这笔');
    expect(request.bill?.amountCents, 3000);
    expect(request.changes.single.label, '金额');
    expect(request.message, contains('位置保留'));
    expect(request.message, contains('图片保留'));

    // 用户在改账确认框里把 30 元进一步改成了 35 元并改了备注
    final userTweaked = request.bill!.copyWith(
      amountCents: 3500,
      note: '午饭加饮料',
    );
    final result = await tools.commitUpdatedBill(
      item: request.originalItem!,
      confirmed: userTweaked,
      proposed: request.bill!,
    );
    expect(result['changed'], isTrue);
    expect(result['modifiedByUser'], isTrue);
    expect(result['amountCents'], 3500);
    expect(result['note'], '午饭加饮料');

    final row = (await database.exportTransactions()).single;
    expect(row.amountCents, 3500);
    expect(row.note, '午饭加饮料');
    expect(row.locationLatitude, 31.2);
    expect(row.locationName, '公司');
    expect(await database.imagesFor(id), hasLength(1));
  });

  test('没改动、缺字段、收支类型不匹配时不落库', () async {
    final id = await _saveFood(tools);

    final same = await tools.describe(
      ToolCallPart(
        toolCallId: 'call-same',
        toolName: 'update_transaction',
        args: {'id': id, 'amountCents': 2800},
        state: ToolCallState.inputAvailable,
      ),
    );
    expect(same, isNull);
    final unchanged = await tools.updateTransaction({
      'id': id,
      'amountCents': 2800,
    });
    expect(unchanged['changed'], isFalse);

    await expectLater(tools.updateTransaction({'id': id}), throwsArgumentError);
    await expectLater(
      tools.updateTransaction({'id': id, 'kind': 'income'}),
      throwsArgumentError,
    );
    await expectLater(
      tools.updateTransaction({'id': 'missing', 'amountCents': 100}),
      throwsStateError,
    );
    expect((await database.exportTransactions()).single.amountCents, 2800);
  });

  test('分类收支类型不匹配时拒绝写入', () async {
    await expectLater(
      tools.saveTransactions({
        'items': [
          {
            'kind': 'expense',
            'amountCents': 100,
            'categoryId': 'income_salary',
            'accountingDate': '2026-10-19',
          },
        ],
      }),
      throwsArgumentError,
    );
  });

  group('分类增删查改工具', () {
    test('list_categories 返回层级树、引用计数、停用过滤与 canDelete', () async {
      await _saveFood(tools);
      await tools.ledgerService.saveTemplate(
        kind: 0,
        amountCents: 250000,
        categoryId: 'expense_housing_rent',
        note: '房租模板',
      );
      await database.setCategoryActive('expense_pet', false);

      final full = await tools.listCategories({'kind': 'expense'});
      expect(full['inactiveCount'], greaterThan(0));
      final roots = full['categories']! as List<Object?>;
      final food = roots
          .cast<Map<String, Object?>>()
          .singleWhere((c) => c['id'] == 'expense_food');
      expect(food['totalTransactionCount'], 1);
      expect(food['canDelete'], isFalse);

      final housing = roots
          .cast<Map<String, Object?>>()
          .singleWhere((c) => c['id'] == 'expense_housing');
      expect(housing['templateCount'], 1);
      expect(housing['canDelete'], isTrue);

      final pet = roots
          .cast<Map<String, Object?>>()
          .singleWhere((c) => c['id'] == 'expense_pet');
      expect(pet['isActive'], isFalse);

      final activeOnly = await tools.listCategories({
        'kind': 'expense',
        'includeInactive': false,
      });
      final activeIds = (activeOnly['categories']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map((c) => c['id'])
          .toSet();
      expect(activeIds, isNot(contains('expense_pet')));
    });

    test('create_categories 支持一级带二级原子创建、二级挂载、幂等与各项边界拦截', () async {
      final nodes = await tools.readCreateCategories(
        {
          'items': [
            {
              'kind': 'expense',
              'name': '养车',
              'iconKey': 'car',
              'children': [
                {'name': '加油', 'iconKey': 'fuel'},
                {'name': '停车', 'iconKey': 'parking'},
              ],
            },
            {
              'kind': 'expense',
              'name': '奶茶',
              'iconKey': 'milk_tea',
              'parentId': 'expense_food',
            },
          ],
        },
        toolCallId: 'call-cat-1',
      );
      final req = tools.buildCreateCategoriesApprovalRequest(nodes);
      expect(req.title, '新建 4 个分类');
      expect(req.categories, hasLength(4));

      final created = await tools.commitCreatedCategories(nodes);
      expect(created['createdCount'], 4);
      // 相同节点重跑幂等，不会因主键冲突报错或重复插入
      final retried = await tools.commitCreatedCategories(nodes);
      expect(retried['createdCount'], 4);

      final all = await database.exportCategories();
      final car = all.singleWhere((c) => c.name == '养车');
      expect(car.level, 1);
      expect(car.iconKey, 'car');
      final fuel = all.singleWhere((c) => c.name == '加油');
      expect(fuel.parentId, car.id);
      expect(fuel.level, 2);
      final milkTea = all.singleWhere((c) => c.name == '奶茶');
      expect(milkTea.parentId, 'expense_food');

      // 新分类立刻可用于记账
      final saved = await tools.saveTransactions({
        'items': [
          {
            'kind': 'expense',
            'amountCents': 1800,
            'categoryId': milkTea.id,
            'accountingDate': '2026-10-20',
            'note': '伯牙绝弦',
          },
        ],
      });
      expect(saved['categoryName'], '奶茶');

      // 拦截：禁止三级分类、禁止非法/custom 图标、禁止超长名称
      await expectLater(
        tools.createCategories({
          'items': [
            {
              'kind': 'expense',
              'name': '三级非法',
              'parentId': milkTea.id,
            },
          ],
        }),
        throwsArgumentError,
      );
      await expectLater(
        tools.createCategories({
          'items': [
            {
              'kind': 'expense',
              'name': '伪造自定义图',
              'iconKey': 'custom:11111111-2222-3333-4444-555555555555',
            },
          ],
        }),
        throwsArgumentError,
      );
      await expectLater(
        tools.createCategories({
          'items': [
            {
              'kind': 'expense',
              'name': '一二三四五六七八九十一二三',
            },
          ],
        }),
        throwsArgumentError,
      );

      // 停用「宠物」后尝试新建同名一级分类，错误提示应带出已停用分类 id 引导启用
      await database.setCategoryActive('expense_pet', false);
      await expectLater(
        tools.createCategories({
          'items': [
            {'kind': 'expense', 'name': '宠物'},
          ],
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('已停用'), contains('expense_pet')),
          ),
        ),
      );
      // 禁止往已停用的父分类下加子分类
      await expectLater(
        tools.createCategories({
          'items': [
            {
              'kind': 'expense',
              'name': '猫砂',
              'parentId': 'expense_pet',
            },
          ],
        }),
        throwsArgumentError,
      );
    });

    test('update_category 支持改名、换图标、级联启停、防清空根分类与孤儿图标回收', () async {
      // 无变化时不生成确认请求
      final noOp = await tools.describe(
        const ToolCallPart(
          toolCallId: 'c-noop',
          toolName: 'update_category',
          args: {'id': 'expense_food_meals', 'name': '三餐'},
          state: ToolCallState.inputAvailable,
        ),
      );
      expect(noOp, isNull);

      // 停用一级分类「宠物」：预览提示连带停用子分类
      final disableReq = await tools.describe(
        const ToolCallPart(
          toolCallId: 'c-disable',
          toolName: 'update_category',
          args: {'id': 'expense_pet', 'isActive': false},
          state: ToolCallState.inputAvailable,
        ),
      );
      expect(disableReq, isNotNull);
      expect(disableReq!.footnote, contains('子分类也会一并停用'));
      final disabled = await tools.updateCategory({
        'id': 'expense_pet',
        'isActive': false,
      });
      expect(disabled['isActive'], isFalse);
      expect(disabled['cascadeDeactivatedCount'], 3);

      // 重新启用子分类「宠物食品」：连带把父分类「宠物」一起启用
      final reEnable = await tools.updateCategory({
        'id': 'expense_pet_food',
        'isActive': true,
      });
      expect(reEnable['isActive'], isTrue);
      expect(reEnable['reactivatedParentName'], '宠物');
      final petAfter = (await database.exportCategories()).singleWhere(
        (c) => c.id == 'expense_pet',
      );
      expect(petAfter.isActive, isTrue);

      // 自定义图片图标：只改名时保留自定义图标；换内置图标时回收孤儿图片文件
      const customId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      await tools.ledgerService.imageStorage.writeCategoryIcon(
        iconId: customId,
        bytes: [1, 2, 3, 4],
      );
      final iconFile = await tools.ledgerService.imageStorage.resolve(
        categoryIconRelativePath(customId),
      );
      expect(iconFile.existsSync(), isTrue);
      await database.addCategory(
        id: 'custom_cat',
        kind: 0,
        name: '自选图',
        iconKey: customCategoryIconKey(customId),
      );

      final renamedOnly = await tools.updateCategory({
        'id': 'custom_cat',
        'name': '改名保留图',
      });
      expect(renamedOnly['iconKey'], customCategoryIconKey(customId));
      expect(iconFile.existsSync(), isTrue);

      await tools.updateCategory({
        'id': 'custom_cat',
        'iconKey': 'gift',
      });
      expect(iconFile.existsSync(), isFalse);

      // 收入侧只留最后一个可用一级分类时，停用必须被拦住
      final incomeRoots = (await database.exportCategories())
          .where((c) => c.kind == 1 && c.level == 1)
          .toList();
      for (final root in incomeRoots.take(incomeRoots.length - 1)) {
        await database.setCategoryActive(root.id, false);
      }
      await expectLater(
        tools.updateCategory({
          'id': incomeRoots.last.id,
          'isActive': false,
        }),
        throwsStateError,
      );
    });

    test('delete_categories 拦截账单引用与清空根分类，提示模板级联并清理删除子树', () async {
      await _saveFood(tools);
      // 「餐饮」下的「三餐」有账单，删父分类或删该子分类都必须在弹窗前直接拦截
      await expectLater(
        tools.describe(
          const ToolCallPart(
            toolCallId: 'del-busy-root',
            toolName: 'delete_categories',
            args: {
              'ids': ['expense_food'],
            },
            state: ToolCallState.inputAvailable,
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        tools.deleteCategories({
          'ids': ['expense_food_meals'],
        }),
        throwsStateError,
      );

      // 禁止一次性把收入侧全部一级分类删空
      final incomeRootIds = (await database.exportCategories())
          .where((c) => c.kind == 1 && c.level == 1)
          .map((c) => c.id)
          .toList();
      await expectLater(
        tools.deleteCategories({'ids': incomeRootIds}),
        throwsStateError,
      );

      // 「宠物」无账单但挂了一个模板：确认请求注明模板级联删除，执行后父子与模板一并移除
      await tools.ledgerService.saveTemplate(
        kind: 0,
        amountCents: 9900,
        categoryId: 'expense_pet_food',
        note: '买猫粮',
      );
      final delReq = await tools.describe(
        const ToolCallPart(
          toolCallId: 'del-pet',
          toolName: 'delete_categories',
          args: {
            'ids': ['expense_pet'],
          },
          state: ToolCallState.inputAvailable,
        ),
      );
      expect(delReq, isNotNull);
      expect(delReq!.destructive, isTrue);
      expect(delReq.footnote, contains('1 个记账模板'));

      final delRes = await tools.deleteCategories({
        'ids': ['expense_pet'],
      });
      expect(delRes['deletedCount'], 4); // 宠物 + 3 个子分类
      final remainingIds = (await database.exportCategories())
          .map((c) => c.id)
          .toSet();
      expect(remainingIds, isNot(contains('expense_pet')));
      expect(remainingIds, isNot(contains('expense_pet_food')));
      expect(await database.exportTemplates(), isEmpty);
    });

    test('会话内分类变更后 refreshSystemPrompt 实时同步可用分类列表', () async {
      SharedPreferences.setMockInitialValues({});
      final session = await AiChatSession.create(
        database: database,
        ledgerService: tools.ledgerService,
        settings: const AiSettings(
          keys: {AiPlatform.deepseek: 'sk-test'},
          model: kDeepSeekDefaultModel,
          reasoning: AiReasoningEffort.high,
        ),
        initial: null,
        approval: ToolApprovalCoordinator(),
      );
      addTearDown(session.dispose);

      expect(session.systemPrompt, isNot(contains('露营装备')));
      expect(session.systemPrompt, contains('expense_pet | 宠物'));

      await tools.createCategories({
        'items': [
          {'kind': 'expense', 'name': '露营装备', 'iconKey': 'camping'},
        ],
      });
      await tools.updateCategory({'id': 'expense_pet', 'isActive': false});
      await session.refreshSystemPrompt();

      expect(session.systemPrompt, contains('露营装备'));
      expect(session.systemPrompt, isNot(contains('expense_pet | 宠物')));
    });
  });
}

Future<String> _saveFood(LedgerToolService tools) {
  return tools.ledgerService.save(
    kind: 0,
    amountCents: 2800,
    categoryId: 'expense_food_meals',
    accountingDate: DateTime(2026, 10, 18),
    occurredAt: DateTime(2026, 10, 18, 12),
    note: '午饭',
    pendingImages: const <XFile>[],
    existingImages: const <TransactionImageEntry>[],
    removedImageIds: const <String>{},
  );
}
