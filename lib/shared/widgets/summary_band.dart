import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/ledger_date.dart';

/// 明细页顶部大卡：本月支出（大字）+ 本月收入+ 本月净收支。
///
/// 参考现代记账 App，采用暖黄色渐变卡片，视觉上比黑色横条更轻。
/// `compact=true` 时用于统计页——尺寸缩小、去掉主副结构，等分三列。
class SummaryBand extends StatelessWidget {
  const SummaryBand({super.key, required this.summary, this.compact = false});

  final LedgerSummary summary;
  final bool compact;

  static const _warmA = Color(0xFFFFF1CC);
  static const _warmB = Color(0xFFFDE1A6);

  @override
  Widget build(BuildContext context) {
    if (compact) return _CompactBand(summary: summary);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_warmA, _warmB],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本月支出(元)',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.ink.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(summary.expenseCents),
              maxLines: 1,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: '本月收入(元)',
                  value: formatMoney(summary.incomeCents),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: '净收支(元)',
                  value: formatMoney(summary.netCents, signed: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.ink.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

/// 统计页专用的紧凑版：三等分小卡，保持原有信息结构。
class _CompactBand extends StatelessWidget {
  const _CompactBand({required this.summary});

  final LedgerSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: AppColors.ink,
      child: Row(
        children: [
          _CompactValue(
            label: '支出',
            value: formatMoney(summary.expenseCents),
            color: const Color(0xFFFFA897),
          ),
          const _BandDivider(),
          _CompactValue(
            label: '收入',
            value: formatMoney(summary.incomeCents),
            color: const Color(0xFF81C784),
          ),
          const _BandDivider(),
          _CompactValue(
            label: '净收支',
            value: formatMoney(summary.netCents, signed: true),
            color: const Color(0xFFF4D07B),
          ),
        ],
      ),
    );
  }
}

class _CompactValue extends StatelessWidget {
  const _CompactValue({
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
