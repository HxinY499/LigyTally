import '../../../core/database/app_database.dart';
import '../../../core/utils/ledger_date.dart';

/// AI 对账单做写操作之前，交给 UI 的一次人工确认。
///
/// 模型只负责提出草稿；用户可在弹窗里直接微调金额、分类、日期、备注，
/// 或在批量记账清单里取消勾选部分条目，最终落库与回传给模型的结果均以
/// [ToolApprovalDecision] 为准。
class ToolApprovalRequest {
  ToolApprovalRequest({
    required this.toolName,
    required this.message,
    required this.confirmLabel,
    this.destructive = false,
    this.title,
    ToolApprovalBill? bill,
    List<ToolApprovalBill>? bills,
    this.originalItem,
    this.changes = const [],
    this.footnote,
  }) : bills = bills ?? (bill == null ? const [] : [bill]);

  final String toolName;
  final String message;
  final String confirmLabel;

  /// 删除类操作用危险色；新增/修改走品牌色。
  final bool destructive;

  /// 弹窗标题。
  final String? title;

  /// 待确认的账单草稿（单笔为 1 项，批量记账为多项，删除为空）。
  final List<ToolApprovalBill> bills;

  /// 单笔新增/修改时的快捷访问。
  ToolApprovalBill? get bill => bills.length == 1 ? bills.single : null;

  bool get isBatch => bills.length > 1;

  /// 修改账单时的原始记录，供弹窗就地微调后实时重算变动列表。
  final LedgerItem? originalItem;

  /// 改账时初始变动的字段。旧值在前，新值在后。
  final List<ToolApprovalChange> changes;

  /// 卡片下方的淡字，例如图片和位置会保留。
  final String? footnote;
}

/// 确认框里可就地微调的一笔账单草稿。
class ToolApprovalBill {
  const ToolApprovalBill({
    required this.kind,
    required this.amountCents,
    this.categoryId = '',
    required this.categoryName,
    this.categoryIconKey = 'other',
    required this.accountingDate,
    this.occurredAt,
    required this.note,
    this.sourceKey,
  });

  /// 0 支出，1 收入。
  final int kind;
  final int amountCents;
  final String categoryId;
  final String categoryName;
  final String categoryIconKey;
  final DateTime accountingDate;
  final DateTime? occurredAt;
  final String note;

  /// 关联回原始 toolCallId 与条目下标，用于重试幂等与多调用合并。
  final String? sourceKey;

  ToolApprovalBill copyWith({
    int? kind,
    int? amountCents,
    String? categoryId,
    String? categoryName,
    String? categoryIconKey,
    DateTime? accountingDate,
    DateTime? occurredAt,
    bool clearOccurredAt = false,
    String? note,
    String? sourceKey,
  }) {
    return ToolApprovalBill(
      kind: kind ?? this.kind,
      amountCents: amountCents ?? this.amountCents,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      categoryIconKey: categoryIconKey ?? this.categoryIconKey,
      accountingDate: accountingDate ?? this.accountingDate,
      occurredAt: clearOccurredAt ? null : (occurredAt ?? this.occurredAt),
      note: note ?? this.note,
      sourceKey: sourceKey ?? this.sourceKey,
    );
  }

  /// 判断用户是否在弹窗中改动了模型提交的草稿。
  bool sameContentAs(ToolApprovalBill other) {
    final sameCat = (categoryId.isNotEmpty && other.categoryId.isNotEmpty)
        ? categoryId == other.categoryId
        : categoryName == other.categoryName;
    final sameClock = (occurredAt == null || other.occurredAt == null)
        ? true
        : formatClock(occurredAt!) == formatClock(other.occurredAt!);
    return kind == other.kind &&
        amountCents == other.amountCents &&
        sameCat &&
        dateKey(accountingDate) == dateKey(other.accountingDate) &&
        sameClock &&
        note.trim() == other.note.trim();
  }
}

/// 改账确认里的一行变动。
class ToolApprovalChange {
  const ToolApprovalChange({
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final String before;
  final String after;
}

/// 根据原始账单与最新草稿计算变动项。
List<ToolApprovalChange> computeApprovalChanges(
  LedgerItem original,
  ToolApprovalBill next,
) {
  final tx = original.transaction;
  final previousOccurred = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt);
  final targetDateKey = dateKey(next.accountingDate);
  final nextOccurred = next.occurredAt ?? previousOccurred;
  final nextNote = next.note.trim();

  String kindLabel(int k) => k == 1 ? '收入' : '支出';
  String noteLabel(String n) => n.isEmpty ? '（空）' : n;

  final changes = <ToolApprovalChange>[];
  if (next.kind != tx.kind) {
    changes.add(
      ToolApprovalChange(
        label: '收支',
        before: kindLabel(tx.kind),
        after: kindLabel(next.kind),
      ),
    );
  }
  if (next.amountCents != tx.amountCents) {
    changes.add(
      ToolApprovalChange(
        label: '金额',
        before: formatMoney(tx.amountCents),
        after: formatMoney(next.amountCents),
      ),
    );
  }
  final catChanged = next.categoryId.isNotEmpty
      ? next.categoryId != original.category.id
      : next.categoryName != original.category.name;
  if (catChanged) {
    changes.add(
      ToolApprovalChange(
        label: '分类',
        before: original.category.name,
        after: next.categoryName,
      ),
    );
  }
  if (targetDateKey != tx.accountingDate) {
    changes.add(
      ToolApprovalChange(
        label: '日期',
        before: tx.accountingDate,
        after: targetDateKey,
      ),
    );
  }
  if (formatClock(nextOccurred) != formatClock(previousOccurred)) {
    changes.add(
      ToolApprovalChange(
        label: '时间',
        before: formatClock(previousOccurred),
        after: formatClock(nextOccurred),
      ),
    );
  }
  if (nextNote != tx.note) {
    changes.add(
      ToolApprovalChange(
        label: '备注',
        before: noteLabel(tx.note),
        after: noteLabel(nextNote),
      ),
    );
  }
  return changes;
}

/// 用户在确认弹窗上的最终决定。
class ToolApprovalDecision {
  const ToolApprovalDecision.cancelled() : approved = false, bills = const [];

  const ToolApprovalDecision.approved([this.bills = const []])
    : approved = true;

  final bool approved;

  /// 经用户确认（可能微调或部分取消勾选后）要执行的账单草稿。
  final List<ToolApprovalBill> bills;
}

typedef ToolApprovalHandler =
    Future<ToolApprovalDecision> Function(ToolApprovalRequest request);

/// 把工具执行层和页面弹窗解耦的薄桥。
///
/// 页面在 initState 里装 handler，dispose 时清掉。没有 handler 时一律拒绝，
/// 绝不能让写操作在用户看不见的地方偷偷执行。
class ToolApprovalCoordinator {
  ToolApprovalHandler? handler;

  Future<ToolApprovalDecision> request(ToolApprovalRequest request) async {
    final current = handler;
    if (current == null) return const ToolApprovalDecision.cancelled();
    return current(request);
  }
}
