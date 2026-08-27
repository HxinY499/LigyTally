import 'package:flutter/material.dart';

import 'category_icon_view.dart';

/// 分类图标的底座：淡色圆片 + 语义色图标。
///
/// ## 为什么要收口
///
/// 这个「圆底 + 图标」的组合原本在五处各写了一遍，且五处都不一样：
/// 明细页账单行 40 圆、日历页当天账单 34 圆、分类明细弹层 36 圆、
/// 统计页分类环比 34 **圆角方**、而记账页的分类选择器干脆**没有底座**
/// （一片同色的灰图标）。
///
/// 于是同一个分类在同一个 App 里有三种长相：粉底红图标、灰底方角图标、
/// 无底灰图标。这不是「几处像素差」，是图标语言分了叉——而分类图标恰好是
/// 全应用出现频率最高的视觉元素。
///
/// ## 尺寸只有两档
///
/// 见 [large] 与 [small]。差别是「这一屏的主内容」还是「次级列表 / 浮层」，
/// 不是「这个页面碰巧有多少空间」。需要第三档时先确认它表达的是第三种层级，
/// 否则又会滑回五种尺寸。
///
/// ## 图标色与底座色由调用点给
///
/// 因为语义在调用点：账单行按收支给 `expense`/`expenseSoft`，记账页选择器按
/// 当前收支侧给，统计页分类环比只能从图表调色板现算（那套色没有对应的
/// `*Soft` 令牌）。本组件只负责「怎么画」，不猜「该是什么颜色」。
class CategoryIconBadge extends StatelessWidget {
  const CategoryIconBadge({
    super.key,
    required this.iconKey,
    required this.color,
    required this.background,
    this.diameter = small,
    this.side = BorderSide.none,
    this.selected = false,
  });

  /// 一屏主内容里的底座：明细页账单行、记账页分类网格。
  static const large = 40.0;

  /// 次级列表与浮层里的底座：日历页当天账单、分类明细弹层、统计页分类环比。
  static const small = 34.0;

  /// 字形边长占底座直径的比例。
  ///
  /// 内置图标是线性字形、四周自带留白，所以不能铺满底座。这个比例是从原来
  /// 「34 圆底里画 18 字形」那一处反推出来的——那是全应用出现最多的一档，
  /// 拿它当基准，其余档位按同一比例缩放后观感才一致。
  static const _glyphRatio = 18 / 34;

  final String iconKey;

  /// 图标（字形）颜色。自定义图片不染色，见 [CategoryIconView.color]。
  final Color color;

  /// 底座颜色。
  final Color background;

  final double diameter;

  /// 底座描边。选中态需要比「淡底 + 彩色图标」更明确的信号时用。
  final BorderSide side;

  /// 传给 [CategoryIconView]：自定义图片的选中态靠描边表达。
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: background,
        shape: CircleBorder(side: side),
      ),
      child: CategoryIconView(
        iconKey: iconKey,
        color: color,
        size: diameter * _glyphRatio,
        // 自定义图片要铺满底座、由底座来定型，否则会成为「大圆底中央一颗
        // 小圆点」，见 CategoryIconView 的 imageSize 文档。
        imageSize: diameter,
        selected: selected,
      ),
    );
  }
}
