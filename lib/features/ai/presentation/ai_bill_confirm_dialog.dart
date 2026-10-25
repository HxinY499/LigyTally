import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../application/ai_approval.dart';

/// 记账 / 改账的确认框。
///
/// 共用的 [showAppConfirmDialog] 只放得下一句居中粗体，适合「删不删」。
/// 这里改成一张账单卡：金额是要核对的数，分类和日期退到下一行。
Future<bool> showAiBillConfirmDialog(
  BuildContext context,
  ToolApprovalRequest request,
) {
  return showAppConfirmDialog(
    context,
    message: request.message,
    confirmLabel: request.confirmLabel,
    accent: context.colors.primary,
    content: _BillCard(request: request),
  );
}

class _BillCard extends StatelessWidget {
  const _BillCard({required this.request});

  final ToolApprovalRequest request;

  @override
  Widget build(BuildContext context) {
    final bill = request.bill!;
    final colors = context.colors;
    final tone = bill.kind == 1 ? colors.income : colors.expense;
    final meta = [
      _billDate(bill.accountingDate),
      bill.categoryName,
      if (bill.note.trim().isNotEmpty) bill.note.trim(),
    ].join(' · ');

    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            request.title ?? '记一笔',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            formatMoney(bill.amountCents),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: tone,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            bill.kind == 1 ? '收入' : '支出',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tone,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            meta,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, height: 1.4, color: colors.muted),
          ),
          if (request.changes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ChangeList(changes: request.changes),
          ],
          if (request.footnote != null && request.footnote!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              request.footnote!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: colors.inactive,
              ),
            ),
          ],
        ],
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

/// 今年省略年份，和账本里的月日写法一致。
String _billDate(DateTime date) {
  final day = formatDay(date);
  if (date.year == DateTime.now().year) return day;
  return '${date.year} 年 $day';
}
