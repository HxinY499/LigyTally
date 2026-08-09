import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/ledger_date.dart';

class SummaryBand extends StatelessWidget {
  const SummaryBand({super.key, required this.summary, this.compact = false});

  final LedgerSummary summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: compact ? 14 : 18,
      ),
      color: AppColors.ink,
      child: Row(
        children: [
          _SummaryValue(
            label: '支出',
            value: formatMoney(summary.expenseCents),
            color: const Color(0xFFFFA897),
          ),
          const _BandDivider(),
          _SummaryValue(
            label: '收入',
            value: formatMoney(summary.incomeCents),
            color: const Color(0xFF81C784),
          ),
          const _BandDivider(),
          _SummaryValue(
            label: '净收支',
            value: formatMoney(summary.netCents, signed: true),
            color: const Color(0xFFF4D07B),
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandDivider extends StatelessWidget {
  const _BandDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.white24,
    );
  }
}
