import 'package:flutter_ai_tools/flutter_ai_tools.dart';

import '../../../core/database/app_database.dart';
import '../../../core/location/place_fix.dart';
import '../../../core/utils/ledger_date.dart';
import '../../ledger/application/ledger_service.dart';
import 'ai_approval.dart';

/// AI 能看到的本地账目能力。
///
/// 所有数字都在这里用现有 Drift 查询算好，模型只负责选工具和组织语言。
/// 读工具返回聚合结果；写工具复用 [LedgerService]，保证图片目录等副作用
/// 与手动记账走同一条路径。
class LedgerToolService {
  LedgerToolService(
    this.database,
    this.ledgerService, {
    this.statsExcludedIds = const {},
  }) {
    registry = ToolRegistry([
      _summaryTool().withExecutor((args) => summary(args)).withUserDesc(),
      _categoryBreakdownTool()
          .withExecutor((args) => categoryBreakdown(args))
          .withUserDesc(),
      _trendTool().withExecutor((args) => spendingTrend(args)).withUserDesc(),
      _comparePeriodsTool()
          .withExecutor((args) => comparePeriods(args))
          .withUserDesc(),
      _searchTool()
          .withExecutor((args) => searchTransactions(args))
          .withUserDesc(),
      _saveBatchTool()
          .withExecutor((args) => saveTransactions(args))
          .withUserDesc(),
      _updateTool()
          .withExecutor((args) => updateTransaction(args))
          .withUserDesc(),
      _deleteTool()
          .withExecutor((args) => deleteTransactions(args))
          .withUserDesc(),
    ]);
  }

  final AppDatabase database;
  final LedgerService ledgerService;

  /// 用户在统计页配置的排除分类 id 集合。
  final Set<String> statsExcludedIds;

  late final ToolRegistry registry;

