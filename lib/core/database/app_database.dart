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

  /// 现场记下的纬度。和 [locationLongitude] 成对出现，缺一即视为没有位置。
  RealColumn get locationLatitude => real().nullable()();
  RealColumn get locationLongitude => real().nullable()();

  /// 给人看的地点文案（逆地理预填或用户手改）。可空：有坐标但没地名时界面显示「已记录位置」。
  TextColumn get locationName => text().nullable()();
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
  int get schemaVersion => 4;

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
      if (from < 4) {
        await migrator.addColumn(transactions, transactions.locationLatitude);
        await migrator.addColumn(transactions, transactions.locationLongitude);
        await migrator.addColumn(transactions, transactions.locationName);
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
        (row) => OrderingTerm.asc(row.parentId),
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
    String iconKey = 'other',
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
        iconKey: iconKey,
        parentId: Value(parentId),
        level: Value(parentId == null ? 1 : 2),
        sortOrder: Value((result.read(maxSort) ?? 0) + 1),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// 按 [ids] 的顺序，把同一 scope 内的 `sortOrder` 重写成 `0..n-1`。
  ///
  /// scope 由列表里每一项共同决定：一级是 `(kind, parent_id IS NULL)`，
  /// 二级是 `(kind, parent_id = 该项的父级)`。不能跨层级、不能跨父级，
  /// 也不能漏掉同 scope 里的停用项——漏掉的那条会带着旧序号留在原位，
  /// 下次拖拽又会插回来。
  ///
  /// [ids] 少于 2 个是空操作：一张卡、一个格子没有可交换的位置。
  Future<void> reorderCategories(List<String> ids) async {
    if (ids.length < 2) return;
    await transaction(() async {
      final rows = await (select(
        categories,
      )..where((row) => row.id.isIn(ids))).get();
      if (rows.length != ids.length) {
        throw StateError('分类已变化，请重试');
      }
      final byId = {for (final row in rows) row.id: row};
      final first = byId[ids.first]!;
      for (final id in ids) {
        final row = byId[id]!;
        if (row.kind != first.kind ||
            row.parentId != first.parentId ||
            row.level != first.level) {
          throw StateError('不能跨层级排序');
        }
      }
      final scope =
          await (select(categories)..where(
                (row) =>
                    row.kind.equals(first.kind) &
                    (first.parentId == null
                        ? row.parentId.isNull()
                        : row.parentId.equals(first.parentId!)),
              ))
              .get();
      if (scope.length != ids.length) {
        throw StateError('分类已变化，请重试');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await batch((batch) {
        for (var i = 0; i < ids.length; i++) {
          batch.update(
            categories,
            CategoriesCompanion(sortOrder: Value(i), updatedAt: Value(now)),
            where: (row) => row.id.equals(ids[i]),
          );
        }
      });
    });
  }

  /// 改分类的名称与图标。层级和归属不可改——分类一旦被账单引用，
  /// 换父级等于悄悄改写历史账单的归类，统计口径会前后不一致。
  Future<void> updateCategory({
    required String id,
    required String name,
    required String iconKey,
  }) {
    return (update(categories)..where((row) => row.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name),
        iconKey: Value(iconKey),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 同一层级下是否已有同名分类（[excludeId] 用于编辑时排除自己）。
  ///
  /// 放在数据层而不是界面层去 `_categories.any(...)`：界面手里只有当前
  /// kind 的列表，且停用项是否参与判重容易各处写法不一。重名会让记账时
  /// 的分类选择器出现两个一模一样的格子，必须统一在入口拦住。
  Future<bool> categoryNameExists({
    required int kind,
    required String name,
    String? parentId,
    String? excludeId,
  }) async {
    final query = select(categories)
      ..where(
        (row) =>
            row.kind.equals(kind) &
            row.name.equals(name) &
            (parentId == null
                ? row.parentId.isNull()
                : row.parentId.equals(parentId)),
      );
    final rows = await query.get();
    return rows.any((row) => row.id != excludeId);
  }

  /// 启用 / 停用分类。
  ///
  /// 返回 [CategoryToggleResult.lastRoot] 表示这次停用会让该收支类型
  /// 一个可用的一级分类都不剩——记账页的分类选择器会直接空掉，没法记账，
  /// 所以拦在这里。删除路径上早有同样的约束（[CategoryDeleteResult.lastRoot]），
  /// 停用只是「软删除」，不该能绕过它。
  Future<CategoryToggleResult> setCategoryActive(String id, bool active) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return transaction(() async {
      final category = await (select(
        categories,
      )..where((row) => row.id.equals(id))).getSingle();
      if (!active && category.level == 1) {
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
        if (activeRoots <= 1) return CategoryToggleResult.lastRoot;
      }
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
      return CategoryToggleResult.ok;
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

  /// 区间内账单的一次性快照，按记账日、发生时间升序。
  ///
  /// [range] 为 null 表示全部账单——「导出全部」不该用 2000–2100 这种假区间
  /// 去碰运气，记账日一旦落在窗外就会被静默丢掉。
  ///
  /// 给 CSV 导出用：表格软件从上往下读应该是时间线，不是明细页那种最新在上。
  /// 和 [watchTransactions] 分开，是因为那边是 Stream、倒序，硬扭成升序快照会
  /// 让调用方看起来像在「订阅一份不会再变的列表」。
  Future<List<LedgerItem>> transactionsIn([LedgerDateRange? range]) async {
    final query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    ]);
    if (range != null) {
      query.where(
        transactions.accountingDate.isBiggerOrEqualValue(dateKey(range.start)) &
            transactions.accountingDate.isSmallerThanValue(
              dateKey(range.endExclusive),
            ),
      );
    }
    query.orderBy([
      OrderingTerm.asc(transactions.accountingDate),
      OrderingTerm.asc(transactions.occurredAt),
    ]);
    final rows = await query.get();
    return [
      for (final row in rows)
        LedgerItem(
          transaction: row.readTable(transactions),
          category: row.readTable(categories),
        ),
    ];
  }

  /// 某个一级分类在区间内的账单明细，按发生时间倒序。
  ///
  /// 归属口径与 [watchCategoryTotals] 一致：交易挂在二级分类上时也算进它的
  /// 一级分类。只按 `category_id == rootCategoryId` 过滤会漏掉全部二级分类的
  /// 账单——排行里的合计是按 root 聚合的，两处口径必须相同，否则明细的
  /// 笔数/金额对不上排行行上的数字。
  ///
  /// 分类树只有两级（见 [watchCategoryTotals] 的 `COALESCE(parent_id, id)`），
  /// 所以「自身 or 父为 root」已覆盖全部情况。
  Stream<List<LedgerItem>> watchCategoryTransactions(
    LedgerDateRange range, {
    required String rootCategoryId,
    required int kind,
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
                ) &
                transactions.kind.equals(kind) &
                (categories.id.equals(rootCategoryId) |
                    categories.parentId.equals(rootCategoryId)),
          )
          ..orderBy([OrderingTerm.desc(transactions.occurredAt)]);
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
        COUNT(*) AS entry_count,
        COUNT(DISTINCT accounting_date) AS active_days
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
        activeDayCount: row.read<int>('active_days'),
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

  /// 一级分类在 [current] 与 [comparison] 两个区间内的金额对照。
  ///
  /// 归属口径与 [watchCategoryTotals] 完全一致（`COALESCE(parent_id, id)`），
  /// 所以两张卡上同一个分类的当期金额必然相等。
  ///
  /// 用一条 SQL 的 CASE WHEN 同时聚合两个区间，而不是订阅两次再在内存里 join：
  /// 只出现在其中一个区间的分类必须以「新增」或「归零」的形式出现，
  /// 分两次查再合并的话，这类分类要靠调用方补齐 key，很容易漏掉一侧。
  ///
  /// 两个区间不允许重叠（[comparison] 恒在 [current] 之前），否则同一笔账单
  /// 会被两列同时计入，差额失去意义。
  Stream<List<CategoryDelta>> watchCategoryDeltas({
    required LedgerDateRange current,
    required LedgerDateRange comparison,
    required int kind,
  }) {
    final currentStart = dateKey(current.start);
    final currentEnd = dateKey(current.endExclusive);
    final comparisonStart = dateKey(comparison.start);
    final comparisonEnd = dateKey(comparison.endExclusive);
    return customSelect(
      '''
      SELECT root.id AS id, root.name AS name, root.icon_key AS icon_key,
        COALESCE(SUM(CASE WHEN t.accounting_date >= ? AND t.accounting_date < ?
          THEN t.amount_cents ELSE 0 END), 0) AS current_total,
        COALESCE(SUM(CASE WHEN t.accounting_date >= ? AND t.accounting_date < ?
          THEN t.amount_cents ELSE 0 END), 0) AS comparison_total
      FROM transactions t
      JOIN categories c ON c.id = t.category_id
      JOIN categories root ON root.id = COALESCE(c.parent_id, c.id)
      WHERE t.kind = ?
        AND ((t.accounting_date >= ? AND t.accounting_date < ?)
          OR (t.accounting_date >= ? AND t.accounting_date < ?))
      GROUP BY root.id, root.name, root.icon_key
      ''',
      // 顺序必须与 SQL 中 `?` 的出现顺序一致。
      variables: [
        Variable.withString(currentStart),
        Variable.withString(currentEnd),
        Variable.withString(comparisonStart),
        Variable.withString(comparisonEnd),
        Variable.withInt(kind),
        Variable.withString(currentStart),
        Variable.withString(currentEnd),
        Variable.withString(comparisonStart),
        Variable.withString(comparisonEnd),
      ],
      readsFrom: {transactions, categories},
    ).watch().map(
      (rows) => rows
          .map(
            (row) => CategoryDelta(
              categoryId: row.read<String>('id'),
              name: row.read<String>('name'),
              iconKey: row.read<String>('icon_key'),
              currentCents: row.read<int>('current_total'),
              comparisonCents: row.read<int>('comparison_total'),
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

  /// 近 [count] 个周期的支出/收入总额，用于"周期支出对比"柱状图。
  ///
  /// [ranges] 由调用方按周期类型（日/周/月/年）算好并按时间升序传入，
  /// 这里用一条 SQL 的 CASE WHEN 把每个区间聚合成一列，避免 N 次订阅。
  ///
  /// [rootCategoryId] 非空时只统计该一级分类及其二级分类，归集口径与
  /// [watchCategoryTotals] 一致，用于分类下钻面板里的走势。
  Stream<List<PeriodBar>> watchPeriodBars(
    List<PeriodSpan> ranges, {
    String? rootCategoryId,
  }) {
    if (ranges.isEmpty) {
      return Stream.value(const <PeriodBar>[]);
    }
    final expenseCases = StringBuffer();
    final incomeCases = StringBuffer();
    final variables = <Variable<Object>>[];
    // 列名一律带 `t.` 前缀：分类过滤要 join categories，而它同样有 kind 列，
    // 裸列名会变成歧义引用。
    for (var i = 0; i < ranges.length; i++) {
      expenseCases.write(
        'COALESCE(SUM(CASE WHEN t.kind = 0 AND t.accounting_date >= ? AND t.accounting_date < ? THEN t.amount_cents ELSE 0 END), 0) AS e$i, ',
      );
      incomeCases.write(
        'COALESCE(SUM(CASE WHEN t.kind = 1 AND t.accounting_date >= ? AND t.accounting_date < ? THEN t.amount_cents ELSE 0 END), 0) AS n$i, ',
      );
    }
    // 变量顺序需与 SQL 中 `?` 出现顺序一致：先所有 expense 段，再所有 income 段。
    for (final span in ranges) {
      variables
        ..add(Variable.withString(dateKey(span.range.start)))
        ..add(Variable.withString(dateKey(span.range.endExclusive)));
    }
    for (final span in ranges) {
      variables
        ..add(Variable.withString(dateKey(span.range.start)))
        ..add(Variable.withString(dateKey(span.range.endExclusive)));
    }
    final overallStart = dateKey(ranges.first.range.start);
    final overallEnd = dateKey(ranges.last.range.endExclusive);
    variables
      ..add(Variable.withString(overallStart))
      ..add(Variable.withString(overallEnd));
    final scoped = rootCategoryId != null;
    if (scoped) variables.add(Variable.withString(rootCategoryId));
    return customSelect(
      'SELECT ${expenseCases.toString()}${incomeCases.toString().replaceAll(RegExp(r', $'), '')} '
      'FROM transactions t '
      '${scoped ? 'JOIN categories c ON c.id = t.category_id ' : ''}'
      'WHERE t.accounting_date >= ? AND t.accounting_date < ?'
      '${scoped ? ' AND COALESCE(c.parent_id, c.id) = ?' : ''}',
      variables: variables,
      readsFrom: scoped ? {transactions, categories} : {transactions},
    ).watchSingle().map((row) {
      return [
        for (var i = 0; i < ranges.length; i++)
          PeriodBar(
            label: ranges[i].label,
            expenseCents: row.read<int>('e$i'),
            incomeCents: row.read<int>('n$i'),
          ),
      ];
    });
  }

  Future<List<TransactionImageEntry>> imagesFor(String transactionId) {
    return (select(transactionImages)
          ..where((row) => row.transactionId.equals(transactionId))
          ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
        .get();
  }

  /// 一批账单各自的图片，按 [sortOrder] 排好。
  ///
  /// 导出带图表格时一行一次 [imagesFor] 会变成 N 次查询，按 id 一把捞回来
  /// 再分组。
  Future<Map<String, List<TransactionImageEntry>>> imagesGroupedFor(
    List<String> transactionIds,
  ) async {
    if (transactionIds.isEmpty) return const {};
    final rows =
        await (select(transactionImages)
              ..where((row) => row.transactionId.isIn(transactionIds))
              ..orderBy([
                (row) => OrderingTerm.asc(row.transactionId),
                (row) => OrderingTerm.asc(row.sortOrder),
              ]))
            .get();
    final grouped = <String, List<TransactionImageEntry>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.transactionId, () => []).add(row);
    }
    return grouped;
  }

  /// 一批账单各自挂了几张图。CSV 只记数量、不带文件。
  Future<Map<String, int>> imageCountsFor(List<String> transactionIds) async {
    if (transactionIds.isEmpty) return const {};
    final count = transactionImages.id.count();
    final rows =
        await (selectOnly(transactionImages)
              ..addColumns([transactionImages.transactionId, count])
              ..where(transactionImages.transactionId.isIn(transactionIds))
              ..groupBy([transactionImages.transactionId]))
            .get();
    return {
      for (final row in rows)
        row.read(transactionImages.transactionId)!: row.read(count) ?? 0,
    };
  }

  /// [range] 内每条账单首图的缩略图相对路径，键为账单 id。
  ///
  /// 明细列表要给有图的账单铺行背景。一行一次 [imagesFor] 会变成几十次查询，
  /// 所以按月一把捞回来在内存里配对；只留每条账单排序最靠前的那张，
  /// 后面的图列表用不上。
  Stream<Map<String, String>> watchFirstImagePaths(LedgerDateRange range) {
    final query =
        select(transactionImages).join([
            innerJoin(
              transactions,
              transactions.id.equalsExp(transactionImages.transactionId),
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
          ..orderBy([OrderingTerm.asc(transactionImages.sortOrder)]);
    return query.watch().map((rows) {
      final paths = <String, String>{};
      for (final row in rows) {
        final image = row.readTable(transactionImages);
        paths.putIfAbsent(image.transactionId, () => image.thumbnailPath);
      }
      return paths;
    });
  }

  /// 全部账单图片。占用空间页用来浏览和批量删除。
  ///
  /// 只返回库里有记录的图，不扫磁盘：分类图标、缩略图副本、孤儿文件
  /// 都不该出现在「账单图」里。
  ///
  /// [sort] 决定顺序：默认新的在前、同一笔按 [sortOrder] 挨着；
  /// [LedgerImageSort.largest] 是给「腾空间」用的，先删最大的那几张
  /// 比按时间翻找有效得多。
  Stream<List<LedgerImageItem>> watchAllImages({
    LedgerImageSort sort = LedgerImageSort.newest,
  }) {
    final query =
        select(transactionImages).join([
          innerJoin(
            transactions,
            transactions.id.equalsExp(transactionImages.transactionId),
          ),
          // 连分类：图库按账单分组时要靠分类图标和名字认出「这是哪笔账」，
          // 光有日期和金额认不出来；跳去编辑这笔账也需要完整的 LedgerItem。
          innerJoin(
            categories,
            categories.id.equalsExp(transactions.categoryId),
          ),
        ])..orderBy([
          if (sort == LedgerImageSort.largest)
            OrderingTerm.desc(transactionImages.sizeBytes),
          OrderingTerm.desc(transactions.accountingDate),
          OrderingTerm.desc(transactions.occurredAt),
          OrderingTerm.asc(transactionImages.sortOrder),
        ]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          LedgerImageItem(
            image: row.readTable(transactionImages),
            transaction: row.readTable(transactions),
            category: row.readTable(categories),
          ),
      ],
    );
  }

  Future<void> deleteImages(Set<String> ids) async {
    if (ids.isEmpty) return;
    await (delete(transactionImages)..where((row) => row.id.isIn(ids))).go();
  }

  /// 重压之后写回图片的实际尺寸与体积。
  ///
  /// 必须写回：占用空间的「平均每张」和图库的按大小排序都读这一列，
  /// 不更新的话重压完列表还按旧体积排，用户会以为没压。
  Future<void> updateImageMetrics({
    required String id,
    required int sizeBytes,
    required int width,
    required int height,
  }) async {
    await (update(transactionImages)..where((row) => row.id.equals(id))).write(
      TransactionImagesCompanion(
        sizeBytes: Value(sizeBytes),
        width: Value(width),
        height: Value(height),
      ),
    );
  }

  /// 回收数据库文件里的空闲页，让删除后的文件真正变小。
  ///
  /// VACUUM 会重建整个库文件，不能包在事务里，所以这里直接发裸语句。
  Future<void> compact() async {
    await customStatement('VACUUM');
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
    await deleteTransactions({id});
  }

  /// 一次删多笔。图片行靠外键 cascade 跟着走。
  Future<void> deleteTransactions(Set<String> ids) async {
    if (ids.isEmpty) return;
    await (delete(transactions)..where((row) => row.id.isIn(ids))).go();
  }

  /// 主库文件的绝对路径。内存库没有文件，返回 null。
  ///
  /// 占用空间必须拿这条路径去读磁盘，不能用 `transaction_images.size_bytes`
  /// 加总：那一列只有原图，不含缩略图、分类图标和 WAL。
  Future<String?> mainDatabaseFilePath() async {
    final rows = await customSelect('PRAGMA database_list').get();
    for (final row in rows) {
      if (row.read<String>('name') != 'main') continue;
      final path = row.read<String>('file');
      if (path.isEmpty || path == ':memory:') return null;
      return path;
    }
    return null;
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

/// 停用/启用的结果。[lastRoot] 表示停用后该收支类型没有可用一级分类了。
enum CategoryToggleResult { ok, lastRoot }

class LedgerItem {
  const LedgerItem({required this.transaction, required this.category});

  final TransactionEntry transaction;
  final CategoryEntry category;
}

class LedgerImageItem {
  const LedgerImageItem({
    required this.image,
    required this.transaction,
    required this.category,
  });

  final TransactionImageEntry image;
  final TransactionEntry transaction;
  final CategoryEntry category;

  /// 这张图所属的账单，可直接交给编辑页。
  LedgerItem get ledgerItem =>
      LedgerItem(transaction: transaction, category: category);
}

/// 图库的排序方式。
enum LedgerImageSort {
  /// 新的在前，同一笔的图挨在一起。翻找某笔账单的图时用这个。
  newest,

  /// 大的在前。腾空间时用这个。
  largest,
}

class LedgerSummary {
  const LedgerSummary({
    required this.incomeCents,
    required this.expenseCents,
    required this.entryCount,
    required this.activeDayCount,
  });

  final int incomeCents;
  final int expenseCents;
  final int entryCount;

  /// 区间内至少有一笔记录的天数。
  ///
  /// 用来暴露样本完整度：日均、环比、分类占比都建立在「这段时间记全了」
  /// 的前提上，而这个前提在页面上原本无处可查。
  final int activeDayCount;

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

/// 一个一级分类在「本期」与「对照期」的金额对照。
class CategoryDelta {
  const CategoryDelta({
    required this.categoryId,
    required this.name,
    required this.iconKey,
    required this.currentCents,
    required this.comparisonCents,
  });

  final String categoryId;
  final String name;
  final String iconKey;
  final int currentCents;
  final int comparisonCents;

  /// 正数表示本期比对照期多花（或多收）。
  int get deltaCents => currentCents - comparisonCents;

  /// 变化幅度。对照期为 0 时算不出比例，返回 null——
  /// 这种情况该显示「新增」而不是 100% 或 ∞。
  double? get ratio =>
      comparisonCents == 0 ? null : deltaCents / comparisonCents;
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

/// 「周期支出对比」的输入：一个时间区间 + 展示用短标签（如 "8月" / "本周"）。
class PeriodSpan {
  const PeriodSpan({required this.range, required this.label});

  final LedgerDateRange range;
  final String label;
}

/// 「周期支出对比」的一根柱：某个周期的支出/收入合计。
class PeriodBar {
  const PeriodBar({
    required this.label,
    required this.expenseCents,
    required this.incomeCents,
  });

  final String label;
  final int expenseCents;
  final int incomeCents;
}
