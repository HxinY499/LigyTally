import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/database/app_database.dart';
import '../../core/appearance/appearance.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hero_skin.dart';
import '../../core/utils/ledger_date.dart';

/// 紧凑版摘要条的实底：固定，不随皮肤变。
///
/// 它上面压的是 `Colors.white70` 标签和三个亮色数字，底色一旦跟着
/// `colors.ink` 在深色下翻成近白，就是白字压白底。
const _compactSurface = Color(0xFF17211E);

/// 明细页顶部大卡：当月支出（Hero 大数字）+ 当月收入 + 净收支。
///
/// 视觉参照现代记账App：主题色渐变、大圆角，本月支出用超大白色黑体数字
/// 撑起视觉重心；底部两组「本月收入 / 净收支」用小字与主数字拉开层级——
/// 之前所有金额字号相近，才显得「一堆数字堆在一起」。
///
/// 卡面直接取 [AppColors.hero]，也就是统计页概览卡那套：两屏的 Hero 卡是
/// 同一个视觉元素，共用一份卡面才不会各自漂移。用户能在外观设置里把这套
/// 卡面换成纯色或描边（见 [HeroCardStyle]），所以卡上的字色也必须从
/// [HeroSkin] 里取——描边档的卡面是白的，白字会直接消失。
class SummaryBand extends ConsumerWidget {
  const SummaryBand({
    super.key,
    required this.summary,
    this.month,
    this.compact = false,
    this.onPickMonth,
  });

  final LedgerSummary summary;

  /// 这张卡在统计的月份。为空按当前自然月处理。
  ///
  /// 存在的理由只有一个：明细页可以翻到别的月，标签写死「本月支出」会在
  /// 数字已经换成三月的时候仍然说「本月」。
  final DateTime? month;

  final bool compact;

  /// 非空时卡片右上角出现「年月 ⌄」，点它换月。
  ///
  /// 月份选择器长在这张卡上，而不是页头或卡片下方那条：它换的就是这张卡
  /// 上的三个数，两者分开摆时得先猜「这个月份管的是谁」。
  final VoidCallback? onPickMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final grouped = ref.watch(moneyGroupedProvider);
    if (compact) return _CompactBand(summary: summary, grouped: grouped);
    final hero = colors.hero;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // gradient 与 color 总有一个是 null，同时传给 BoxDecoration 合法。
        gradient: hero.gradient,
        color: hero.color,
        border: hero.border,
        borderRadius: context.radii.cardAll,
        // 彩色档用带主色相的阴影而不是中性灰：灰色压在彩色卡面下会发浊，
        // 阴影里掺入卡片自身色相才干净。描边档反过来用中性阴影，
        // 这一层选择在 [HeroSkin] 里已经做完了。
        boxShadow: hero.shadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: _bandBody(hero, grouped),
      ),
    );
  }

  /// 标签的时间前缀：当前自然月说「本月」，同年的别的月说「3 月」，
  /// 跨年才带上年份——「3 月支出」在翻到去年时会被读成今年三月。
  String get _periodLabel {
    final value = month;
    if (value == null) return '本月';
    final now = DateTime.now();
    if (value.year == now.year) {
      return value.month == now.month ? '本月' : '${value.month} 月';
    }
    return '${value.year} 年 ${value.month} 月';
  }

  Widget _bandBody(HeroSkin hero, bool grouped) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$_periodLabel支出',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: hero.foregroundSoft,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '(元)',
              style: TextStyle(fontSize: 11, color: hero.foregroundFaint),
            ),
            if (onPickMonth != null) ...[
              const Spacer(),
              _MonthChip(
                hero: hero,
                label: formatMonth(month ?? DateTime.now()),
                onTap: onPickMonth!,
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _rawMoney(summary.expenseCents, grouped: grouped),
            maxLines: 1,
            style: TextStyle(
              fontSize: 40,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: hero.foreground,
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
                hero: hero,
                label: '$_periodLabel收入',
                value: _rawMoney(summary.incomeCents, grouped: grouped),
              ),
            ),
            Expanded(
              child: _MiniStat(
                hero: hero,
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
    );
  }
}

/// 卡片右上角的月份入口：`2026 年 8 月 ⌄`。
///
/// 必须自带一层透明 [Material]：水波画在最近的 Material 上、且在其子节点
/// **之下**，而这张卡的卡面是渐变 [Container]，往上找到的最近 Material 是
/// 页面那层，水波会被卡面整块盖住（与明细页日卡踩过的同一个坑）。
///
/// 按下色走 [HeroSkin.highlight] 而不是全局 `pressed`：后者是墨色系，
/// 为白面卡片挑的，压在深彩卡面上几乎看不见。
class _MonthChip extends StatelessWidget {
  const _MonthChip({
    required this.hero,
    required this.label,
    required this.onTap,
  });

  final HeroSkin hero;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: '选择月份',
        child: InkWell(
          onTap: onTap,
          highlightColor: hero.highlight,
          splashColor: hero.splash,
          hoverColor: hero.splash,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: hero.foreground,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  FLucideIcons.chevronDown,
                  size: 15,
                  color: hero.foreground,
                ),
              ],
            ),
          ),
        ),
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
  const _MiniStat({
    required this.hero,
    required this.label,
    required this.value,
  });

  final HeroSkin hero;
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
                color: hero.foregroundSoft,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '(元)',
              style: TextStyle(fontSize: 10, color: hero.foregroundFaint),
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
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: hero.foreground,
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
