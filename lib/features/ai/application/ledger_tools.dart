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
  LedgerToolService(this.database, this.ledgerService) {
    registry = ToolRegistry([
      _summaryTool().withExecutor((args) => summary(args)),
      _categoryBreakdownTool().withExecutor((args) => categoryBreakdown(args)),
      _searchTool().withExecutor((args) => searchTransactions(args)),
      _saveTool().withExecutor((args) => saveTransaction(args)),
      _updateTool().withExecutor((args) => updateTransaction(args)),
      _deleteTool().withExecutor((args) => deleteTransactions(args)),
    ]);
  }

  final AppDatabase database;
  final LedgerService ledgerService;
  late final ToolRegistry registry;

  static ToolSpec _summaryTool() => ToolSpec(
    name: 'get_cashflow_summary',
    description:
        '查询某个日期范围内的收入、支出、净额、账单笔数和有记录的天数。'
        '日期用 YYYY-MM-DD，from 和 to 都包含在范围内；按全部分类计算。'
        '所有金额单位都是分（例如 28.50 元是 2850）。',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'from': {'type': 'string', 'description': '开始日期 YYYY-MM-DD，含'},
        'to': {'type': 'string', 'description': '结束日期 YYYY-MM-DD，含'},
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
        'kind 只能是 expense 或 income；按全部分类计算，不沿用统计页排除项。'
        '金额单位是分。',
    parametersSchema: const {
      'type': 'object',
      'properties': {
        'from': {'type': 'string', 'description': '开始日期 YYYY-MM-DD，含'},
        'to': {'type': 'string', 'description': '结束日期 YYYY-MM-DD，含'},
        'kind': {
          'type': 'string',
          'enum': ['expense', 'income'],
        },
        'limit': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 20,
          'description': '返回前几类，默认 8',
        },
      },
      'required': ['from', 'to', 'kind'],
      'additionalProperties': false,
    },
    execute: null,
  );

  static ToolSpec _searchTool() => ToolSpec(
    name: 'search_transactions',
    description:
        '按日期范围、关键词、收支类型或分类查账单。用于定位用户说的某一笔/某一类账单，'
        '也是修改和删除前必须调用的一步。最多返回 30 条，超过时 truncated=true。'
        '不要凭记忆猜账单 id。',
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
        'query': {'type': 'string', 'description': '匹配备注或分类名的关键词，可省略'},
        'categoryId': {
          'type': 'string',
          'description': '分类 id；传一级分类时包含它的二级分类。必须来自系统提供的分类列表。',
        },
        'amountCents': {
          'type': 'integer',
          'minimum': 1,
          'description': '精确金额，单位分；用户说“那笔 28 元”时使用',
        },
        'limit': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 30,
          'description': '默认 20',
        },
      },
      'required': ['from', 'to'],
      'additionalProperties': false,
    },
    execute: null,
  );

  static ToolSpec _saveTool() => ToolSpec(
    name: 'save_transaction',
    description:
        '新增一笔账单。金额单位是分；用户说「午饭 28 元」就传 amountCents=2800。'
        'categoryId 必须来自系统提供的分类列表，且分类的收支类型必须与 kind 一致。'
        '这个工具会先弹给用户确认，不要在工具返回成功前声称已经记好。',
    parametersSchema: const {
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
          'description': '记账日 YYYY-MM-DD；用户说昨天就传昨天',
        },
        'note': {'type': 'string', 'maxLength': 200, 'description': '备注，可省略'},
        'occurredAt': {
          'type': 'string',
          'description': '发生时刻 ISO 8601，可省略；省略时按记账日推断',
        },
      },
      'required': ['kind', 'amountCents', 'categoryId', 'accountingDate'],
      'additionalProperties': false,
    },
    execute: null,
  );

  static ToolSpec _updateTool() => ToolSpec(
    name: 'update_transaction',
    description:
        '修改已经存在的一笔账单。必须先用 search_transactions 拿到 id，不要猜。'
        '一次只改一笔，只传要改的字段，没传的金额、分类、日期、备注保持原样。'
        '改日期传 accountingDate；改 kind 时必须同时传匹配的 categoryId。'
        '这个工具不改图片和位置。会先弹给用户确认，返回成功前不要说已经改好。'
        '金额单位是分。',
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
        'categoryId': {'type': 'string', 'description': '新分类 id，必须来自系统提供的分类列表'},
        'accountingDate': {
          'type': 'string',
          'description': '新的记账日 YYYY-MM-DD。改哪一天传这个，不要只改 occurredAt',
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
        '按账单 id 删除，最多 20 笔。调用前必须先用 search_transactions 找到确切账单，'
        '不能猜 id。这个工具会先弹给用户确认，用户确认后才真正删除。',
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

  /// 给待确认的写操作生成人话摘要；读工具返回 null。
  Future<ToolApprovalRequest?> describe(ToolCallPart call) async {
    switch (call.toolName) {
      case 'save_transaction':
        final draft = await _readSaveArgs(call.args);
        return ToolApprovalRequest(
          toolName: call.toolName,
          confirmLabel: '确认记账',
          title: '记一笔',
          bill: ToolApprovalBill(
            kind: draft.kind,
            amountCents: draft.amountCents,
            accountingDate: draft.accountingDate,
            categoryName: draft.category.name,
            note: draft.note,
          ),
          message:
              'AI 想记一笔：\n'
              '${draft.kind == 1 ? '收入' : '支出'} ${formatMoney(draft.amountCents)}'
              ' · ${draft.category.name}\n'
              '${dateKey(draft.accountingDate)}'
              '${draft.note.isEmpty ? '' : ' · ${draft.note}'}',
        );
      case 'update_transaction':
        final update = await _readUpdate(call.args);
        if (update.changes.isEmpty) return null;
        final kept = await _keptSideEffects(update.item);
        return ToolApprovalRequest(
          toolName: call.toolName,
          confirmLabel: '确认修改',
          title: '修改这笔',
          bill: ToolApprovalBill(
            kind: update.kind,
            amountCents: update.amountCents,
            accountingDate: update.accountingDate,
            categoryName: update.category.name,
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

  Future<Map<String, Object?>> summary(Map<String, Object?> args) async {
    final range = _range(args);
    final summary = await database.summaryIn(range);
    return {
      'from': dateKey(range.start),
      'to': dateKey(range.endExclusive.subtract(const Duration(days: 1))),
      'currency': 'CNY',
      'scope': 'all_categories',
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
    final totals = await database.categoryTotalsIn(range, kind);
    final totalCents = totals.fold<int>(
      0,
      (sum, item) => sum + item.totalCents,
    );
    final limit = (_optionalInt(args, 'limit', fallback: 8) ?? 8).clamp(1, 20);
    final visible = totals.take(limit).toList();
    return {
      'from': dateKey(range.start),
      'to': dateKey(range.endExclusive.subtract(const Duration(days: 1))),
      'kind': kind == 0 ? 'expense' : 'income',
      'currency': 'CNY',
      'scope': 'all_categories',
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

  Future<Map<String, Object?>> searchTransactions(
    Map<String, Object?> args,
  ) async {
    final range = _range(args);
    final kind = _optionalString(args, 'kind') ?? 'all';
    final wantedKind = kind == 'all' ? null : _kindCode(kind);
    final query = (_optionalString(args, 'query') ?? '').trim().toLowerCase();
    final categoryId = _optionalString(args, 'categoryId');
    final amountCents = _optionalInt(args, 'amountCents');
    final limit = (_optionalInt(args, 'limit', fallback: 20) ?? 20).clamp(
      1,
      30,
    );

    final all = await database.transactionsIn(range);
    final filtered =
        all.where((item) {
          if (wantedKind != null && item.transaction.kind != wantedKind) {
            return false;
          }
          if (categoryId != null &&
              item.category.id != categoryId &&
              item.category.parentId != categoryId) {
            return false;
          }
          if (amountCents != null &&
              item.transaction.amountCents != amountCents) {
            return false;
          }
          if (query.isNotEmpty) {
            final haystack = '${item.transaction.note}\n${item.category.name}'
                .toLowerCase();
            if (!haystack.contains(query)) return false;
          }
          return true;
        }).toList()..sort(
          (a, b) =>
              b.transaction.occurredAt.compareTo(a.transaction.occurredAt),
        );

    final visible = filtered.take(limit).toList();
    return {
      'from': dateKey(range.start),
      'to': dateKey(range.endExclusive.subtract(const Duration(days: 1))),
      'kind': kind,
      'currency': 'CNY',
      'totalMatches': filtered.length,
      'returned': visible.length,
      'truncated': filtered.length > visible.length,
      'transactions': [
        for (final item in visible)
          {
            'id': item.transaction.id,
            'accountingDate': item.transaction.accountingDate,
            'kind': item.transaction.kind == 0 ? 'expense' : 'income',
            'amountCents': item.transaction.amountCents,
            'categoryId': item.category.id,
            'categoryName': item.category.name,
            'note': item.transaction.note.length > 120
                ? '${item.transaction.note.substring(0, 120)}…'
                : item.transaction.note,
          },
      ],
    };
  }

  Future<Map<String, Object?>> saveTransaction(
    Map<String, Object?> args, {
    String? id,
  }) async {
    final draft = await _readSaveArgs(args);
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

  Future<Map<String, Object?>> updateTransaction(
    Map<String, Object?> args,
  ) async {
    final update = await _readUpdate(args);
    final tx = update.item.transaction;
    if (update.changes.isEmpty) {
      return _updateResult(update, changed: false);
    }
    final images = await database.imagesFor(tx.id);
    await ledgerService.save(
      existing: update.item,
      kind: update.kind,
      amountCents: update.amountCents,
      categoryId: update.category.id,
      accountingDate: update.accountingDate,
      occurredAt: update.occurredAt,
      note: update.note,
      place: PlaceFix.tryFrom(tx),
      pendingImages: const [],
      existingImages: images,
      removedImageIds: const {},
    );
    return _updateResult(update, changed: true);
  }

  Map<String, Object?> _updateResult(
    _TxnUpdate update, {
    required bool changed,
  }) {
    return {
      'ok': true,
      'changed': changed,
      'transactionId': update.item.transaction.id,
      'kind': update.kind == 0 ? 'expense' : 'income',
      'amountCents': update.amountCents,
      'categoryId': update.category.id,
      'categoryName': update.category.name,
      'accountingDate': dateKey(update.accountingDate),
      'note': update.note,
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

  Future<
    ({
      int kind,
      int amountCents,
      CategoryEntry category,
      DateTime accountingDate,
      DateTime occurredAt,
      String note,
    })
  >
  _readSaveArgs(Map<String, Object?> args) async {
    final kind = _kindCode(_requiredString(args, 'kind'));
    final amountCents = _requiredInt(args, 'amountCents');
    if (amountCents <= 0) {
      throw ArgumentError('amountCents 必须大于 0');
    }
    if (amountCents > 100000000) {
      throw ArgumentError('单笔金额过大，请核对 amountCents 是否按分填写');
    }
    final categoryId = _requiredString(args, 'categoryId');
    final category = await _findCategory(categoryId, kind);
    final accountingDate = _parseDate(_requiredString(args, 'accountingDate'));
    final note = (_optionalString(args, 'note') ?? '').trim();
    if (note.length > 200) {
      throw ArgumentError('备注不能超过 200 字');
    }
    final occurredText = _optionalString(args, 'occurredAt');
    DateTime occurredAt;
    if (occurredText == null || occurredText.isEmpty) {
      final now = DateTime.now();
      final today = dateOnly(now);
      occurredAt = accountingDate == today
          ? now
          : DateTime(
              accountingDate.year,
              accountingDate.month,
              accountingDate.day,
              12,
            );
    } else {
      final parsed = DateTime.tryParse(occurredText);
      if (parsed == null) {
        throw ArgumentError('occurredAt 不是合法的 ISO 8601 时间');
      }
      occurredAt = parsed;
    }
    return (
      kind: kind,
      amountCents: amountCents,
      category: category,
      accountingDate: accountingDate,
      occurredAt: occurredAt,
      note: note,
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

    final changes = <ToolApprovalChange>[];
    if (kind != tx.kind) {
      changes.add(
        ToolApprovalChange(
          label: '收支',
          before: _kindLabel(tx.kind),
          after: _kindLabel(kind),
        ),
      );
    }
    if (amountCents != tx.amountCents) {
      changes.add(
        ToolApprovalChange(
          label: '金额',
          before: formatMoney(tx.amountCents),
          after: formatMoney(amountCents),
        ),
      );
    }
    if (category.id != item.category.id) {
      changes.add(
        ToolApprovalChange(
          label: '分类',
          before: item.category.name,
          after: category.name,
        ),
      );
    }
    if (dateKey(accountingDate) != tx.accountingDate) {
      changes.add(
        ToolApprovalChange(
          label: '日期',
          before: tx.accountingDate,
          after: dateKey(accountingDate),
        ),
      );
    }
    if (formatClock(occurredAt) != formatClock(previousOccurred)) {
      changes.add(
        ToolApprovalChange(
          label: '时间',
          before: formatClock(previousOccurred),
          after: formatClock(occurredAt),
        ),
      );
    }
    if (note != tx.note) {
      changes.add(
        ToolApprovalChange(
          label: '备注',
          before: _noteLabel(tx.note),
          after: _noteLabel(note),
        ),
      );
    }
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

  String _noteLabel(String note) => note.isEmpty ? '（空）' : note;

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

  LedgerDateRange _range(Map<String, Object?> args) {
    final start = _parseDate(_requiredString(args, 'from'));
    final end = _parseDate(_requiredString(args, 'to'));
    if (end.isBefore(start)) {
      throw ArgumentError('to 不能早于 from');
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
}
