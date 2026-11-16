import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../../core/appearance/appearance_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/amount_expression.dart';
import '../application/ai_approval.dart';

/// 记账 / 批量记账 / 改账的可微调确认弹窗。
///
/// 单笔展示大字金额 + 可点击的收支、日期、分类、备注胶囊，点任意一项就地修改；
/// 多笔展示带勾选框与汇总的批量清单，可勾选剔除或点进单条微调。
/// 返回 [ToolApprovalDecision]，由调用方将修正后的终态落库并回传给模型。
Future<ToolApprovalDecision> showAiBillConfirmDialog(
  BuildContext context,
  ToolApprovalRequest request, {
  List<CategoryEntry> categories = const [],
}) async {
  final activeCategories = categories.where((c) => c.isActive).toList();
  final decision = await showDialog<ToolApprovalDecision>(
    context: context,
    builder: (dialogContext) => request.isBatch
        ? _BatchBillConfirmDialog(
            request: request,
            categories: activeCategories,
          )
        : _SingleBillConfirmDialog(
            request: request,
            categories: activeCategories,
          ),
  );
  return decision ?? const ToolApprovalDecision.cancelled();
}

class _SingleBillConfirmDialog extends StatefulWidget {
  const _SingleBillConfirmDialog({
    required this.request,
    required this.categories,
    this.confirmLabelOverride,
  });

  final ToolApprovalRequest request;
  final List<CategoryEntry> categories;
  final String? confirmLabelOverride;

  @override
  State<_SingleBillConfirmDialog> createState() =>
      _SingleBillConfirmDialogState();
}

class _SingleBillConfirmDialogState extends State<_SingleBillConfirmDialog> {
  late ToolApprovalBill _bill = widget.request.bills.single;

  List<ToolApprovalChange> get _changes {
    final original = widget.request.originalItem;
    if (original != null) {
      return computeApprovalChanges(original, _bill);
    }
    return widget.request.changes;
  }

  bool get _canConfirm {
    if (_bill.amountCents <= 0) return false;
    if (widget.request.originalItem != null) {
      return _changes.isNotEmpty;
    }
    return true;
  }

  Future<void> _editAmount() async {
    final nextCents = await _showAmountEditSheet(
      context,
      initialCents: _bill.amountCents,
      kind: _bill.kind,
    );
    if (nextCents == null || !mounted) return;
    setState(() => _bill = _bill.copyWith(amountCents: nextCents));
  }

