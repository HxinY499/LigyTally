import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/preferences/money_grouped.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/ledger_date.dart';

/// 明细页顶部大卡：本月支出（Hero 大数字）+ 本月收入 + 净收支。
///
/// 视觉参照现代记账App：暖黄渐变、大圆角，本月支出用超大黑体数字撑起
/// 视觉重心；底部两组「本月收入 / 净收支」用小字与主数字拉开层级——
/// 之前所有金额字号相近，才显得「一堆数字堆在一起」。
class SummaryBand extends ConsumerWidget {
  const SummaryBand({super.key, required this.summary, this.compact = false});

  final LedgerSummary summary;
  final bool compact;

  static const _warmA = Color(0xFFFFF3D2);
  static const _warmB = Color(0xFFF8D98A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = ref.watch(moneyGroupedProvider);
    if (compact) return _CompactBand(summary: summary, grouped: grouped);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_warmA, _warmB],
        ),
        borderRadius: BorderRadius.circular(22),
        // 用暖色阴影而不是中性灰：灰色压在暖黄渐变下会发浊，
        // 阴影里掺入卡片自身色相才干净。与统计页 Hero 卡同一套思路。
        boxShadow: AppShadows.heroWarm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '本月支出',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink.withValues(alpha: 0.65),
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(元)',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.ink.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _rawMoney(summary.expenseCents, grouped: grouped),
              maxLines: 1,
              style: const TextStyle(
                fontSize: 40,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _MiniStat(
                  label: '本月收入',
                  value: _rawMoney(summary.incomeCents, grouped: grouped),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: '净收支',
                  value: _rawMoney(
                    summary.netCents,
                    grouped: grouped,
                    signed: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 摘要卡内的裸金额：不带 `¥` 前缀，让大数字更干净；
/// 卡片外的普通场景仍走 `formatMoney`。
String _rawMoney(int cents, {required bool grouped, bool signed = false}) {
  final sign = cents < 0 ? '-' : (signed && cents > 0 ? '+' : '');
  final absolute = cents.abs();
  final yuan = absolute ~/ 100;
  final fraction = absolute % 100;
  final yuanText = grouped ? _groupInt(yuan) : yuan.toString();
  return '$sign$yuanText.${fraction.toString().padLeft(2, '0')}';
}

String _groupInt(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  final length = raw.length;
  for (var i = 0; i < length; i++) {
    if (i > 0 && (length - i) % 3 == 0) buffer.write(',');
    buffer.write(raw[i]);
  }
  return buffer.toString();
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
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.ink.withValues(alpha: 0.6),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '(元)',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.ink.withValues(alpha: 0.42),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// 统计页专用的紧凑版：三等分小卡（保留原黑底样式，不影响统计页视觉）。
class _CompactBand extends StatelessWidget {
  const _CompactBand({required this.summary, required this.grouped});

  final LedgerSummary summary;
  final bool grouped;

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
            value: formatMoney(summary.expenseCents, grouped: grouped),
            color: const Color(0xFFFFA897),
          ),
          const _BandDivider(),
          _CompactValue(
            label: '收入',
            value: formatMoney(summary.incomeCents, grouped: grouped),
            color: const Color(0xFF81C784),
          ),
          const _BandDivider(),
          _CompactValue(
            label: '净收支',
            value: formatMoney(
              summary.netCents,
              signed: true,
              grouped: grouped,
            ),
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
