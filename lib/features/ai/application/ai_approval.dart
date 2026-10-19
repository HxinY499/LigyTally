/// AI 对账单做写操作之前，交给 UI 的一次人工确认。
///
/// 模型只负责提出动作；是否真的落库由这里拦住。读工具不需要经过它。
class ToolApprovalRequest {
  const ToolApprovalRequest({
    required this.toolName,
    required this.message,
    required this.confirmLabel,
    this.destructive = false,
  });

  final String toolName;
  final String message;
  final String confirmLabel;

  /// 删除类操作用危险色；新增/修改走品牌色。
  final bool destructive;
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
