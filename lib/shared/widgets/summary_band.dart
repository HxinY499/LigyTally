import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/database/app_database.dart';
import '../../core/preferences/money_grouped.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/ledger_date.dart';

/// 摘要卡上的文字色：固定白色，不随深浅皮肤变。
///
/// 这里刻意不用 `colors.ink`——那是「压在页面底色上的文字色」，浅色皮肤下
/// 是深墨色。而这张卡的卡面是一条主题色渐变，深浅两套皮肤下都足够深，
/// 字色必须跟着卡面而不是跟着页面，否则浅色下就是深墨字压深卡面。
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
///
/// 卡面直接取 [AppColors.heroGradient]，也就是统计页概览卡那条：两屏的
/// Hero 卡是同一个视觉元素，共用一份色停才不会各自漂移。
class SummaryBand extends ConsumerWidget {
  const SummaryBand({
    super.key,
    required this.summary,
    this.compact = false,
    this.onOpenCalendar,
  });

  final LedgerSummary summary;
  final bool compact;

  /// 非空时在卡片右上角显示月历入口。
  ///
  /// 刻意做成一颗独立图标按钮，而不是让整张卡可点：这张卡面积大又待在
  /// 滚动区顶部，整卡可点会在滑列表时被误触，而且卡面上没有任何线索
  /// 能告诉用户「这里能点」。
  final VoidCallback? onOpenCalendar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final grouped = ref.watch(moneyGroupedProvider);
    // 注意这张卡的文字用 [_onHero] 而不是 colors.ink：卡面在深浅两套皮肤下
    // 都是主题色渐变，字色必须跟着**卡面**走，跟着页面走会在浅色下
    // 变成深墨字压深卡面。
    if (compact) return _CompactBand(summary: summary, grouped: grouped);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: colors.heroGradient,
        borderRadius: context.radii.cardAll,
        // 用带主色相的阴影而不是中性灰：灰色压在彩色卡面下会发浊，
        // 阴影里掺入卡片自身色相才干净。与统计页 Hero 卡同一套思路。
        boxShadow: colors.shadowHeroPrimary,
      ),
      child: Stack(
        children: [
          // 月历按钮浮在角上而不是排进标签行：排进去会把 34 的热区撑进
          // 那一行，整张卡跟着变高，主数字的位置也跟着往下挪。
          if (onOpenCalendar != null)
            Positioned(
              top: 8,
              right: 8,
              child: _CalendarButton(onTap: onOpenCalendar!),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: _bandBody(grouped),
          ),
        ],
      ),
    );
  }

  Widget _bandBody(bool grouped) {
    return Column(
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
    );
  }
}

/// 卡片右上角的月历入口。
///
/// 必须自带一层透明 [Material]：水波是画在最近的 Material 上、且在其子节点
/// 之下的，而这张卡的卡面是渐变 [Container]，往上找到的最近 Material 是页面
/// 那层，水波会被卡面整块盖住（与记账页日卡踩过的同一个坑）。
class _CalendarButton extends StatelessWidget {
  const _CalendarButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: '月历',
        child: InkResponse(
          onTap: onTap,
          radius: 17,
          containedInkWell: true,
          customBorder: const CircleBorder(),
          // 水波色写死成半透明白：卡面是主题色渐变，用全局 ripple（墨色系）
          // 压在上面几乎看不见。
          highlightColor: const Color(0x1FFFFFFF),
          splashColor: const Color(0x24FFFFFF),
          child: const SizedBox.square(
            dimension: 34,
            child: Center(
              child: Icon(FLucideIcons.calendarDays, size: 18, color: _onHero),
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