  static const _exclusionProps = <String, Object?>{
    'useStatsExclusion': {
      'type': 'boolean',
      'description': '为 true 时沿用用户在统计页设置的排除分类；默认 false（全部分类）',
    },
    'excludedCategoryIds': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': '临时排除的分类 id 列表（一级会连同其二级一起排除），可省略',
    },
  };

  static ToolSpec _summaryTool() => ToolSpec(
    name: 'get_cashflow_summary',
    description:
        '查询某个日期范围内的收入、支出、净额、账单笔数和有记录的天数。'
        '日期用 YYYY-MM-DD，from 和 to 都包含在范围内。金额单位是分。',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'from': {'type': 'string', 'description': '开始日期 YYYY-MM-DD，含'},
        'to': {'type': 'string', 'description': '结束日期 YYYY-MM-DD，含'},
        ..._exclusionProps,
      },
      'required': ['from', 'to'],
      'additionalProperties': false,
    },
    execute: null,
  );

  static ToolSpec _categoryBreakdownTool() => ToolSpec(
    name: 'get_category_breakdown',
    description:
        '查询某个日期范围内、支出或收入的分类排行和占比。'
        '不传 parentCategoryId 时返回一级分类排行（含已使用的二级细分）；'
        '传一级分类 id 到 parentCategoryId 时专门下钻该分类下的二级分类构成。金额单位是分。',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'from': {'type': 'string', 'description': '开始日期 YYYY-MM-DD，含'},
        'to': {'type': 'string', 'description': '结束日期 YYYY-MM-DD，含'},
        'kind': {
          'type': 'string',
          'enum': ['expense', 'income'],
        },
        'parentCategoryId': {
          'type': 'string',
          'description': '一级分类 id，用于查询其二级分类占比，可省略',
        },
        'limit': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 20,
          'description': '返回前几类，默认 8',
        },
        ..._exclusionProps,
      },
      'required': ['from', 'to', 'kind'],
      'additionalProperties': false,
    },
    execute: null,
  );

  static ToolSpec _trendTool() => ToolSpec(
    name: 'get_spending_trend',
    description:
        '查询日期范围内按天或按月聚合的收支时间序列，用于观察走势起伏或多月对比。'
        '可按单个分类（一级或二级）过滤。金额单位是分。',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'from': {'type': 'string', 'description': '开始日期 YYYY-MM-DD，含'},
        'to': {'type': 'string', 'description': '结束日期 YYYY-MM-DD，含'},
        'granularity': {
          'type': 'string',
          'enum': ['day', 'month'],
          'description': '聚合粒度：day 按天，month 按月；省略时超过 62 天自动按月',
        },
        'categoryId': {
          'type': 'string',
          'description': '限定某个分类 id（一级含其二级），可省略',
        },
        ..._exclusionProps,
      },
      'required': ['from', 'to'],
      'additionalProperties': false,
    },
    execute: null,
  );

  static ToolSpec _comparePeriodsTool() => ToolSpec(
    name: 'compare_periods',
    description:
        '对比两个不重叠日期区间（本期 vs 对照期）的总额变化及各一级分类增减排行。'
        '当期尚未结束时，对照期应取上一周期等长前缀以保证同口径对比。金额单位是分。',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'from': {'type': 'string', 'description': '本期开始日期 YYYY-MM-DD，含'},
        'to': {'type': 'string', 'description': '本期结束日期 YYYY-MM-DD，含'},
        'compareFrom': {
          'type': 'string',
          'description': '对照期开始日期 YYYY-MM-DD，含',
        },
        'compareTo': {
          'type': 'string',
          'description': '对照期结束日期 YYYY-MM-DD，含',
        },
        'kind': {
          'type': 'string',
          'enum': ['expense', 'income'],
          'description': '对比支出还是收入，默认 expense',
        },
        'limit': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 20,
          'description': '增减各返回前几类，默认 10',
        },
        ..._exclusionProps,
      },
      'required': ['from', 'to', 'compareFrom', 'compareTo'],
      'additionalProperties': false,
    },
    execute: null,
  );

  static ToolSpec _searchTool() => ToolSpec(
    name: 'search_transactions',
    description:
        '按日期范围、关键词（匹配备注/分类名/地点）、收支类型、分类、金额区间或排序方式查账单明细。'
        '修改和删除前必须先调用本工具拿到确切 id。最多返回 50 条，返回结果包含全部匹配项的合计金额。',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'from': {'type': 'string', 'description': '开始日期 YYYY-MM-DD，含'},
        'to': {'type': 'string', 'description': '结束日期 YYYY-MM-DD，含'},
        'kind': {
          'type': 'string',
          'enum': ['expense', 'income', 'all'],
          'description': '默认 all',
        },
        'query': {
          'type': 'string',
          'description': '匹配备注、分类名或地点名的关键词；多个词用空格分隔时需同时命中',
        },
        'categoryId': {
          'type': 'string',
          'description': '分类 id；传一级分类时包含它的二级分类',
        },
        'amountCents': {
          'type': 'integer',
          'minimum': 1,
          'description': '精确金额，单位分',
        },
        'minAmountCents': {
          'type': 'integer',
          'minimum': 1,
          'description': '最小金额（含），单位分；查大额消费时使用',
        },
        'maxAmountCents': {
          'type': 'integer',
          'minimum': 1,
          'description': '最大金额（含），单位分',
        },
        'sortBy': {
          'type': 'string',
          'enum': ['time_desc', 'time_asc', 'amount_desc', 'amount_asc'],
          'description': '排序方式：默认 time_desc（最新在前），查最贵账单用 amount_desc',
        },
        'limit': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
          'description': '默认 20，最大 50',
        },
      },
      'required': ['from', 'to'],
      'additionalProperties': false,
    },
    execute: null,
  );

  static ToolSpec _saveBatchTool() => ToolSpec(
    name: 'save_transactions',
    description:
        '新增一笔或多笔账单（1～20 笔）。记单笔传 1 项，记多笔放在同一个 items 数组一次提交。'
        '金额单位是分；categoryId 必须来自可用分类列表且与 kind 一致。'
        'App 会弹出可编辑确认框由用户核对或微调，返回成功前不要声称已经记好，最终回答以返回值为准。',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'items': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 20,
          'items': {
            'type': 'object',
            'properties': {
              'kind': {
                'type': 'string',
                'enum': ['expense', 'income'],
              },
              'amountCents': {
                'type': 'integer',
                'minimum': 1,
                'maximum': 100000000,
                'description': '金额，单位分',
              },
              'categoryId': {'type': 'string'},
              'accountingDate': {
                'type': 'string',
                'description': '记账日 YYYY-MM-DD',
              },
              'note': {
                'type': 'string',
                'maxLength': 200,
                'description': '备注，可省略',
              },
              'occurredAt': {
                'type': 'string',
                'description': '发生时刻 ISO 8601，可省略',
              },
            },
            'required': ['kind', 'amountCents', 'categoryId', 'accountingDate'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['items'],
      'additionalProperties': false,
    },
    execute: null,
  );

  static ToolSpec _updateTool() => ToolSpec(
    name: 'update_transaction',
    description:
        '修改已存在的一笔账单。必须先用 search_transactions 拿到 id。'
        '只传要改的字段，没传的保持原样；改日期传 accountingDate，改 kind 必须同时传匹配的 categoryId。'
        '不改图片和位置。App 会弹出可编辑确认框，返回成功前不要说已改好，最终回答以返回值为准。金额单位是分。',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'id': {'type': 'string', 'description': 'search_transactions 返回的账单 id'},
        'kind': {
          'type': 'string',
          'enum': ['expense', 'income'],
        },
        'amountCents': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 100000000,
          'description': '新金额，单位分',
        },
        'categoryId': {'type': 'string', 'description': '新分类 id'},
        'accountingDate': {
          'type': 'string',
          'description': '新的记账日 YYYY-MM-DD',
        },
        'note': {
          'type': 'string',
          'maxLength': 200,
          'description': '新备注。传空字符串会清空备注；不传则保留',
        },
        'occurredAt': {
          'type': 'string',
          'description': '新的发生时刻 ISO 8601。只改钟点时使用',
        },
      },
      'required': ['id'],
      'additionalProperties': false,
    },
    execute: null,
  );

  static ToolSpec _deleteTool() => ToolSpec(
    name: 'delete_transactions',
    description:
        '按账单 id 删除，最多 20 笔。调用前必须先用 search_transactions 找到确切账单。'
        '会先弹给用户确认，用户确认后才真正删除。',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'ids': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 1,
          'maxItems': 20,
        },
      },
      'required': ['ids'],
      'additionalProperties': false,
    },
    execute: null,
  );

  /// 给待确认的写操作生成人话摘要与可微调草稿；读工具返回 null。
  Future<ToolApprovalRequest?> describe(ToolCallPart call) async {
    switch (call.toolName) {
      case 'save_transactions':
      case 'save_transaction':
        final bills = await readSaveBills(
          call.args,
          toolCallId: call.toolCallId,
        );
        return buildSaveApprovalRequest(bills, toolName: call.toolName);
      case 'update_transaction':
        final update = await _readUpdate(call.args);
        if (update.changes.isEmpty) return null;
        final kept = await _keptSideEffects(update.item);
        return ToolApprovalRequest(
          toolName: call.toolName,
          confirmLabel: '确认修改',
          title: '修改这笔',
          originalItem: update.item,
          bill: ToolApprovalBill(
            kind: update.kind,
            amountCents: update.amountCents,
            categoryId: update.category.id,
            categoryName: update.category.name,
            categoryIconKey: update.category.iconKey,
            accountingDate: update.accountingDate,
            occurredAt: update.occurredAt,
            note: update.note,
          ),
          changes: update.changes,
          footnote: kept.isEmpty ? null : kept,
          message:
              'AI 想修改这笔账单：\n'
              '${_transactionLine(update.item)}\n'
              '${update.changes.map((change) => '${change.label} ${change.before} → ${change.after}').join('\n')}'
              '${kept.isEmpty ? '' : '\n$kept'}',
        );
      case 'delete_transactions':
        final items = await _readDeleteItems(call.args);
        final lines = items
            .take(8)
            .map(
              (item) =>
                  '${item.transaction.accountingDate} '
                  '${item.category.name} '
                  '${formatMoney(item.transaction.amountCents)}',
            )
            .join('\n');
        return ToolApprovalRequest(
          toolName: call.toolName,
          confirmLabel: '确认删除',
          destructive: true,
          message:
              'AI 想删除 ${items.length} 笔账单：\n$lines'
              '${items.length > 8 ? '\n…还有 ${items.length - 8} 笔' : ''}\n'
              '删除后不可恢复。',
        );
      default:
        return null;
    }
  }

  /// 为 1 笔或多笔待记账草稿构造确认请求（亦可供并行调用合并后统一弹窗）。
  ToolApprovalRequest buildSaveApprovalRequest(
    List<ToolApprovalBill> bills, {
    String toolName = 'save_transactions',
  }) {
    if (bills.length == 1) {
      final draft = bills.single;
      return ToolApprovalRequest(
        toolName: toolName,
        confirmLabel: '确认记账',
        title: '记一笔',
        bills: bills,
        message:
            'AI 想记一笔：\n'
            '${draft.kind == 1 ? '收入' : '支出'} ${formatMoney(draft.amountCents)}'
            ' · ${draft.categoryName}\n'
            '${dateKey(draft.accountingDate)}'
            '${draft.note.isEmpty ? '' : ' · ${draft.note}'}',
      );
    }
    final lines = bills
        .take(8)
        .map(
          (b) =>
              '${dateKey(b.accountingDate)} '
              '${b.categoryName} '
              '${formatMoney(b.amountCents)}',
        )
        .join('\n');
    return ToolApprovalRequest(
      toolName: toolName,
      confirmLabel: '确认记入 ${bills.length} 笔',
      title: '批量记账',
      bills: bills,
      message:
          'AI 想记入 ${bills.length} 笔账单：\n$lines'
          '${bills.length > 8 ? '\n…还有 ${bills.length - 8} 笔' : ''}',
    );
  }

  Future<Map<String, Object?>> summary(Map<String, Object?> args) async {
    final range = _range(args);
    final exclusion = await _resolveExclusion(args);
    final summary = await database.summaryIn(
      range,
      excludedCategoryIds: exclusion.ids,
    );
    return {
      'from': dateKey(range.start),
      'to': dateKey(range.endExclusive.subtract(const Duration(days: 1))),
      'currency': 'CNY',
      'scope': exclusion.scope,
      if (exclusion.names.isNotEmpty) 'excludedCategories': exclusion.names,
      'incomeCents': summary.incomeCents,
      'expenseCents': summary.expenseCents,
      'netCents': summary.netCents,
      'entryCount': summary.entryCount,
      'activeDayCount': summary.activeDayCount,
    };
  }

  Future<Map<String, Object?>> categoryBreakdown(
    Map<String, Object?> args,
  ) async {
    final range = _range(args);
    final kind = _kindCode(_requiredString(args, 'kind'));
    final limit = (_optionalInt(args, 'limit', fallback: 8) ?? 8).clamp(1, 20);
    final exclusion = await _resolveExclusion(args);
    final parentId = _optionalString(args, 'parentCategoryId')?.trim();

    if (parentId != null && parentId.isNotEmpty) {
      final parent = await _findAnyCategory(parentId, expectedKind: kind);
      final rootId = parent.level == 1 ? parent.id : (parent.parentId ?? parent.id);
      final totals = await database.subcategoryTotalsIn(
        range,
        rootCategoryId: rootId,
        kind: kind,
        excludedCategoryIds: exclusion.ids,
      );
      final totalCents = totals.fold<int>(0, (s, item) => s + item.totalCents);
      final visible = totals.take(limit).toList();
      return {
        'from': dateKey(range.start),
        'to': dateKey(range.endExclusive.subtract(const Duration(days: 1))),
        'kind': kind == 0 ? 'expense' : 'income',
        'parentCategoryId': rootId,
        'parentCategoryName': parent.name,
        'currency': 'CNY',
        'scope': exclusion.scope,
        if (exclusion.names.isNotEmpty) 'excludedCategories': exclusion.names,
        'totalCents': totalCents,
        'categories': [
          for (final item in visible)
            {
              'categoryId': item.categoryId,
              'name': item.name,
              'totalCents': item.totalCents,
              'entryCount': item.entryCount,
              'share': totalCents == 0 ? 0.0 : (item.totalCents / totalCents),
            },
        ],
        'truncated': totals.length > visible.length,
      };
    }

    final totals = await database.categoryTotalsIn(
      range,
      kind,
      excludedCategoryIds: exclusion.ids,
    );
    final subByRoot = await database.subcategoriesByRootIn(
      range,
      kind,
      excludedCategoryIds: exclusion.ids,
    );
    final totalCents = totals.fold<int>(
      0,
      (sum, item) => sum + item.totalCents,
    );
    final visible = totals.take(limit).toList();
    return {
      'from': dateKey(range.start),
      'to': dateKey(range.endExclusive.subtract(const Duration(days: 1))),
      'kind': kind == 0 ? 'expense' : 'income',
      'currency': 'CNY',
      'scope': exclusion.scope,
      if (exclusion.names.isNotEmpty) 'excludedCategories': exclusion.names,
      'totalCents': totalCents,
      'categories': [
        for (final item in visible)
          {
            'categoryId': item.categoryId,
            'name': item.name,
            'totalCents': item.totalCents,
            'entryCount': item.entryCount,
            'share': totalCents == 0 ? 0.0 : (item.totalCents / totalCents),
            if (subByRoot.containsKey(item.categoryId))
              'subcategories': [
                for (final sub in subByRoot[item.categoryId]!)
                  {
                    'categoryId': sub.categoryId,
                    'name': sub.name,
                    'totalCents': sub.totalCents,
                    'entryCount': sub.entryCount,
                    'share': item.totalCents == 0
                        ? 0.0
                        : (sub.totalCents / item.totalCents),
                  },
              ],
          },
      ],
      'truncated': totals.length > visible.length,
    };
  }

  Future<Map<String, Object?>> spendingTrend(Map<String, Object?> args) async {
    final range = _range(args);
    final rawGranularity = _optionalString(args, 'granularity')?.trim();
    final bool groupByMonth;
    if (rawGranularity == null || rawGranularity.isEmpty) {
      groupByMonth = range.dayCount > 62;
    } else if (rawGranularity == 'month') {
      groupByMonth = true;
    } else if (rawGranularity == 'day') {
      groupByMonth = false;
    } else {
      throw ArgumentError('granularity 只能是 day 或 month');
    }

    final categoryId = _optionalString(args, 'categoryId')?.trim();
    CategoryEntry? category;
    if (categoryId != null && categoryId.isNotEmpty) {
      category = await _findAnyCategory(categoryId);
    }
    final exclusion = await _resolveExclusion(args);
    final rawPoints = await database.trendIn(
      range,
      groupByMonth: groupByMonth,
      categoryId: category?.id,
      excludedCategoryIds: exclusion.ids,
    );

    final List<TrendPoint> points = groupByMonth
        ? _fillMonthlyPoints(range, rawPoints)
        : rawPoints;
    final totalExpense = points.fold<int>(0, (s, p) => s + p.expenseCents);
    final totalIncome = points.fold<int>(0, (s, p) => s + p.incomeCents);

    return {
      'from': dateKey(range.start),
      'to': dateKey(range.endExclusive.subtract(const Duration(days: 1))),
      'granularity': groupByMonth ? 'month' : 'day',
      'currency': 'CNY',
      'scope': exclusion.scope,
      if (exclusion.names.isNotEmpty) 'excludedCategories': exclusion.names,
      if (category != null) ...{
        'categoryId': category.id,
        'categoryName': category.name,
      },
      'totalExpenseCents': totalExpense,
      'totalIncomeCents': totalIncome,
      'netCents': totalIncome - totalExpense,
      'points': [
        for (final p in points)
          {
            'bucket': p.bucket,
            'expenseCents': p.expenseCents,
            'incomeCents': p.incomeCents,
            'netCents': p.incomeCents - p.expenseCents,
          },
      ],
    };
  }

  Future<Map<String, Object?>> comparePeriods(Map<String, Object?> args) async {
    final current = _range(args);
    final comparison = _rangeFromKeys(args, 'compareFrom', 'compareTo');
    if (current.start.isBefore(comparison.endExclusive) &&
        comparison.start.isBefore(current.endExclusive)) {
      throw ArgumentError('本期区间与对照期区间不能重叠');
    }
    final kindText = _optionalString(args, 'kind') ?? 'expense';
    final kind = _kindCode(kindText);
    final limit = (_optionalInt(args, 'limit', fallback: 10) ?? 10).clamp(1, 20);
    final exclusion = await _resolveExclusion(args);

    final currentSummary = await database.summaryIn(
      current,
      excludedCategoryIds: exclusion.ids,
    );
    final compareSummary = await database.summaryIn(
      comparison,
      excludedCategoryIds: exclusion.ids,
    );
    final deltas = await database.categoryDeltasIn(
      current: current,
      comparison: comparison,
      kind: kind,
      excludedCategoryIds: exclusion.ids,
    );

    final currentTotal = kind == 0
        ? currentSummary.expenseCents
        : currentSummary.incomeCents;
    final compareTotal = kind == 0
        ? compareSummary.expenseCents
        : compareSummary.incomeCents;
    final totalDelta = currentTotal - compareTotal;

    final increased = deltas.where((d) => d.deltaCents > 0).toList()
      ..sort((a, b) => b.deltaCents.compareTo(a.deltaCents));
    final decreased = deltas.where((d) => d.deltaCents < 0).toList()
      ..sort((a, b) => a.deltaCents.compareTo(b.deltaCents));

    Map<String, Object?> formatDelta(CategoryDelta d) => {
      'categoryId': d.categoryId,
      'name': d.name,
      'currentCents': d.currentCents,
      'comparisonCents': d.comparisonCents,
      'deltaCents': d.deltaCents,
      'deltaRatio': d.ratio,
      'status': d.comparisonCents == 0
          ? 'added'
          : (d.currentCents == 0 ? 'cleared' : 'changed'),
    };

    return {
      'period': {
        'from': dateKey(current.start),
        'to': dateKey(current.endExclusive.subtract(const Duration(days: 1))),
      },
      'comparePeriod': {
        'from': dateKey(comparison.start),
        'to': dateKey(comparison.endExclusive.subtract(const Duration(days: 1))),
      },
      'kind': kind == 0 ? 'expense' : 'income',
      'currency': 'CNY',
      'scope': exclusion.scope,
      if (exclusion.names.isNotEmpty) 'excludedCategories': exclusion.names,
      'summary': {
        'currentCents': currentTotal,
        'comparisonCents': compareTotal,
        'deltaCents': totalDelta,
        'deltaRatio': compareTotal == 0 ? null : totalDelta / compareTotal,
      },
      'increased': [for (final d in increased.take(limit)) formatDelta(d)],
      'decreased': [for (final d in decreased.take(limit)) formatDelta(d)],
      'truncated': increased.length > limit || decreased.length > limit,
    };
  }

  Future<Map<String, Object?>> searchTransactions(
    Map<String, Object?> args,
  ) async {
    final range = _range(args);
    final kind = _optionalString(args, 'kind') ?? 'all';
    final wantedKind = kind == 'all' ? null : _kindCode(kind);
    final rawQuery = (_optionalString(args, 'query') ?? '').trim().toLowerCase();
    final queryTokens = rawQuery.isEmpty
        ? const <String>[]
        : rawQuery.split(RegExp(r'\s+'));
    final categoryId = _optionalString(args, 'categoryId')?.trim();
    final amountCents = _optionalInt(args, 'amountCents');
    final minAmountCents = _optionalInt(args, 'minAmountCents');
    final maxAmountCents = _optionalInt(args, 'maxAmountCents');
    if (minAmountCents != null &&
        maxAmountCents != null &&
        minAmountCents > maxAmountCents) {
      throw ArgumentError('minAmountCents 不能大于 maxAmountCents');
    }
    final sortBy = _optionalString(args, 'sortBy') ?? 'time_desc';
    if (!const {
      'time_desc',
      'time_asc',
      'amount_desc',
      'amount_asc',
    }.contains(sortBy)) {
      throw ArgumentError(
        'sortBy 只能是 time_desc、time_asc、amount_desc 或 amount_asc',
      );
    }
    final limit = (_optionalInt(args, 'limit', fallback: 20) ?? 20).clamp(
      1,
      50,
    );

    final categoriesById = queryTokens.isEmpty
        ? const <String, CategoryEntry>{}
        : {for (final c in await database.exportCategories()) c.id: c};

    final all = await database.transactionsIn(range);
    final filtered = all.where((item) {
      final tx = item.transaction;
      if (wantedKind != null && tx.kind != wantedKind) {
        return false;
      }
      if (categoryId != null &&
          categoryId.isNotEmpty &&
          item.category.id != categoryId &&
          item.category.parentId != categoryId) {
        return false;
      }
      if (amountCents != null && tx.amountCents != amountCents) {
        return false;
      }
      if (minAmountCents != null && tx.amountCents < minAmountCents) {
        return false;
      }
      if (maxAmountCents != null && tx.amountCents > maxAmountCents) {
        return false;
      }
      if (queryTokens.isNotEmpty) {
        final parentName = item.category.parentId == null
            ? ''
            : (categoriesById[item.category.parentId!]?.name ?? '');
        final location = tx.locationName ?? '';
        final haystack =
            '${tx.note}\n${item.category.name}\n$parentName\n$location'
                .toLowerCase();
        if (!queryTokens.every(haystack.contains)) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (sortBy) {
        case 'time_asc':
          return a.transaction.occurredAt.compareTo(b.transaction.occurredAt);
        case 'amount_desc':
          final cmp = b.transaction.amountCents.compareTo(
            a.transaction.amountCents,
          );
          return cmp != 0
              ? cmp
              : b.transaction.occurredAt.compareTo(a.transaction.occurredAt);
        case 'amount_asc':
          final cmp = a.transaction.amountCents.compareTo(
            b.transaction.amountCents,
          );
          return cmp != 0
              ? cmp
              : b.transaction.occurredAt.compareTo(a.transaction.occurredAt);
        case 'time_desc':
        default:
          return b.transaction.occurredAt.compareTo(a.transaction.occurredAt);
      }
    });

    var matchedExpenseCents = 0;
    var matchedIncomeCents = 0;
    for (final item in filtered) {
      if (item.transaction.kind == 0) {
        matchedExpenseCents += item.transaction.amountCents;
      } else {
        matchedIncomeCents += item.transaction.amountCents;
      }
    }

    final visible = filtered.take(limit).toList();
    return {
      'from': dateKey(range.start),
      'to': dateKey(range.endExclusive.subtract(const Duration(days: 1))),
      'kind': kind,
      'sortBy': sortBy,
      'currency': 'CNY',
      'totalMatches': filtered.length,
      'matchedExpenseCents': matchedExpenseCents,
      'matchedIncomeCents': matchedIncomeCents,
      'returned': visible.length,
      'truncated': filtered.length > visible.length,
      'transactions': [
        for (final item in visible)
          {
            'id': item.transaction.id,
            'accountingDate': item.transaction.accountingDate,
            'time': formatClock(
              DateTime.fromMillisecondsSinceEpoch(item.transaction.occurredAt),
            ),
            'kind': item.transaction.kind == 0 ? 'expense' : 'income',
            'amountCents': item.transaction.amountCents,
            'categoryId': item.category.id,
            'categoryName': item.category.name,
            if (item.transaction.locationLabel != null)
              'location': item.transaction.locationLabel,
            'note': item.transaction.note.length > 120
                ? '${item.transaction.note.substring(0, 120)}…'
                : item.transaction.note,
          },
      ],
    };
  }

  /// 解析 `save_transactions`（或单笔 `save_transaction`）参数为待确认草稿列表。
  Future<List<ToolApprovalBill>> readSaveBills(
    Map<String, Object?> args, {
    String? toolCallId,
  }) async {
    final rawItems = args['items'];
    final List<Map<String, Object?>> maps;
    if (rawItems is List) {
      if (rawItems.isEmpty) {
        throw ArgumentError('items 不能为空');
      }
      if (rawItems.length > 20) {
        throw ArgumentError('一次最多记入 20 笔');
      }
      maps = [
        for (final entry in rawItems)
          if (entry is Map)
            entry.cast<String, Object?>()
          else
            throw ArgumentError('items 每一项必须是对象'),
      ];
    } else if (args.containsKey('amountCents')) {
      maps = [args];
    } else {
      throw ArgumentError('缺少 items 数组');
    }

    final categories = await database.exportCategories();
    final bills = <ToolApprovalBill>[];
    final cleanCallId = (toolCallId ?? '').trim();
    for (var i = 0; i < maps.length; i++) {
      final draft = _parseSingleDraft(maps[i], categories);
      final String? sourceKey;
      if (cleanCallId.isEmpty) {
        sourceKey = null;
      } else if (maps.length == 1) {
        sourceKey = cleanCallId;
      } else {
        sourceKey = '$cleanCallId-$i';
      }
      bills.add(
        ToolApprovalBill(
          kind: draft.kind,
          amountCents: draft.amountCents,
          categoryId: draft.category.id,
          categoryName: draft.category.name,
          categoryIconKey: draft.category.iconKey,
          accountingDate: draft.accountingDate,
          occurredAt: draft.occurredAt,
          note: draft.note,
          sourceKey: sourceKey,
        ),
      );
    }
    return bills;
  }

  /// 执行批量（或单笔）新增。直接调用时按参数原样落库。
  Future<Map<String, Object?>> saveTransactions(
    Map<String, Object?> args, {
    String? toolCallId,
  }) async {
    final bills = await readSaveBills(args, toolCallId: toolCallId);
    return commitSavedBills(bills, proposed: bills);
  }

  /// 单笔便捷入口。
  Future<Map<String, Object?>> saveTransaction(
    Map<String, Object?> args, {
    String? id,
  }) async {
    final categories = await database.exportCategories();
    final draft = _parseSingleDraft(args, categories);
    final savedId = await ledgerService.save(
      id: id,
      kind: draft.kind,
      amountCents: draft.amountCents,
      categoryId: draft.category.id,
      accountingDate: draft.accountingDate,
      occurredAt: draft.occurredAt,
      note: draft.note,
      pendingImages: const [],
      existingImages: const [],
      removedImageIds: const {},
    );
    return {
      'ok': true,
      'transactionId': savedId,
      'kind': draft.kind == 0 ? 'expense' : 'income',
      'amountCents': draft.amountCents,
      'categoryId': draft.category.id,
      'categoryName': draft.category.name,
      'accountingDate': dateKey(draft.accountingDate),
      'note': draft.note,
    };
  }

  /// 将用户在确认弹窗里最终勾选并可能微调过的 [confirmed] 草稿写入数据库。
  Future<Map<String, Object?>> commitSavedBills(
    List<ToolApprovalBill> confirmed, {
    required List<ToolApprovalBill> proposed,
  }) async {
    final proposedByKey = <String, ToolApprovalBill>{
      for (final b in proposed)
        if (b.sourceKey != null) b.sourceKey!: b,
    };
    final categories = await database.exportCategories();
    final savedRows = <Map<String, Object?>>[];
    var anyModified = false;

    for (var i = 0; i < confirmed.length; i++) {
      final bill = confirmed[i];
      if (bill.amountCents <= 0 || bill.amountCents > 100000000) {
        throw ArgumentError('金额不合法');
      }
      final category = _matchCategoryIn(categories, bill.categoryId, bill.kind);
      final note = bill.note.trim();
      if (note.length > 200) {
        throw ArgumentError('备注不能超过 200 字');
      }
      final occurredAt = _resolveOccurredAt(
        bill.accountingDate,
        bill.occurredAt,
      );
      final deterministicId = bill.sourceKey == null || bill.sourceKey!.isEmpty
          ? null
          : 'ai-${bill.sourceKey}';
      final savedId = await ledgerService.save(
        id: deterministicId,
        kind: bill.kind,
        amountCents: bill.amountCents,
        categoryId: category.id,
        accountingDate: bill.accountingDate,
        occurredAt: occurredAt,
        note: note,
        pendingImages: const [],
        existingImages: const [],
        removedImageIds: const {},
      );

      final origin = bill.sourceKey != null
          ? proposedByKey[bill.sourceKey!]
          : (i < proposed.length ? proposed[i] : null);
      final modified = origin != null && !bill.sameContentAs(origin);
      if (modified) anyModified = true;

      savedRows.add({
        'transactionId': savedId,
        'kind': bill.kind == 0 ? 'expense' : 'income',
        'amountCents': bill.amountCents,
        'categoryId': category.id,
        'categoryName': category.name,
        'accountingDate': dateKey(bill.accountingDate),
        'note': note,
        if (modified) 'modifiedByUser': true,
      });
    }

    final skipped = proposed.length - savedRows.length;
    return {
      'ok': true,
      'proposedCount': proposed.length,
      'savedCount': savedRows.length,
      if (skipped > 0) 'skippedByUserCount': skipped,
      if (anyModified) 'modifiedByUser': true,
      if (savedRows.length == 1) ...savedRows.single,
      'transactions': savedRows,
    };
  }

  Future<Map<String, Object?>> updateTransaction(
    Map<String, Object?> args,
  ) async {
    final update = await _readUpdate(args);
    if (update.changes.isEmpty) {
      return _updateResult(
        item: update.item,
        kind: update.kind,
        amountCents: update.amountCents,
        category: update.category,
        accountingDate: update.accountingDate,
        note: update.note,
        changed: false,
        modifiedByUser: false,
      );
    }
    final proposed = ToolApprovalBill(
      kind: update.kind,
      amountCents: update.amountCents,
      categoryId: update.category.id,
      categoryName: update.category.name,
      categoryIconKey: update.category.iconKey,
      accountingDate: update.accountingDate,
      occurredAt: update.occurredAt,
      note: update.note,
    );
    return commitUpdatedBill(
      item: update.item,
      confirmed: proposed,
      proposed: proposed,
    );
  }

  /// 将用户在改账确认框中确认（并可能再次微调）的结果写入数据库。
  Future<Map<String, Object?>> commitUpdatedBill({
    required LedgerItem item,
    required ToolApprovalBill confirmed,
    required ToolApprovalBill proposed,
  }) async {
    if (confirmed.amountCents <= 0 || confirmed.amountCents > 100000000) {
      throw ArgumentError('金额不合法');
    }
    final note = confirmed.note.trim();
    if (note.length > 200) {
      throw ArgumentError('备注不能超过 200 字');
    }
    final category = await _findCategory(confirmed.categoryId, confirmed.kind);
    final tx = item.transaction;
    final previousOccurred = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt);
    final baseClock = confirmed.occurredAt ?? previousOccurred;
    final occurredAt = DateTime(
      confirmed.accountingDate.year,
      confirmed.accountingDate.month,
      confirmed.accountingDate.day,
      baseClock.hour,
      baseClock.minute,
      baseClock.second,
    );
    final normalized = confirmed.copyWith(
      categoryName: category.name,
      occurredAt: occurredAt,
      note: note,
    );
    final changes = computeApprovalChanges(item, normalized);
    final modifiedByUser = !normalized.sameContentAs(proposed);

    if (changes.isEmpty) {
      return _updateResult(
        item: item,
        kind: confirmed.kind,
        amountCents: confirmed.amountCents,
        category: category,
        accountingDate: confirmed.accountingDate,
        note: note,
        changed: false,
        modifiedByUser: modifiedByUser,
      );
    }

    final images = await database.imagesFor(tx.id);
    await ledgerService.save(
      existing: item,
      kind: confirmed.kind,
      amountCents: confirmed.amountCents,
      categoryId: category.id,
      accountingDate: confirmed.accountingDate,
      occurredAt: occurredAt,
      note: note,
      place: PlaceFix.tryFrom(tx),
      pendingImages: const [],
      existingImages: images,
      removedImageIds: const {},
    );
    return _updateResult(
      item: item,
      kind: confirmed.kind,
      amountCents: confirmed.amountCents,
      category: category,
      accountingDate: confirmed.accountingDate,
      note: note,
      changed: true,
      modifiedByUser: modifiedByUser,
    );
  }

  Map<String, Object?> _updateResult({
    required LedgerItem item,
    required int kind,
    required int amountCents,
    required CategoryEntry category,
    required DateTime accountingDate,
    required String note,
    required bool changed,
    required bool modifiedByUser,
  }) {
    return {
      'ok': true,
      'changed': changed,
      if (modifiedByUser) 'modifiedByUser': true,
      'transactionId': item.transaction.id,
      'kind': kind == 0 ? 'expense' : 'income',
      'amountCents': amountCents,
      'categoryId': category.id,
      'categoryName': category.name,
      'accountingDate': dateKey(accountingDate),
      'note': note,
    };
  }

  Future<Map<String, Object?>> deleteTransactions(
    Map<String, Object?> args,
  ) async {
    final items = await _readDeleteItems(args);
    await ledgerService.deleteAll(items);
    return {
      'ok': true,
      'deletedCount': items.length,
      'transactions': [
        for (final item in items)
          {
            'id': item.transaction.id,
            'accountingDate': item.transaction.accountingDate,
            'amountCents': item.transaction.amountCents,
            'categoryName': item.category.name,
          },
      ],
    };
  }

  ({
    int kind,
    int amountCents,
    CategoryEntry category,
    DateTime accountingDate,
    DateTime occurredAt,
    String note,
  })
  _parseSingleDraft(
    Map<String, Object?> args,
    List<CategoryEntry> categories,
  ) {
    final kind = _kindCode(_requiredString(args, 'kind'));
    final amountCents = _requiredInt(args, 'amountCents');
    if (amountCents <= 0) {
      throw ArgumentError('amountCents 必须大于 0');
    }
    if (amountCents > 100000000) {
      throw ArgumentError('单笔金额过大，请核对 amountCents 是否按分填写');
    }
    final categoryId = _requiredString(args, 'categoryId');
    final category = _matchCategoryIn(categories, categoryId, kind);
    final accountingDate = _parseDate(_requiredString(args, 'accountingDate'));
    final note = (_optionalString(args, 'note') ?? '').trim();
    if (note.length > 200) {
      throw ArgumentError('备注不能超过 200 字');
    }
    final occurredText = _optionalString(args, 'occurredAt');
    DateTime? parsedOccurred;
    if (occurredText != null && occurredText.isNotEmpty) {
      parsedOccurred = DateTime.tryParse(occurredText);
      if (parsedOccurred == null) {
        throw ArgumentError('occurredAt 不是合法的 ISO 8601 时间');
      }
    }
    return (
      kind: kind,
      amountCents: amountCents,
      category: category,
      accountingDate: accountingDate,
      occurredAt: _resolveOccurredAt(accountingDate, parsedOccurred),
      note: note,
    );
  }

  DateTime _resolveOccurredAt(DateTime accountingDate, DateTime? explicit) {
    final day = dateOnly(accountingDate);
    if (explicit == null) {
      final now = DateTime.now();
      return day == dateOnly(now)
          ? now
          : DateTime(day.year, day.month, day.day, 12);
    }
    if (dateOnly(explicit) == day) return explicit;
    return DateTime(
      day.year,
      day.month,
      day.day,
      explicit.hour,
      explicit.minute,
      explicit.second,
    );
  }

  Future<_TxnUpdate> _readUpdate(Map<String, Object?> args) async {
    final id = _requiredString(args, 'id');
    final items = await database.transactionsByIds([id]);
    if (items.length != 1) {
      throw StateError('找不到这笔账单，请重新搜索确认');
    }
    final item = items.single;
    final tx = item.transaction;
    const patchKeys = [
      'kind',
      'amountCents',
      'categoryId',
      'accountingDate',
      'note',
      'occurredAt',
    ];
    if (!patchKeys.any(args.containsKey)) {
      throw ArgumentError('至少要改一个字段');
    }

    final hasKind = args.containsKey('kind');
    final kind = hasKind ? _kindCode(_requiredString(args, 'kind')) : tx.kind;
    if (hasKind && kind != tx.kind && !args.containsKey('categoryId')) {
      throw ArgumentError('改了收支类型就必须同时传入对应的 categoryId');
    }
    final amountCents = args.containsKey('amountCents')
        ? _requiredInt(args, 'amountCents')
        : tx.amountCents;
    if (amountCents <= 0) {
      throw ArgumentError('amountCents 必须大于 0');
    }
    if (amountCents > 100000000) {
      throw ArgumentError('单笔金额过大，请核对 amountCents 是否按分填写');
    }

    final category = args.containsKey('categoryId')
        ? await _findCategory(_requiredString(args, 'categoryId'), kind)
        : item.category;
    final previousOccurred = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt);
    final accountingDate = args.containsKey('accountingDate')
        ? _parseDate(_requiredString(args, 'accountingDate'))
        : _parseDate(tx.accountingDate);
    final DateTime occurredAt;
    if (args.containsKey('occurredAt')) {
      final parsed = DateTime.tryParse(_requiredString(args, 'occurredAt'));
      if (parsed == null) {
        throw ArgumentError('occurredAt 不是合法的 ISO 8601 时间');
      }
      occurredAt = parsed;
    } else if (dateKey(accountingDate) != tx.accountingDate) {
      // 只改记账日时，钟点跟着挪到新的那天，和手动编辑同一条规则。
      occurredAt = DateTime(
        accountingDate.year,
        accountingDate.month,
        accountingDate.day,
        previousOccurred.hour,
        previousOccurred.minute,
        previousOccurred.second,
      );
    } else {
      occurredAt = previousOccurred;
    }
    final note = args.containsKey('note')
        ? (_optionalString(args, 'note') ?? '').trim()
        : tx.note;
    if (note.length > 200) {
      throw ArgumentError('备注不能超过 200 字');
    }

    final changes = computeApprovalChanges(
      item,
      ToolApprovalBill(
        kind: kind,
        amountCents: amountCents,
        categoryId: category.id,
        categoryName: category.name,
        categoryIconKey: category.iconKey,
        accountingDate: accountingDate,
        occurredAt: occurredAt,
        note: note,
      ),
    );
    return _TxnUpdate(
      item: item,
      kind: kind,
      amountCents: amountCents,
      category: category,
      accountingDate: accountingDate,
      occurredAt: occurredAt,
      note: note,
      changes: changes,
    );
  }

  Future<({Set<String> ids, String scope, List<String> names})>
  _resolveExclusion(Map<String, Object?> args) async {
    final useStats = _optionalBool(args, 'useStatsExclusion') ?? false;
    final extraRaw = args['excludedCategoryIds'];
    final ids = <String>{
      if (useStats) ...statsExcludedIds,
      if (extraRaw is List)
        for (final entry in extraRaw)
          if (entry != null && entry.toString().trim().isNotEmpty)
            entry.toString().trim(),
    };
    if (ids.isEmpty) {
      return (
        ids: const <String>{},
        scope: 'all_categories',
        names: const <String>[],
      );
    }
    final categories = await database.exportCategories();
    final names = <String>[
      for (final c in categories)
        if (ids.contains(c.id)) c.name,
    ];
    final validIds = <String>{
      for (final c in categories)
        if (ids.contains(c.id)) c.id,
    };
    return (
      ids: validIds,
      scope: validIds.isEmpty ? 'all_categories' : 'excluded_categories',
      names: names,
    );
  }

  List<TrendPoint> _fillMonthlyPoints(
    LedgerDateRange range,
    List<TrendPoint> raw,
  ) {
    final byBucket = {for (final p in raw) p.bucket: p};
    final lastDay = range.endExclusive.subtract(const Duration(days: 1));
    final result = <TrendPoint>[];
    var cursor = DateTime(range.start.year, range.start.month);
    final endMonth = DateTime(lastDay.year, lastDay.month);
    while (!cursor.isAfter(endMonth)) {
      final bucket =
          '${cursor.year.toString().padLeft(4, '0')}-'
          '${cursor.month.toString().padLeft(2, '0')}';
      result.add(
        byBucket[bucket] ??
            TrendPoint(bucket: bucket, incomeCents: 0, expenseCents: 0),
      );
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return result;
  }

  Future<String> _keptSideEffects(LedgerItem item) async {
    final images = await database.imagesFor(item.transaction.id);
    final parts = <String>[
      if (images.isNotEmpty) '图片保留',
      if (item.transaction.locationLatitude != null &&
          item.transaction.locationLongitude != null)
        '位置保留',
    ];
    if (parts.isEmpty) return '';
    return '${parts.join('，')}。';
  }

  String _transactionLine(LedgerItem item) {
    final tx = item.transaction;
    final note = tx.note.trim();
    return '${tx.accountingDate} · ${_kindLabel(tx.kind)} · '
        '${item.category.name} · ${formatMoney(tx.amountCents)}'
        '${note.isEmpty ? '' : ' · $note'}';
  }

  String _kindLabel(int kind) => kind == 1 ? '收入' : '支出';

  Future<List<LedgerItem>> _readDeleteItems(Map<String, Object?> args) async {
    final raw = args['ids'];
    if (raw is! List || raw.isEmpty) {
      throw ArgumentError('ids 必须是非空数组');
    }
    final ids = raw.map((value) => value.toString()).toSet();
    if (ids.length > 20) {
      throw ArgumentError('一次最多删除 20 笔');
    }
    final items = await database.transactionsByIds(ids);
    if (items.length != ids.length) {
      final found = items.map((item) => item.transaction.id).toSet();
      final missing = ids.difference(found);
      throw StateError('有 ${missing.length} 笔账单已不存在，请重新搜索确认');
    }
    return items;
  }

  Future<CategoryEntry> _findCategory(String id, int kind) async {
    final categories = await database.exportCategories();
    return _matchCategoryIn(categories, id, kind);
  }

  CategoryEntry _matchCategoryIn(
    List<CategoryEntry> categories,
    String id,
    int kind,
  ) {
    CategoryEntry? found;
    for (final category in categories) {
      if (category.id == id) {
        found = category;
        break;
      }
    }
    if (found == null) {
      throw ArgumentError('分类 id 不存在，请从系统提供的分类列表中选择');
    }
    if (!found.isActive) {
      throw ArgumentError('分类「${found.name}」已停用，请换一个');
    }
    if (found.kind != kind) {
      throw ArgumentError('分类「${found.name}」的收支类型与 kind 不一致');
    }
    return found;
  }

  Future<CategoryEntry> _findAnyCategory(
    String id, {
    int? expectedKind,
  }) async {
    final categories = await database.exportCategories();
    for (final category in categories) {
      if (category.id == id) {
        if (expectedKind != null && category.kind != expectedKind) {
          throw ArgumentError('分类「${category.name}」的收支类型与 kind 不一致');
        }
        return category;
      }
    }
    throw ArgumentError('分类 id 不存在：$id');
  }

  LedgerDateRange _range(Map<String, Object?> args) =>
      _rangeFromKeys(args, 'from', 'to');

  LedgerDateRange _rangeFromKeys(
    Map<String, Object?> args,
    String fromKey,
    String toKey,
  ) {
    final start = _parseDate(_requiredString(args, fromKey));
    final end = _parseDate(_requiredString(args, toKey));
    if (end.isBefore(start)) {
      throw ArgumentError('$toKey 不能早于 $fromKey');
    }
    final endExclusive = end.add(const Duration(days: 1));
    if (endExclusive.difference(start).inDays > 3660) {
      throw ArgumentError('日期范围太大，请缩小到 10 年以内');
    }
    return LedgerDateRange(start, endExclusive);
  }

  DateTime _parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw ArgumentError('日期必须是 YYYY-MM-DD');
    }
    final parts = value.split('-').map(int.parse).toList();
    final parsed = DateTime(parts[0], parts[1], parts[2]);
    // DateTime 会把 2026-02-30 滚到 3 月；记账日期必须原样成立。
    if (parsed.year != parts[0] ||
        parsed.month != parts[1] ||
        parsed.day != parts[2]) {
      throw ArgumentError('日期不合法：$value');
    }
    return parsed;
  }

  int _kindCode(String value) => switch (value) {
    'expense' => 0,
    'income' => 1,
    _ => throw ArgumentError('kind 只能是 expense 或 income'),
  };

  String _requiredString(Map<String, Object?> args, String key) {
    final value = _optionalString(args, key);
    if (value == null || value.trim().isEmpty) {
      throw ArgumentError('缺少 $key');
    }
    return value.trim();
  }

  String? _optionalString(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  bool? _optionalBool(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) {
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    throw ArgumentError('$key 必须是布尔值');
  }

  int _requiredInt(Map<String, Object?> args, String key) {
    final value = _optionalInt(args, key);
    if (value == null) throw ArgumentError('缺少 $key');
    return value;
  }

  int? _optionalInt(Map<String, Object?> args, String key, {int? fallback}) {
    final value = args[key];
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) {
      final parsed = int.tryParse(value.replaceAll(',', '').trim());
      if (parsed != null) return parsed;
    }
    throw ArgumentError('$key 必须是整数');
  }
}