  Future<void> _editKindOrCategory({int? initialKind}) async {
    if (widget.categories.isEmpty) return;
    final picked = await _showCategoryEditSheet(
      context,
      categories: widget.categories,
      initialKind: initialKind ?? _bill.kind,
      initialCategoryId: _bill.categoryId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _bill = _bill.copyWith(
        kind: picked.kind,
        categoryId: picked.id,
        categoryName: picked.name,
        categoryIconKey: picked.iconKey,
      );
    });
  }

  Future<void> _editDate() async {
    final picked = await showAppDatePicker(
      context,
      initial: _bill.accountingDate,
    );
    if (picked == null || !mounted) return;
    final day = dateOnly(picked);
    final prevOccurred = _bill.occurredAt;
    final nextOccurred = prevOccurred == null
        ? null
        : DateTime(
            day.year,
            day.month,
            day.day,
            prevOccurred.hour,
            prevOccurred.minute,
            prevOccurred.second,
          );
    setState(() {
      _bill = _bill.copyWith(accountingDate: day, occurredAt: nextOccurred);
    });
  }

  Future<void> _editNote() async {
    final nextNote = await _showNoteEditSheet(context, initial: _bill.note);
    if (nextNote == null || !mounted) return;
    setState(() => _bill = _bill.copyWith(note: nextNote));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = _bill.kind == 1 ? colors.income : colors.expense;
    final toneSoft = _bill.kind == 1 ? colors.incomeSoft : colors.expenseSoft;
    final changes = _changes;
    final canSwitchCategory = widget.categories.isNotEmpty;
    final oppositeKind = _bill.kind == 0 ? 1 : 0;
    final hasOppositeKind = widget.categories.any((c) => c.kind == oppositeKind);

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: context.radii.sheetAll),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.request.title ?? '记一笔',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              key: const ValueKey('confirm-edit-amount'),
              onTap: _editAmount,
              borderRadius: context.radii.chipAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatMoney(_bill.amountCents),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: tone,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      FLucideIcons.pencil,
                      size: 14,
                      color: tone.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              key: const ValueKey('confirm-edit-kind'),
              onTap: canSwitchCategory && hasOppositeKind
                  ? () => _editKindOrCategory(initialKind: oppositeKind)
                  : null,
              borderRadius: context.radii.chipAll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: toneSoft,
                  borderRadius: context.radii.chipAll,
                ),
                child: Text(
                  _bill.kind == 1 ? '收入' : '支出',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tone,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                _EditableChip(
                  chipKey: const ValueKey('confirm-edit-date'),
                  icon: FLucideIcons.calendarDays,
                  label: _billDate(_bill.accountingDate),
                  onTap: _editDate,
                ),
                _EditableChip(
                  chipKey: const ValueKey('confirm-edit-category'),
                  leading: CategoryIconBadge(
                    iconKey: _bill.categoryIconKey,
                    color: tone,
                    background: toneSoft,
                    diameter: 20,
                  ),
                  label: _bill.categoryName,
                  showChevron: canSwitchCategory,
                  onTap: canSwitchCategory ? () => _editKindOrCategory() : null,
                ),
                _EditableChip(
                  chipKey: const ValueKey('confirm-edit-note'),
                  icon: FLucideIcons.pencil,
                  label: _bill.note.trim().isEmpty
                      ? '添加备注'
                      : _bill.note.trim(),
                  muted: _bill.note.trim().isEmpty,
                  onTap: _editNote,
                ),
              ],
            ),
            if (changes.isNotEmpty) ...[
              const SizedBox(height: 16),
              _ChangeList(changes: changes),
            ],
            if (widget.request.footnote != null &&
                widget.request.footnote!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                widget.request.footnote!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: colors.inactive,
                ),
              ),
            ],
            const SizedBox(height: 22),
            AppConfirmButtons(
              confirmLabel:
                  widget.confirmLabelOverride ?? widget.request.confirmLabel,
              onConfirm: _canConfirm
                  ? () => Navigator.pop(
                      context,
                      ToolApprovalDecision.approved([_bill]),
                    )
                  : null,
              onCancel: () =>
                  Navigator.pop(context, const ToolApprovalDecision.cancelled()),
              accent: colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchBillConfirmDialog extends StatefulWidget {
  const _BatchBillConfirmDialog({
    required this.request,
    required this.categories,
  });

  final ToolApprovalRequest request;
  final List<CategoryEntry> categories;

  @override
  State<_BatchBillConfirmDialog> createState() =>
      _BatchBillConfirmDialogState();
}

class _BatchBillConfirmDialogState extends State<_BatchBillConfirmDialog> {
  late final List<ToolApprovalBill> _bills = List.of(widget.request.bills);
  late final Set<int> _selected = {
    for (var i = 0; i < widget.request.bills.length; i++) i,
  };

  void _toggle(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.add(index)) _selected.remove(index);
    });
  }

  void _toggleAll() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.length == _bills.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(Iterable<int>.generate(_bills.length));
      }
    });
  }

  Future<void> _editItem(int index) async {
    final item = _bills[index];
    final singleRequest = ToolApprovalRequest(
      toolName: widget.request.toolName,
      message: '',
      confirmLabel: '保存修改',
      title: '调整第 ${index + 1} 笔',
      bill: item,
    );
    final decision = await showDialog<ToolApprovalDecision>(
      context: context,
      builder: (_) => _SingleBillConfirmDialog(
        request: singleRequest,
        categories: widget.categories,
        confirmLabelOverride: '保存修改',
      ),
    );
    if (decision == null ||
        !decision.approved ||
        decision.bills.isEmpty ||
        !mounted) {
      return;
    }
    setState(() {
      _bills[index] = decision.bills.single;
      _selected.add(index);
    });
  }

  String _summaryText() {
    var expense = 0;
    var income = 0;
    for (final index in _selected) {
      final b = _bills[index];
      if (b.kind == 0) {
        expense += b.amountCents;
      } else {
        income += b.amountCents;
      }
    }
    final parts = <String>['已选 ${_selected.length}/${_bills.length} 笔'];
    if (expense > 0) parts.add('支 ${formatMoney(expense)}');
    if (income > 0) parts.add('收 ${formatMoney(income)}');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final allSelected = _selected.length == _bills.length;
    final count = _selected.length;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: context.radii.sheetAll),
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.request.title ?? '批量记账',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _summaryText(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: colors.muted),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      allSelected ? '取消全选' : '全选',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.44,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.fill,
                  borderRadius: context.radii.blockAll,
                ),
                child: ClipRRect(
                  borderRadius: context.radii.blockAll,
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _bills.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      thickness: 1,
                      indent: 42,
                      endIndent: 12,
                      color: colors.lineSoft,
                    ),
                    itemBuilder: (context, index) {
                      final bill = _bills[index];
                      final checked = _selected.contains(index);
                      final isExpense = bill.kind == 0;
                      final tone = isExpense ? colors.expense : colors.income;
                      final soft = isExpense
                          ? colors.expenseSoft
                          : colors.incomeSoft;
                      final meta = [
                        _billDate(bill.accountingDate),
                        if (bill.note.trim().isNotEmpty) bill.note.trim(),
                      ].join(' · ');

                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: checked ? 1 : 0.45,
                        child: Row(
                          children: [
                            InkWell(
                              key: ValueKey('batch-check-$index'),
                              onTap: () => _toggle(index),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  12,
                                  6,
                                  12,
                                ),
                                child: Icon(
                                  checked
                                      ? FLucideIcons.squareCheck
                                      : FLucideIcons.square,
                                  size: 20,
                                  color: checked
                                      ? colors.primary
                                      : colors.inactive,
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                key: ValueKey('batch-row-$index'),
                                onTap: () => _editItem(index),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    10,
                                    10,
                                    10,
                                  ),
                                  child: Row(
                                    children: [
                                      CategoryIconBadge(
                                        iconKey: bill.categoryIconKey,
                                        color: tone,
                                        background: soft,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              bill.categoryName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: colors.ink,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              meta,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: colors.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${isExpense ? '-' : '+'}${formatMoney(bill.amountCents)}',
                                        style: AppText.money(
                                          14.5,
                                          color: tone,
                                          weight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        FLucideIcons.pencil,
                                        size: 12,
                                        color: colors.inactive,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            AppConfirmButtons(
              confirmLabel: count == 0 ? '请至少勾选 1 笔' : '确认记入 $count 笔',
              onConfirm: count == 0
                  ? null
                  : () => Navigator.pop(
                      context,
                      ToolApprovalDecision.approved([
                        for (var i = 0; i < _bills.length; i++)
                          if (_selected.contains(i)) _bills[i],
                      ]),
                    ),
              onCancel: () =>
                  Navigator.pop(context, const ToolApprovalDecision.cancelled()),
              accent: colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableChip extends StatelessWidget {
  const _EditableChip({
    this.chipKey,
    this.icon,
    this.leading,
    required this.label,
    this.muted = false,
    this.showChevron = false,
    this.onTap,
  });

  final Key? chipKey;
  final IconData? icon;
  final Widget? leading;
  final String label;
  final bool muted;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.fill,
      borderRadius: context.radii.chipAll,
      child: InkWell(
        key: chipKey,
        onTap: onTap,
        borderRadius: context.radii.chipAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
                Icon(icon, size: 13, color: colors.muted),
                const SizedBox(width: 5),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: muted ? colors.inactive : colors.ink,
                  ),
                ),
              ),
              if (showChevron) ...[
                const SizedBox(width: 2),
                Icon(FLucideIcons.chevronDown, size: 13, color: colors.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeList extends StatelessWidget {
  const _ChangeList({required this.changes});

  final List<ToolApprovalChange> changes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: context.radii.blockAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            for (final change in changes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        change.label,
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: change.before,
                              style: TextStyle(color: colors.inactive),
                            ),
                            TextSpan(
                              text: ' → ',
                              style: TextStyle(color: colors.faint),
                            ),
                            TextSpan(
                              text: change.after,
                              style: TextStyle(
                                color: colors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 金额就地微调面板：自带简洁加减数字键盘，免弹系统软键盘。
Future<int?> _showAmountEditSheet(
  BuildContext context, {
  required int initialCents,
  required int kind,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AmountEditSheet(initialCents: initialCents, kind: kind),
  );
}

class _AmountEditSheet extends StatefulWidget {
  const _AmountEditSheet({required this.initialCents, required this.kind});

  final int initialCents;
  final int kind;

  @override
  State<_AmountEditSheet> createState() => _AmountEditSheetState();
}

class _AmountEditSheetState extends State<_AmountEditSheet> {
  late String _expr = _initialText(widget.initialCents);
  bool _fresh = true;

  static String _initialText(int cents) {
    if (cents <= 0) return '';
    if (cents % 100 == 0) return '${cents ~/ 100}';
    if (cents % 10 == 0) return (cents / 100).toStringAsFixed(1);
    return (cents / 100).toStringAsFixed(2);
  }

  double get _value => AmountExpression.evaluate(_expr);
  int get _cents => (_value * 100).round();
  bool get _valid => _cents > 0 && _cents <= 100000000;

  String _currentSegment() {
    var idx = -1;
    for (var i = _expr.length - 1; i >= 0; i--) {
      if (_expr[i] == '+' || _expr[i] == '-') {
        idx = i;
        break;
      }
    }
    return _expr.substring(idx + 1);
  }

  void _onKey(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_fresh && key != 'back' && key != '+' && key != '-') {
        _expr = '';
      }
      _fresh = false;
      switch (key) {
        case 'back':
          if (_expr.isNotEmpty) {
            _expr = _expr.substring(0, _expr.length - 1);
          }
        case '+':
        case '-':
          if (_expr.isEmpty) return;
          final last = _expr[_expr.length - 1];
          if (last == '+' || last == '-') {
            _expr = _expr.substring(0, _expr.length - 1) + key;
          } else {
            _expr += key;
          }
        case '.':
          final seg = _currentSegment();
          if (!seg.contains('.')) {
            _expr += _expr.isEmpty ? '0.' : '.';
          }
        default:
          final seg = _currentSegment();
          if (seg.contains('.')) {
            if (seg.split('.').last.length >= 2) return;
          } else if (seg.replaceAll('-', '').length >= 8) {
            return;
          }
          _expr += key;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = widget.kind == 1 ? colors.income : colors.expense;
    final hasOp = AmountExpression.hasOperator(_expr);
    final display = _expr.isEmpty
        ? '0.00'
        : (hasOp ? _value.toStringAsFixed(2) : AmountExpression.format(_expr));

    return Material(
      color: colors.surface,
      shape: context.radii.sheetTopShape,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                child: Row(
                  children: [
                    Text(
                      '¥',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: colors.muted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasOp)
                            Text(
                              AmountExpression.format(_expr),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.muted,
                              ),
                            ),
                          Text(
                            display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.money(
                              28,
                              color: _expr.isEmpty ? colors.inactive : accent,
                              weight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: _valid
                          ? () => Navigator.pop(context, _cents)
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: context.radii.chipAll,
                        ),
                      ),
                      child: const Text(
                        '确定',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 12),
              _buildKeyRow(colors, accent, const ['7', '8', '9', 'back']),
              const SizedBox(height: 6),
              _buildKeyRow(colors, accent, const ['4', '5', '6', '-']),
              const SizedBox(height: 6),
              _buildKeyRow(colors, accent, const ['1', '2', '3', '+']),
              const SizedBox(height: 6),
              _buildKeyRow(colors, accent, const ['C', '0', '.']),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyRow(AppColors colors, Color accent, List<String> keys) {
    return Row(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            flex: keys.length == 3 && keys[i] == '0' ? 2 : 1,
            child: SizedBox(
              height: 46,
              child: Material(
                color: colors.fill,
                borderRadius: context.radii.blockAll,
                child: InkWell(
                  key: ValueKey('amount-key-${keys[i]}'),
                  borderRadius: context.radii.blockAll,
                  onTap: () {
                    if (keys[i] == 'C') {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _expr = '';
                        _fresh = false;
                      });
                    } else {
                      _onKey(keys[i]);
                    }
                  },
                  child: Center(
                    child: keys[i] == 'back'
                        ? Icon(FLucideIcons.delete, size: 20, color: colors.ink)
                        : Text(
                            keys[i] == '-' ? '−' : keys[i],
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: (keys[i] == '+' || keys[i] == '-')
                                  ? accent
                                  : (keys[i] == 'C'
                                        ? colors.muted
                                        : colors.ink),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 收支类型 + 分类网格选择浮层。
Future<CategoryEntry?> _showCategoryEditSheet(
  BuildContext context, {
  required List<CategoryEntry> categories,
  required int initialKind,
  required String initialCategoryId,
}) {
  return showModalBottomSheet<CategoryEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoryEditSheet(
      categories: categories,
      initialKind: initialKind,
      initialCategoryId: initialCategoryId,
    ),
  );
}

class _CategoryEditSheet extends StatefulWidget {
  const _CategoryEditSheet({
    required this.categories,
    required this.initialKind,
    required this.initialCategoryId,
  });

  final List<CategoryEntry> categories;
  final int initialKind;
  final String initialCategoryId;

  @override
  State<_CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends State<_CategoryEditSheet> {
  late int _kind = widget.initialKind;
  late String? _selectedId = _resolveInitial(
    widget.initialKind,
    widget.initialCategoryId,
  );

  String? _resolveInitial(int kind, String preferredId) {
    final matching = _forKind(kind);
    if (matching.any((c) => c.id == preferredId)) return preferredId;
    return matching.isEmpty ? null : matching.first.id;
  }

  List<CategoryEntry> _forKind(int kind) =>
      widget.categories.where((c) => c.kind == kind).toList();

  CategoryEntry? get _selectedEntry {
    final id = _selectedId;
    if (id == null) return null;
    for (final c in widget.categories) {
      if (c.id == id && c.kind == _kind) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = _kind == 1 ? colors.income : colors.expense;
    final accentSoft = _kind == 1 ? colors.incomeSoft : colors.expenseSoft;
    final list = _forKind(_kind);
    final hasExpense = _forKind(0).isNotEmpty;
    final hasIncome = _forKind(1).isNotEmpty;

    return Material(
      color: colors.surface,
      shape: context.radii.sheetTopShape,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('取消', style: TextStyle(color: colors.muted)),
                  ),
                  const Spacer(),
                  if (hasExpense && hasIncome)
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 0, label: Text('支出')),
                        ButtonSegment(value: 1, label: Text('收入')),
                      ],
                      selected: {_kind},
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onSelectionChanged: (next) {
                        final target = next.first;
                        setState(() {
                          _kind = target;
                          _selectedId = _resolveInitial(target, '');
                        });
                      },
                    )
                  else
                    Text(
                      '选择分类',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _selectedEntry == null
                        ? null
                        : () => Navigator.pop(context, _selectedEntry),
                    child: Text(
                      '确定',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _selectedEntry == null
                            ? colors.inactive
                            : colors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.48,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                child: CategoryPicker(
                  categories: list,
                  selectedIds: {?_selectedId},
                  accent: accent,
                  accentSoft: accentSoft,
                  idleBackground: colors.fill,
                  layout: CategoryPickerLayout.grid,
                  onSelected: (id) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedId = id);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 备注微调底部输入栏。
Future<String?> _showNoteEditSheet(
  BuildContext context, {
  required String initial,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final colors = sheetContext.colors;
      final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Material(
          color: colors.surface,
          shape: sheetContext.radii.sheetTopShape,
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text(
                          '取消',
                          style: TextStyle(color: colors.muted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '编辑备注',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(sheetContext, controller.text.trim()),
                        child: Text(
                          '确定',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 200,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (value) =>
                        Navigator.pop(sheetContext, value.trim()),
                    decoration: InputDecoration(
                      hintText: '填写备注（可留空）',
                      filled: true,
                      fillColor: colors.fill,
                      counterText: '',
                      suffixIcon: IconButton(
                        icon: Icon(
                          FLucideIcons.x,
                          size: 16,
                          color: colors.muted,
                        ),
                        onPressed: controller.clear,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: sheetContext.radii.blockAll,
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  controller.dispose();
  return result;
}

/// 今年省略年份，和账本里的月日写法一致。
String _billDate(DateTime date) {
  final day = formatDay(date);
  if (date.year == DateTime.now().year) return day;
  return '${date.year} 年 $day';
}
