import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

/// 金额变化时逐帧插值，而不是从旧值瞬间跳到新值。
///
/// 只插值**数值**，不碰渲染：[builder] 每帧拿到一个中间分值，怎么格式化、
/// 用什么字号字色全由调用点决定。所以同一个组件既能包普通 [Text]，
/// 也能包 Hero 卡上那种「符号 + ¥ + 数字」的富文本。
///
/// ## 首次出现不动
///
/// `tween` 的 `begin` 与 `end` 都传当前值，于是首帧 begin == end，直接落到
/// 终点。这是刻意的：数字从 0 滚上来虽然显眼，但它推迟了「这个月花了多少」
/// 这条信息的到达时间，而那是用户打开这一屏的唯一目的。滚动的价值在于表达
/// **变化**（换了月份、换了周期），不在于入场表演。
///
/// ## 什么情况下不要用它
///
/// **数字右侧有跟着它排版的兄弟节点时不要用。** 位数在滚动途中会跨越千位、
/// 万位，[Text] 的宽度随之变化，右边的东西会跟着来回滑。
///
/// 数字独占一行、或者被 [Expanded] 之类固定了外框的场合才安全。
///
/// ## 目前只有明细页的 Hero 卡在用
///
/// 统计页概览卡整张都没接，理由是它的主数字紧挨着一枚环比徽章
/// （`Flexible` + `SizedBox(8)` + 徽章），一滚那枚徽章会在半秒内左右横移，
/// 比数字瞬变难看得多。
///
/// 而那张卡的三个次级数字各被 [Expanded] 框住，单独接是安全的——但**没有单独
/// 接**：一张卡里主数字瞬变、次级数字却在滚，会让人觉得主数字「没跟上」。
/// 滚动这件事在一张卡的范围内要么全接要么全不接。
class AnimatedCents extends StatelessWidget {
  const AnimatedCents({super.key, required this.cents, required this.builder});

  final int cents;

  /// 每帧的渲染。[value] 是当前的中间分值。
  final Widget Function(BuildContext context, int value) builder;

  /// 滚动时长。
  ///
  /// 520ms 与统计页图表的数值变化同一档（`StatsTokens.durChart`）：同一次
  /// 换月里 Hero 卡的数字和下面的折线是一起变的，两者时长不一致会显得
  /// 图表「慢半拍」。
  static const duration = Duration(milliseconds: 520);

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final resolved = motion(duration);
    // 动效关闭档直接给终值：套一个零时长的 TweenAnimationBuilder 也能到终点，
    // 但白建一个 AnimationController。
    if (resolved == Duration.zero) return builder(context, cents);
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: cents, end: cents),
      duration: resolved,
      curve: motion.curve(Curves.easeOutCubic),
      builder: (context, value, _) => builder(context, value),
    );
  }
}
