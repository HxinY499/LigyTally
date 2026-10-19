import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_ai_tools/flutter_ai_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ligy_tally/core/database/app_database.dart';
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
    );
    // 触发 onCreate 的默认分类种子。
    await database.exportCategories();
  });

  tearDown(() async {
    await database.close();
    mediaRoot.deleteSync(recursive: true);
  });

  test('汇总和分类排行复用统计口径', () async {
    await _saveFood(tools);

    final summary = await tools.summary({
      'from': '2026-10-01',
      'to': '2026-10-31',
    });
    expect(summary['expenseCents'], 2800);
    expect(summary['incomeCents'], 0);
    expect(summary['entryCount'], 1);

    final breakdown = await tools.categoryBreakdown({
      'from': '2026-10-01',
      'to': '2026-10-31',
      'kind': 'expense',
    });
    final categories = breakdown['categories']! as List<Object?>;
    expect(categories, hasLength(1));
    final food = categories.single! as Map<String, Object?>;
    expect(food['categoryId'], 'expense_food');
    expect(food['name'], '餐饮');
    expect(food['totalCents'], 2800);
  });

  test('搜索返回紧凑账单并可定位到备注', () async {
    await _saveFood(tools);

    final result = await tools.searchTransactions({
      'from': '2026-10-01',
      'to': '2026-10-31',
      'query': '午饭',
    });
    final rows = result['transactions']! as List<Object?>;
    expect(rows, hasLength(1));
    final row = rows.single! as Map<String, Object?>;
    expect(row['note'], '午饭');
    expect(row['categoryName'], '三餐');
    expect(row['amountCents'], 2800);
    expect(row['id'], isNotEmpty);
  });

  test('写操作先给出人话确认摘要', () async {
    final request = await tools.describe(
      const ToolCallPart(
        toolCallId: 'call-1',
        toolName: 'save_transaction',
        args: {
          'kind': 'expense',
          'amountCents': 2800,
          'categoryId': 'expense_food_meals',
          'accountingDate': '2026-10-19',
          'note': '午饭',
        },
        state: ToolCallState.inputAvailable,
      ),
    );

    expect(request, isNotNull);
    expect(request!.confirmLabel, '确认记账');
    expect(request.message, contains('¥28.00'));
    expect(request.message, contains('三餐'));
    expect(request.message, contains('2026-10-19'));
    expect(request.destructive, isFalse);
  });

  test('新增账单走 LedgerService 并返回 id', () async {
    final result = await tools.saveTransaction({
      'kind': 'expense',
      'amountCents': 3550,
      'categoryId': 'expense_transport_taxi',
      'accountingDate': '2026-10-18',
      'note': '打车回家',
    });
    expect(result['ok'], isTrue);
    expect(result['transactionId'], isNotEmpty);
    final rows = await database.exportTransactions();
    expect(rows, hasLength(1));
    expect(rows.single.amountCents, 3550);
    expect(rows.single.categoryId, 'expense_transport_taxi');
  });

  test('同一个 toolCallId 重试不会写出两笔账', () async {
    final args = {
      'kind': 'expense',
      'amountCents': 3550,
      'categoryId': 'expense_transport_taxi',
      'accountingDate': '2026-10-18',
      'note': '打车回家',
    };
    await tools.saveTransaction(args, id: 'ai-call-retry');
    await tools.saveTransaction(args, id: 'ai-call-retry');

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

  test('分类收支类型不匹配时拒绝写入', () async {
    await expectLater(
      tools.saveTransaction({
        'kind': 'expense',
        'amountCents': 100,
        'categoryId': 'income_salary',
        'accountingDate': '2026-10-19',
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
