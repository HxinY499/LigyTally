import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_ai_tools/flutter_ai_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/location/place_fix.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/features/ai/application/ledger_tools.dart';
import 'package:ligy_tally/features/ledger/application/ledger_service.dart';

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