class _TxnUpdate {
  const _TxnUpdate({
    required this.item,
    required this.kind,
    required this.amountCents,
    required this.category,
    required this.accountingDate,
    required this.occurredAt,
    required this.note,
    required this.changes,
  });

  final LedgerItem item;
  final int kind;
  final int amountCents;
  final CategoryEntry category;
  final DateTime accountingDate;
  final DateTime occurredAt;
  final String note;
  final List<ToolApprovalChange> changes;
}

extension on ToolSpec {
  ToolSpec withExecutor(ToolExecutor executor) => ToolSpec(
    name: name,
    description: description,
    parametersSchema: parametersSchema,
    execute: executor,
  );

  /// 每个工具都要求模型写一句给用户看的 desc。校验不通过会打回重写。
  ToolSpec withUserDesc() => ToolSpec(
    name: name,
    description:
        '$description 每次调用都必须带 desc：给用户看的一句简短中文，'
        '说明这次在做什么，不要写工具名或参数名。',
    parametersSchema: _schemaWithDesc(parametersSchema),
    execute: execute,
  );
}

Map<String, Object?> _schemaWithDesc(Map<String, Object?> schema) {
  final properties = Map<String, Object?>.from(
    (schema['properties'] as Map?)?.cast<String, Object?>() ?? const {},
  );
  properties['desc'] = const {
    'type': 'string',
    'maxLength': 40,
    'description': '给用户看的一句话，说明这次调用在做什么。简短中文，不要写工具名。',
  };
  final required = <Object?>[...((schema['required'] as List?) ?? const [])];
  if (!required.contains('desc')) required.add('desc');
  return {...schema, 'properties': properties, 'required': required};
}
