/// AI 对账单做写操作之前，交给 UI 的一次人工确认。
///
/// 模型只负责提出动作；是否真的落库由这里拦住。读工具不需要经过它。
/// 记账和改账带 [bill]，确认框按账单卡排；删除只有 [message]。
class ToolApprovalRequest {
  const ToolApprovalRequest({
    required this.toolName,
    required this.message,
    required this.confirmLabel,
    this.destructive = false,
    this.title,
    this.bill,
    this.changes = const [],
    this.footnote,
  });

  final String toolName;
  final String message;
  final String confirmLabel;

  /// 删除类操作用危险色；新增/修改走品牌色。
  final bool destructive;

  /// 账单卡标题。有 [bill] 时使用。
  final String? title;

  /// 确认后账单应有的样子。记账是新账，改账是改完后的样子。
  final ToolApprovalBill? bill;

  /// 改账时实际变动的字段。旧值在前，新值在后。
  final List<ToolApprovalChange> changes;

  /// 卡片下方的淡字，例如图片和位置会保留。
  final String? footnote;
}

/// 确认框上那张账单卡的结果态。
class ToolApprovalBill {
  const ToolApprovalBill({
    required this.kind,
    required this.amountCents,
    required this.accountingDate,
    required this.categoryName,
    required this.note,
  });

  /// 0 支出，1 收入。
  final int kind;
  final int amountCents;
  final DateTime accountingDate;
  final String categoryName;
  final String note;
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

typedef ToolApprovalHandler =
    Future<bool> Function(ToolApprovalRequest request);

/// 把工具执行层和页面弹窗解耦的薄桥。
///
/// 页面在 initState 里装 handler，dispose 时清掉。没有 handler 时一律拒绝，
/// 绝不能让写操作在用户看不见的地方偷偷执行。
class ToolApprovalCoordinator {
  ToolApprovalHandler? handler;

  Future<bool> request(ToolApprovalRequest request) async {
    final current = handler;
    if (current == null) return false;
    return current(request);
  }
}
