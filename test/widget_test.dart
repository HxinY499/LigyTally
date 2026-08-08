import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/category_config/category_config_service.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/database/default_categories.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/utils/ledger_date.dart';
import 'package:ligy_tally/shared/widgets/summary_band.dart';

void main() {
  test('month range uses a left-closed right-open boundary', () {
    final range = monthRange(DateTime(2026, 2, 18));

    expect(range.start, DateTime(2026, 2));
    expect(range.endExclusive, DateTime(2026, 3));
    expect(range.dayCount, 28);
  });

  test('money formatting keeps integer-cent precision', () {
    expect(formatMoney(1234), '¥12.34');
    expect(formatMoney(-505, signed: true), '-¥5.05');
    expect(formatMoney(505, signed: true), '+¥5.05');
  });

  test('default category seed preserves a generic two-level tree', () {
    expect(defaultCategorySeeds, hasLength(44));
    expect(
      defaultCategorySeeds.where((item) => item.level == 1),
      hasLength(16),
    );
    expect(
      defaultCategorySeeds.where((item) => item.level == 2),
      hasLength(28),
    );
    expect(
      defaultCategorySeeds.any(
        (item) => item.name == '宠物食品' && item.parentId == 'expense_pet',
      ),
      isTrue,
    );
    expect(defaultCategorySeeds.any((item) => item.name == '果冻'), isFalse);
  });

  test(
    'database creates the full category tree and stores subcategories',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final categories = await database.exportCategories();

      expect(categories, hasLength(44));
      expect(categories.where((item) => item.level == 1), hasLength(16));
      expect(categories.where((item) => item.level == 2), hasLength(28));

      final petFood = categories.singleWhere((item) => item.name == '宠物食品');
      final pet = categories.singleWhere((item) => item.name == '宠物');
      expect(petFood.parentId, pet.id);

      final now = DateTime(2026, 8, 8, 17);
      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: 'test-transaction',
          kind: 0,
          amountCents: 2350,
          categoryId: petFood.id,
          accountingDate: '2026-08-08',
          occurredAt: now.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
          note: const Value('猫粮'),
        ),
        newImages: const [],
        removedImageIds: const {},
      );
      final items = await database
          .watchTransactions(
            LedgerDateRange(DateTime(2026, 8), DateTime(2026, 9)),
          )
          .first;
      expect(items.single.category.name, '宠物食品');
      expect(
        await database.deleteCategory(petFood.id),
        CategoryDeleteResult.inUse,
      );
    },
  );

  test(
    'category config import replaces active config with a two-level tree',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final directory = await Directory.systemTemp.createTemp(
        'ligy_categories',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/categories.json');
      await file.writeAsString('''
        {
          "format": "ligy-tally-categories",
          "version": 1,
          "expense": [
            {
              "name": "通勤",
              "icon": "transport",
              "children": [{"name": "地铁", "icon": "subway"}]
            }
          ],
          "income": [
            {"name": "薪资", "icon": "salary", "children": []}
          ]
        }
      ''');

      final service = CategoryConfigService(database);
      final preview = await service.inspect(file.path);
      expect(preview.parentCount, 2);
      expect(preview.childCount, 1);

      await service.importAndReplace(file.path);
      final active = (await database.exportCategories())
          .where((category) => category.isActive)
          .toList();
      expect(active, hasLength(3));
      final subway = active.singleWhere((category) => category.name == '地铁');
      final commute = active.singleWhere((category) => category.name == '通勤');
      expect(subway.parentId, commute.id);
      expect(
        await database.deleteCategory(subway.id),
        CategoryDeleteResult.deleted,
      );
    },
  );

  testWidgets('summary band presents expense, income and net values', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: SummaryBand(
            summary: LedgerSummary(
              incomeCents: 10000,
              expenseCents: 3575,
              entryCount: 2,
            ),
          ),
        ),
      ),
    );

    expect(find.text('¥35.75'), findsOneWidget);
    expect(find.text('¥100.00'), findsOneWidget);
    expect(find.text('+¥64.25'), findsOneWidget);
  });
}
