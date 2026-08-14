import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/preferences/money_grouped.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/color_luminance.dart';
import '../../core/utils/ledger_date.dart';

/// 摘要卡上的文字色：固定白色，不随深浅皮肤变。
///
/// 这里刻意不用 `colors.ink`——那是「压在页面底色上的文字色」，浅色皮肤下
/// 是深墨色。而这张卡的卡面是一条压到固定深度的主题色渐变，两套皮肤下
/// 一样深，字色必须跟着卡面而不是跟着页面，否则浅色下就是深墨字压深卡面。
/// 与统计页 `StatsTokens.onHeroPrimary` 同一条规则：**彩色卡上的前景色
/// 属于卡片自己的配色，不进全局色板。**
const _onHero = Colors.white;

/// 卡面上的次级文字（标签）：白色降透明度，而不是给一个灰色——
/// 灰色压在彩色卡面上会发浊。
const _onHeroSoft = Color(0xCCFFFFFF);

/// 最弱一档：金额后面的「(元)」单位。
const _onHeroFaint = Color(0x94FFFFFF);

/// 紧凑版摘要条的实底：同样固定，不随皮肤变。
///
/// 它上面压的是 `Colors.white70` 标签和三个亮色数字，底色一旦跟着
/// `colors.ink` 在深色下翻成近白，就是白字压白底。
const _compactSurface = Color(0xFF17211E);

/// 明细页顶部大卡：本月支出（Hero 大数字）+ 本月收入 + 净收支。
///
/// 视觉参照现代记账App：主题色渐变、大圆角，本月支出用超大白色黑体数字
/// 撑起视觉重心；底部两组「本月收入 / 净收支」用小字与主数字拉开层级——
/// 之前所有金额字号相近，才显得「一堆数字堆在一起」。
class SummaryBand extends ConsumerWidget {
  const SummaryBand({super.key, required this.summary, this.compact = false});

  final LedgerSummary summary;
  final bool compact;

  /// 卡面三个色停的相对亮度。
  ///
  /// 不直接用 `colors.primary` 及其明暗变体：那支色是为「压在页底上的强调色」
  /// 挑的，白字压上去只有 3.2:1。这里把色停钉在固定亮度上，选哪套强调色、
  /// 哪套皮肤，白字的对比度都一样——最浅的 [_faceTop] 卡在 AA(4.5:1) 之上，
  /// 而它正是大数字所在的左上角。
  static const _faceTop = 0.17;
  static const _faceMid = 0.125;
  static const _faceEnd = 0.085;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final grouped = ref.watch(moneyGroupedProvider);
    // 注意这张卡的文字用 [_onHero] 而不是 colors.ink：卡面在深浅两套皮肤下
    // 都是同一深度的主题色渐变，字色必须跟着**卡面**走，跟着页面走会在浅色下
    // 变成深墨字压深卡面。
    if (compact) return _CompactBand(summary: summary, grouped: grouped);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            withRelativeLuminance(colors.primary, _faceTop),
            withRelativeLuminance(colors.primary, _faceMid),
            withRelativeLuminance(colors.primary, _faceEnd),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(22),
        // 用带主色相的阴影而不是中性灰：灰色压在彩色卡面下会发浊，
        // 阴影里掺入卡片自身色相才干净。与统计页 Hero 卡同一套思路。
        boxShadow: colors.shadowHeroPrimary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '本月支出',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _onHeroSoft,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '(元)',
                style: TextStyle(fontSize: 11, color: _onHeroFaint),
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
                color: _onHero,
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
              style: const TextStyle(
                fontSize: 12,
                color: _onHeroSoft,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 3),
            const Text(
              '(元)',
              style: TextStyle(fontSize: 10, color: _onHeroFaint),
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
              color: _onHero,
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
      color: _compactSurface,
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
