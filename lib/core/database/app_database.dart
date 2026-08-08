import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../utils/ledger_date.dart';
import 'default_categories.dart';

part 'app_database.g.dart';

@DataClassName('CategoryEntry')
class Categories extends Table {
  TextColumn get id => text()();
  IntColumn get kind => integer()();
  TextColumn get name => text()();
  TextColumn get iconKey => text()();
  TextColumn get parentId => text().nullable()();
  IntColumn get level => integer().withDefault(const Constant(1))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TransactionEntry')
class Transactions extends Table {
  TextColumn get id => text()();
  IntColumn get kind => integer()();
  IntColumn get amountCents => integer()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get accountingDate => text()();
  IntColumn get occurredAt => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TransactionImageEntry')
class TransactionImages extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();
  TextColumn get imagePath => text()();
  TextColumn get thumbnailPath => text()();
  TextColumn get mimeType => text().withDefault(const Constant('image/jpeg'))();
  IntColumn get width => integer().withDefault(const Constant(0))();
  IntColumn get height => integer().withDefault(const Constant(0))();
  IntColumn get sizeBytes => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Categories, Transactions, TransactionImages])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'ligy_tally'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _seedCategories();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(categories, categories.parentId);
        await migrator.addColumn(categories, categories.level);
      }
      if (from < 3) {
        await _seedCategories(insertOrIgnore: true);
        final mappings = {
          ...legacyCategoryMapping,
          ...deprecatedCategoryMapping,
        };
        for (final mapping in mappings.entries) {
          if (mapping.key == mapping.value) continue;
          await customStatement(
            'UPDATE transactions SET category_id = ? WHERE category_id = ?',
            [mapping.value, mapping.key],
          );
        }
        final defaultIds = defaultCategorySeeds.map((seed) => seed.id).toSet();
        final obsoleteIds = mappings.keys
            .where((id) => !defaultIds.contains(id))
            .toList();
        await (delete(
          categories,
        )..where((row) => row.id.isIn(obsoleteIds))).go();
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _seedCategories({bool insertOrIgnore = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await batch((batch) {
      for (final seed in defaultCategorySeeds) {
        batch.insert(
          categories,
          CategoriesCompanion.insert(
            id: seed.id,
            kind: seed.kind,
            name: seed.name,
            iconKey: seed.iconKey,
            parentId: Value(seed.parentId),
            level: Value(seed.level),
            sortOrder: Value(seed.sortOrder),
            createdAt: now,
            updatedAt: now,
          ),
          mode: insertOrIgnore ? InsertMode.insertOrIgnore : InsertMode.insert,
        );
      }
    });
  }

  Stream<List<CategoryEntry>> watchCategories(
    int kind, {
    bool activeOnly = true,
  }) {
    final query = select(categories)
      ..where((row) => row.kind.equals(kind))
      ..orderBy([
        (row) => OrderingTerm.asc(row.level),
        (row) => OrderingTerm.asc(row.sortOrder),
      ]);
    if (activeOnly) {
      query.where((row) => row.isActive.equals(true));
    }
    return query.watch();
  }

  Future<void> addCategory({
    required String id,
    required int kind,
    required String name,
    String? parentId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxSort = categories.sortOrder.max();
    final query = selectOnly(categories)..addColumns([maxSort]);
    query.where(
      categories.kind.equals(kind) &
          (parentId == null
              ? categories.parentId.isNull()
              : categories.parentId.equals(parentId)),
    );
    final result = await query.getSingle();
    await into(categories).insert(
      CategoriesCompanion.insert(
        id: id,
        kind: kind,
        name: name,
        iconKey: 'other',
        parentId: Value(parentId),
        level: Value(parentId == null ? 1 : 2),
        sortOrder: Value((result.read(maxSort) ?? 0) + 1),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> setCategoryActive(String id, bool active) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return transaction(() async {
      final category = await (select(
        categories,
      )..where((row) => row.id.equals(id))).getSingle();
      await (update(categories)..where((row) => row.id.equals(id))).write(
        CategoriesCompanion(isActive: Value(active), updatedAt: Value(now)),
      );
      if (active && category.parentId != null) {
        await (update(
          categories,
        )..where((row) => row.id.equals(category.parentId!))).write(
          CategoriesCompanion(
            isActive: const Value(true),
            updatedAt: Value(now),
          ),
        );
      }
      if (!active) {
        await (update(
          categories,
        )..where((row) => row.parentId.equals(id))).write(
          CategoriesCompanion(
            isActive: const Value(false),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  Future<CategoryDeleteResult> deleteCategory(String id) {
    return transaction(() async {
      final category = await (select(
        categories,
      )..where((row) => row.id.equals(id))).getSingle();
      if (category.level == 1 && category.isActive) {
        final rootCount = categories.id.count();
        final activeRoots =
            await (selectOnly(categories)
                  ..addColumns([rootCount])
                  ..where(
                    categories.kind.equals(category.kind) &
                        categories.level.equals(1) &
                        categories.isActive.equals(true),
                  ))
                .map((row) => row.read(rootCount) ?? 0)
                .getSingle();
        if (activeRoots <= 1) return CategoryDeleteResult.lastRoot;
      }
      final childIds =
          await (selectOnly(categories)
                ..addColumns([categories.id])
                ..where(categories.parentId.equals(id)))
              .map((row) => row.read(categories.id)!)
              .get();
      final ids = {id, ...childIds};
      final count = transactions.id.count();
      final usage =
          await (selectOnly(transactions)
                ..addColumns([count])
                ..where(transactions.categoryId.isIn(ids)))
              .map((row) => row.read(count) ?? 0)
              .getSingle();
      if (usage > 0) return CategoryDeleteResult.inUse;
      await (delete(categories)..where((row) => row.id.isIn(ids))).go();
      return CategoryDeleteResult.deleted;
    });
  }

  Future<void> replaceActiveCategoryConfig(List<CategoryEntry> rows) {
    return transaction(() async {
      await update(categories).write(
        CategoriesCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await batch((batch) {
        batch.insertAllOnConflictUpdate(categories, rows);
      });
      await customStatement('''
        DELETE FROM categories
        WHERE is_active = 0
          AND id NOT IN (SELECT category_id FROM transactions)
          AND id NOT IN (
            SELECT parent_id FROM categories
            WHERE id IN (SELECT category_id FROM transactions)
              AND parent_id IS NOT NULL
          )
      ''');
    });
  }

  Stream<List<LedgerItem>> watchTransactions(
    LedgerDateRange range, {
    int? kind,
  }) {
    final query =
        select(transactions).join([
            innerJoin(
              categories,
              categories.id.equalsExp(transactions.categoryId),
            ),
          ])
          ..where(
            transactions.accountingDate.isBiggerOrEqualValue(
                  dateKey(range.start),
                ) &
                transactions.accountingDate.isSmallerThanValue(
                  dateKey(range.endExclusive),
                ),
          )
          ..orderBy([OrderingTerm.desc(transactions.occurredAt)]);
    if (kind != null) {
      query.where(transactions.kind.equals(kind));
    }
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => LedgerItem(
              transaction: row.readTable(transactions),
              category: row.readTable(categories),
            ),
          )
          .toList(),
    );
  }

  Stream<LedgerSummary> watchSummary(LedgerDateRange range) {
    return customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN kind = 1 THEN amount_cents ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN kind = 0 THEN amount_cents ELSE 0 END), 0) AS expense,
        COUNT(*) AS entry_count
      FROM transactions
      WHERE accounting_date >= ? AND accounting_date < ?
      ''',
      variables: [
        Variable.withString(dateKey(range.start)),
        Variable.withString(dateKey(range.endExclusive)),
      ],
      readsFrom: {transactions},
    ).watchSingle().map(
      (row) => LedgerSummary(
        incomeCents: row.read<int>('income'),
        expenseCents: row.read<int>('expense'),
        entryCount: row.read<int>('entry_count'),
      ),
    );
  }

  Stream<List<CategoryTotal>> watchCategoryTotals(
    LedgerDateRange range,
    int kind,
  ) {
    return customSelect(
      '''
      SELECT root.id, root.name, root.icon_key,
             SUM(t.amount_cents) AS total, COUNT(*) AS entry_count
      FROM transactions t
      JOIN categories c ON c.id = t.category_id
      JOIN categories root ON root.id = COALESCE(c.parent_id, c.id)
      WHERE t.accounting_date >= ? AND t.accounting_date < ? AND t.kind = ?
      GROUP BY root.id, root.name, root.icon_key
      ORDER BY total DESC
      ''',
      variables: [
        Variable.withString(dateKey(range.start)),
        Variable.withString(dateKey(range.endExclusive)),
        Variable.withInt(kind),
      ],
      readsFrom: {transactions, categories},
    ).watch().map(
      (rows) => rows
          .map(
            (row) => CategoryTotal(
              categoryId: row.read<String>('id'),
              name: row.read<String>('name'),
              iconKey: row.read<String>('icon_key'),
              totalCents: row.read<int>('total'),
              entryCount: row.read<int>('entry_count'),
            ),
          )
          .toList(),
    );
  }

  Stream<List<TrendPoint>> watchTrend(
    LedgerDateRange range, {
    required bool groupByMonth,
  }) {
    final bucket = groupByMonth
        ? "substr(accounting_date, 1, 7)"
        : 'accounting_date';
    return customSelect(
      '''
      SELECT $bucket AS bucket,
        COALESCE(SUM(CASE WHEN kind = 1 THEN amount_cents ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN kind = 0 THEN amount_cents ELSE 0 END), 0) AS expense
      FROM transactions
      WHERE accounting_date >= ? AND accounting_date < ?
      GROUP BY bucket
      ORDER BY bucket ASC
      ''',
      variables: [
        Variable.withString(dateKey(range.start)),
        Variable.withString(dateKey(range.endExclusive)),
      ],
      readsFrom: {transactions},
    ).watch().map(
      (rows) => rows
          .map(
            (row) => TrendPoint(
              bucket: row.read<String>('bucket'),
              incomeCents: row.read<int>('income'),
              expenseCents: row.read<int>('expense'),
            ),
          )
          .toList(),
    );
  }

  Future<List<TransactionImageEntry>> imagesFor(String transactionId) {
    return (select(transactionImages)
          ..where((row) => row.transactionId.equals(transactionId))
          ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
        .get();
  }

  Future<void> saveTransaction({
    required TransactionsCompanion entry,
    required List<TransactionImagesCompanion> newImages,
    required Set<String> removedImageIds,
  }) {
    return transaction(() async {
      await into(transactions).insertOnConflictUpdate(entry);
      if (removedImageIds.isNotEmpty) {
        await (delete(
          transactionImages,
        )..where((row) => row.id.isIn(removedImageIds))).go();
      }
      if (newImages.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(transactionImages, newImages);
        });
      }
    });
  }

  Future<void> deleteTransaction(String id) async {
    await (delete(transactions)..where((row) => row.id.equals(id))).go();
  }

  Future<List<CategoryEntry>> exportCategories() => select(categories).get();

  Future<List<TransactionEntry>> exportTransactions() =>
      select(transactions).get();

  Future<List<TransactionImageEntry>> exportImages() =>
      select(transactionImages).get();

  Future<void> replaceAllData({
    required List<CategoryEntry> categoryRows,
    required List<TransactionEntry> transactionRows,
    required List<TransactionImageEntry> imageRows,
  }) {
    return transaction(() async {
      await delete(transactionImages).go();
      await delete(transactions).go();
      await delete(categories).go();
      await batch((batch) {
        batch.insertAll(categories, categoryRows);
        batch.insertAll(transactions, transactionRows);
        batch.insertAll(transactionImages, imageRows);
      });
    });
  }
}

enum CategoryDeleteResult { deleted, inUse, lastRoot }

class LedgerItem {
  const LedgerItem({required this.transaction, required this.category});

  final TransactionEntry transaction;
  final CategoryEntry category;
}

class LedgerSummary {
  const LedgerSummary({
    required this.incomeCents,
    required this.expenseCents,
    required this.entryCount,
  });

  final int incomeCents;
  final int expenseCents;
  final int entryCount;

  int get netCents => incomeCents - expenseCents;
}

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.iconKey,
    required this.totalCents,
    required this.entryCount,
  });

  final String categoryId;
  final String name;
  final String iconKey;
  final int totalCents;
  final int entryCount;
}

class TrendPoint {
  const TrendPoint({
    required this.bucket,
    required this.incomeCents,
    required this.expenseCents,
  });

  final String bucket;
  final int incomeCents;
  final int expenseCents;
}
