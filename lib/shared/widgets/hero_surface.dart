import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/hero_skin.dart';

/// Hero 卡的卡面外壳：卡面 + 高光 + 内边距。
///
/// Hero 卡是同一个视觉元素在两屏上的两次出现（明细页月度摘要、统计页概览），
/// 卡面此前在两处各自用 [BoxDecoration] 拼一遍。那种写法在只有「渐变 + 圆角 +
/// 阴影」三件事时还撑得住，但卡面现在是**两层**（底下一条线性渐变、上面一层
/// 径向高光，见 [HeroSkin.sheen]），复制两份就等于以后每次调卡面都要记着
/// 改两处——这正是本组件存在的理由。
///
/// 用户能把卡面换成纯色或描边（见 [HeroCardStyle]），三档的差异全部由
/// [HeroSkin] 吸收：描边档没有高光层，本组件会退化成单层。所以调用点不需要
/// 判断当前是哪一档。
///
/// **卡上的前景色仍要调用点自己从 `context.colors.hero` 取。** 本组件只管
/// 卡面，不代管字色——描边档的卡面是白的，字色跟着一起翻是调用点的责任，
/// 也是 [HeroSkin] 把「卡面 + 前景」成套发放的原因。
class HeroSurface extends StatelessWidget {
  const HeroSurface({
    super.key,
    required this.padding,
    required this.child,
    this.borderRadius,
  });

  /// 卡内边距。两屏的 Hero 卡内容密度不同（统计页概览卡上还压着一行周期
  /// 切换器），所以留给调用点，不在这里钉死。
  final EdgeInsetsGeometry padding;

  /// 卡片圆角。null 表示取 `AppRadius.cardAll`。
  final BorderRadius? borderRadius;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hero = context.colors.hero;
    final radius = borderRadius ?? context.radii.cardAll;
    final sheen = hero.sheen(radius);
    final content = Padding(padding: padding, child: child);
    return Container(
      // 卡片恒占满可用宽度。不给的话 Column 会缩到最宽那行文字的宽度，
      // 卡片宽度就随金额位数变化了。
      width: double.infinity,
      decoration: hero.decoration(radius),
      child: sheen == null
          ? content
          : DecoratedBox(decoration: sheen, child: content),
    );
  }
}
