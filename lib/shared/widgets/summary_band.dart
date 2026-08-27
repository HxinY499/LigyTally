import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/database/app_database.dart';
import '../../core/appearance/appearance.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hero_skin.dart';
import '../../core/utils/ledger_date.dart';
import 'animated_money.dart';
import 'hero_surface.dart';

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
    // 卡面（渐变 / 纯色 / 描边三档 + 高光层 + 阴影）全部由 HeroSurface 负责，
    // 统计页概览卡用的是同一个组件。
    return HeroSurface(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: _bandBody(hero, grouped),
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
          child: _HeroMoney(
            cents: summary.expenseCents,
            grouped: grouped,
            size: AppText.moneyXl,
            weight: FontWeight.w800,
            hero: hero,
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
                cents: summary.incomeCents,
                grouped: grouped,
              ),
            ),
            Expanded(
              child: _MiniStat(
                hero: hero,
                label: '净收支',
                cents: summary.netCents,
                grouped: grouped,
                signed: true,
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

/// 摘要卡内的金额：`-` `¥` `1,234.56` 三段，中间那段字号小一档。
///
/// ## 为什么货币符号要单独一段
///
/// 这张卡上原本是「标签后面跟一个 `(元)`，数字本身不带符号」。那样做的代价是
/// 单位跑到了离数字最远的地方（标签行的末尾），而括号又把标签切成两截。
///
/// 现在把 `¥` 放回数字前面，但**字号压到 0.55 倍、颜色降到 [HeroSkin.foregroundSoft]**：
/// 单位回到它该在的位置，同时不和数字抢视觉重量——一屏里最该被读到的是
/// 「2428」这四位数，不是那个所有金额都一样的货币符号。
///
/// 符号（`-` / `+`）留在货币符号**之前**且用大号字：`¥-1,234` 是错的，
/// 负号修饰的是整个金额，不是货币单位。
///
/// 数字那一段交给 [AnimatedMoneyText] 逐位翻到新值。这也是这里从
/// [Text.rich] 换成分段的原因——富文本能自动按基线对齐不同字号，但它没法让
/// 单个字符各自动画。基线对齐改由 [AnimatedMoneyText] 里的 Row 显式处理。
class _HeroMoney extends StatelessWidget {
  const _HeroMoney({
    required this.cents,
    required this.grouped,
    required this.size,
    required this.hero,
    this.weight = FontWeight.w700,
    this.signed = false,
  });

  final int cents;
  final bool grouped;
  final double size;
  final HeroSkin hero;
  final FontWeight weight;

  /// true 时正数也带 `+`（净收支要区分方向）。
  final bool signed;

  /// 货币符号相对主数字的字号比例。
  static const _currencyScale = 0.55;

  /// 货币符号的字号下限。
  ///
  /// 纯按比例缩会让次级数字上的 `¥` 掉到 11px（20 × 0.55），比它旁边的标签
  /// 还小——那时它已经不是「退到后面的单位」，而是一个认不出来的小疙瘩。
  /// 压小货币符号的收益只在大数字上成立，小数字本来就不存在「符号抢戏」。
  static const _currencyMinSize = 13.0;

  double get _currencySize =>
      math.max(size * _currencyScale, math.min(size, _currencyMinSize));

  @override
  Widget build(BuildContext context) {
    final base = AppText.money(
      size,
      color: hero.foreground,
      weight: weight,
      height: 1.1,
    );
    return AnimatedMoneyText(
      segments: [
        // 正负号不逐位翻：它不是一个「位」，翻转反而会让人以为数值在变。
        MoneySegment(_sign, style: base),
        MoneySegment(
          '¥',
          style: AppText.money(
            _currencySize,
            color: hero.foregroundSoft,
            weight: FontWeight.w600,
            height: 1.1,
          ),
        ),
        MoneySegment(_digits, style: base, animate: true),
      ],
    );
  }

  String get _sign => cents < 0 ? '-' : (signed && cents > 0 ? '+' : '');

  String get _digits {
    final absolute = cents.abs();
    final yuan = absolute ~/ 100;
    final fraction = absolute % 100;
    final yuanText = grouped ? _groupInt(yuan) : yuan.toString();
    return '$yuanText.${fraction.toString().padLeft(2, '0')}';
  }
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
    required this.cents,
    required this.grouped,
    this.signed = false,
  });

  final HeroSkin hero;
  final String label;
  final int cents;
  final bool grouped;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: hero.foregroundSoft,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: _HeroMoney(
            cents: cents,
            grouped: grouped,
            size: AppText.moneyMd,
            weight: FontWeight.w800,
            hero: hero,
            signed: signed,
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
