import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/theme/app_theme.dart';

/// ── 页头设计令牌（唯一真相源）──────────────────────────────
///
/// 全应用**所有**页头都由本文件渲染，一级 Tab 页与二级页共用同一套几何。
///
/// 视觉语言是「大标题 + 滚动折叠」：静止时标题以 28px 大字左对齐、上方留出
/// 完整的操作行，页面像有个封面；内容一滚，标题平滑缩到 20px 收进 56 高的
/// 紧凑条，同时浮现一道发丝线把页头与内容分层。滚回顶部再原样展开。
///
/// 三条硬性一致规则（由 test/app_page_header_test.dart 锁死）：
/// 1. **所有页面展开高度相同** = [kAppHeaderExpandedHeight]，
///    没有 actions / 没有返回箭头的页面就留空，不缩高度 —— 否则切 Tab 时
///    内容起始线会上下跳。
/// 2. **所有页面大标题左缘相同** = [kAppHeaderGutter]。返回箭头独占标题
///    上方一行，不再横向挤压标题（旧版被挤到 56，与一级页的 20 对不齐）。
/// 3. **操作行位置完全不随折叠变化**：返回箭头与 actions 恒定居中在顶部
///    56 区内（中心线 28）。只有标题在动，图标不跟着漂。

/// 折叠态页头高度（不含状态栏）。也是 [content] 模式（搜索框）的固定高度。
const double kAppHeaderHeight = 56;

/// 展开态（大标题）页头高度。
///
/// 112 = 操作行 56 + 大标题行 56。两段都取 56 而非压缩：
/// 操作行与折叠态同高，图标位置才能在折叠过程中保持绝对静止。
const double kAppHeaderExpandedHeight = 112;

/// 折叠所需的滚动距离 —— 等于页头要收缩的高度。
///
/// 二者相等意味着「页头收缩量」= 「内容上移量」，标题看起来是被内容顶着走，
/// 而不是自己突然抽一下。
const double _kCollapseDistance = kAppHeaderExpandedHeight - kAppHeaderHeight;

/// 页面左右安全留白基线。标题左缘、返回图标光学左缘、右侧图标光学右缘
/// 全部落在这条线上，与页面内容卡片的边距同源。
const double kAppHeaderGutter = 20;

/// 页头图标的点击热区（正方形）。40 是移动端舒适下限，
/// 比 Material 默认 48 更紧凑，不会把 56 高的操作行顶满。
const double kAppHeaderActionSize = 40;

/// 页头图标视觉尺寸。
const double kAppHeaderIconSize = 22;

/// 图标在热区内的内缩：热区居中放图标后，图标边缘到热区边缘的距离。
/// 用它把「热区边距」换算成「图标光学边距」，让图标和文字对齐同一条线。
const double _iconInset = (kAppHeaderActionSize - kAppHeaderIconSize) / 2;

/// 图标热区应有的外边距 —— 使图标光学边缘正好落在 [kAppHeaderGutter] 上。
const double _actionEdgeInset = kAppHeaderGutter - _iconInset;

/// 折叠态标题字号（与旧版一致，紧凑条观感不变）。
const double _kTitleSizeCollapsed = 20;

/// 展开态标题字号。
///
/// 28 而非更大：中文字面本就比拉丁字母饱满，28 已有足够的大标题气势，
/// 再大在 6 英寸屏上会显笨重，也容易和正文一级标题打架。
const double _kTitleSizeExpanded = 28;

/// 标题行高倍数。固定它，避免不同字体度量导致基线上下浮动。
const double _kTitleHeight = 1.2;

/// 折叠态标题顶边 —— 使其在 56 条内垂直居中。
const double _kTitleTopCollapsed =
    (kAppHeaderHeight - _kTitleSizeCollapsed * _kTitleHeight) / 2;

/// 展开态标题顶边 —— 紧贴操作行下方。
///
/// 剩余空间 112 - 56 - 33.6 ≈ 22 全部留给标题下方：下留白大于上留白，
/// 标题才有「呼吸区」，等分会显得字被夹住。
const double _kTitleTopExpanded = kAppHeaderHeight;

/// 折叠态标题左缘：有返回箭头时让位到箭头右侧。
const double _kTitleLeftCollapsedWithBack = 56;

/// 页头标题统一样式（折叠态基准）。
///
/// - w700：比 w800 更透气，大字重在中文黑体上容易糊成一坨
/// - letterSpacing -0.2：中文标题收紧一点更精致（现代 App 的通用手法）
const kAppHeaderTitleStyle = TextStyle(
  fontSize: _kTitleSizeCollapsed,
  fontWeight: FontWeight.w700,
  height: _kTitleHeight,
  letterSpacing: -0.2,
  color: AppColors.ink,
);

/// 页头副标题（可选，如「共 12 笔」）。仅展开态显示。
const _kAppHeaderSubtitleStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  height: 1.25,
  letterSpacing: -0.1,
  color: AppColors.inactive,
);

/// 折叠后页头底部的分隔线。
///
/// 用 [AppColors.lineSoft] 而非 [AppColors.line]：贴边长直线上深一档的灰
/// 会压出明显硬边，显脏。厚度 0.6 存在感刚够分层，不至于变成装饰线。
const _kDividerThickness = 0.6;

/// 页头右侧图标按钮：统一热区、统一图标尺寸、统一水波纹。
///
/// 业务页放 actions 时一律用它，别自己写 [IconButton]——
/// 默认 IconButton 的 48 热区 + 内建 padding 会把图标推离右边线。
///
/// **[onTap] 为 null 就是彻底不可点**，视觉也一起置灰，没有例外。
/// 这里曾有个 `enabled` 参数用来单独控制置灰，给「点击由外层接管」的场景
/// （拿本组件当 popover 锚点）用。但 forui 的 `FPopoverMenu` 并不接管点击，
/// 于是 `onTap: null` + `enabled: true` 造出了一颗看起来能点、实际是死键的
/// 按钮，且因为视觉正常，没人发现。锚点场景请直接把
/// `controller.toggle` 传进 [onTap]。
class AppHeaderAction extends StatelessWidget {
  const AppHeaderAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;

  /// null 时不响应点击，图标同时置灰。
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    final button = InkResponse(
      onTap: onTap,
      radius: kAppHeaderActionSize / 2,
      containedInkWell: true,
      customBorder: const CircleBorder(),
      child: SizedBox.square(
        dimension: kAppHeaderActionSize,
        child: Center(
          child: Icon(
            icon,
            size: kAppHeaderIconSize,
            color: active ? AppColors.ink : AppColors.inactive,
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 页头返回按钮。图标光学左缘落在 [kAppHeaderGutter] 上。
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return AppHeaderAction(
      icon: FLucideIcons.chevronLeft,
      tooltip: '返回',
      onTap: () => Navigator.of(context).maybePop(),
    );
  }
}

/// 页头内容 —— 一级页与二级页共用的唯一布局实现。
///
/// [t] 是折叠进度（0 = 完全展开的大标题，1 = 完全折叠的紧凑条）。
/// 所有随滚动变化的量都由它线性插值，过渡连续无跳变。
///
/// 布局是「一层钉死的操作行 + 一个会移动缩放的标题」：
/// 只有标题随 t 动（字号 28↔20、顶边 56↔16、左缘 20↔56），
/// 操作行始终居中在顶部 56 区内，绝不漂移。
class _HeaderContent extends StatelessWidget {
  const _HeaderContent({
    required this.t,
    this.title,
    this.subtitle,
    this.content,
    this.actions,
    this.showBack = false,
  });

  final double t;
  final String? title;
  final String? subtitle;
  final Widget? content;
  final List<Widget>? actions;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final actionList = actions ?? const <Widget>[];

    // content（如搜索输入框）不参与大标题缩放：输入框放大会变形。
    // 直接按折叠态几何渲染成单行。
    if (content != null) {
      return SizedBox(
        height: kAppHeaderHeight,
        child: Row(
          children: [
            const SizedBox(width: kAppHeaderGutter),
            Expanded(child: content!),
            if (actionList.isEmpty)
              const SizedBox(width: kAppHeaderGutter)
            else
              Padding(
                padding: const EdgeInsets.only(
                  left: 4,
                  right: _actionEdgeInset,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actionList,
                ),
              ),
          ],
        ),
      );
    }

    // 标题右侧要给 actions 留出空间，否则折叠后长标题会压到图标上。
    // AppHeaderAction 宽度恒为 kAppHeaderActionSize，可精确算出。
    final actionsWidth = actionList.isEmpty
        ? 0.0
        : kAppHeaderActionSize * actionList.length;
    final titleRight = kAppHeaderGutter + actionsWidth;

    return Stack(
      children: [
        // ── 操作行：钉在顶部 56 区，位置不随 t 变化 ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: kAppHeaderHeight,
          child: Row(
            children: [
              if (showBack)
                const Padding(
                  padding: EdgeInsets.only(left: _actionEdgeInset),
                  child: _BackButton(),
                ),
              const Spacer(),
              if (actionList.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: _actionEdgeInset),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actionList,
                  ),
                ),
            ],
          ),
        ),
        // ── 标题：唯一随 t 移动缩放的元素 ──
        Positioned(
          top: _lerp(_kTitleTopExpanded, _kTitleTopCollapsed),
          left: _lerp(
            kAppHeaderGutter,
            showBack ? _kTitleLeftCollapsedWithBack : kAppHeaderGutter,
          ),
          right: titleRight,
          child: _TitleBlock(
            title: title!,
            subtitle: subtitle,
            fontSize: _lerp(_kTitleSizeExpanded, _kTitleSizeCollapsed),
            // 字号越大字距越要收紧，否则大字显松散。
            letterSpacing: _lerp(-0.6, -0.2),
            subtitleOpacity: 1 - t,
          ),
        ),
      ],
    );
  }

  double _lerp(double expanded, double collapsed) =>
      expanded + (collapsed - expanded) * t;
}

/// 标题（可带副标题）。单行省略。
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.title,
    required this.subtitle,
    required this.fontSize,
    required this.letterSpacing,
    required this.subtitleOpacity,
  });

  final String title;
  final String? subtitle;
  final double fontSize;
  final double letterSpacing;
  final double subtitleOpacity;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: kAppHeaderTitleStyle.copyWith(
        fontSize: fontSize,
        letterSpacing: letterSpacing,
      ),
    );
    if (subtitle == null) return titleText;
    // 副标题只在展开态出现：折叠条里塞两行字会拥挤。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleText,
        if (subtitleOpacity > 0)
          Opacity(
            opacity: subtitleOpacity,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _kAppHeaderSubtitleStyle,
              ),
            ),
          ),
      ],
    );
  }
}

/// 折叠动画外壳：监听内容滚动驱动折叠进度，并在折叠后淡入分隔线。
///
/// 为什么用 [NotificationListener] 而不是要求业务页传 ScrollController：
/// 各页滚动体形态不同（ListView / CustomScrollView / 嵌套滚动），
/// 通知冒泡是唯一不改各页结构就能拿到滚动量的方式。因此页头必须把滚动内容
/// 作为 child 包进来，而不是与之在 Column 里并列。
class _CollapsibleHeader extends StatefulWidget {
  const _CollapsibleHeader({
    required this.builder,
    required this.collapsible,
    required this.child,
    this.background = AppColors.canvas,
  });

  /// 按折叠进度 t 构建页头内容。
  final Widget Function(double t) builder;

  /// false 时恒为折叠态（[content] 搜索框模式）。
  final bool collapsible;

  /// 页头条底色。透明时页面自身的背景（如记账页的图片背板）会透上来。
  final Color background;

  /// 页头下方的滚动内容。
  final Widget child;

  @override
  State<_CollapsibleHeader> createState() => _CollapsibleHeaderState();
}

class _CollapsibleHeaderState extends State<_CollapsibleHeader> {
  double _t = 0;

  bool _onScroll(ScrollNotification n) {
    // 只认页面主轴的垂直滚动：横向分类网格、图表手势不该影响页头；
    // depth > 0 是嵌套子滚动体（如横向 chip 条），同样忽略。
    if (n.metrics.axis != Axis.vertical || n.depth > 0) return false;
    final next = (n.metrics.pixels / _kCollapseDistance).clamp(0.0, 1.0);
    // 1px 级的抖动不必重建。
    if ((next - _t).abs() < 0.002) return false;
    setState(() => _t = next);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.collapsible ? _t : 1.0;

    final height = kAppHeaderExpandedHeight - _kCollapseDistance * t;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Column(
        children: [
          // 高度直接跟 t 走、不加隐式动画：标题位移与手指滚动 1:1 绑定。
          // 加隐式动画会滞后一拍，手感发飘。
          SizedBox(
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.background,
                border: Border(
                  bottom: BorderSide(
                    // 分隔线随折叠淡入：静止时页头与内容同色无缝，
                    // 一滚才分层 —— iOS / Notion 的通用手法。
                    color: AppColors.lineSoft.withValues(alpha: t),
                    width: _kDividerThickness,
                  ),
                ),
              ),
              // 折叠过程中标题会短暂超出高度，必须裁掉。
              child: ClipRect(child: widget.builder(t)),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

/// 应用统一页头（一级 Tab 页用）。
///
/// 静止时是 [kAppHeaderExpandedHeight] 高的大标题封面，内容滚动时平滑折叠成
/// [kAppHeaderHeight] 紧凑条并浮现分隔线。
///
/// 滚动内容必须作为 [body] 传进来（而不是在 Column 里与页头并列），
/// 页头才能收到滚动通知。
/// [content] 非空时替换标题区域（如记账页的搜索框），此时不折叠。
///
/// 用法：`AppPageHeader(title: '设置', body: ListView(...))`
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.body,
    this.title,
    this.subtitle,
    this.content,
    this.actions,
  }) : assert(title != null || content != null, 'title 与 content 至少提供一个');

  final String? title;

  /// 标题下方的小灰字，可选。仅展开态显示。
  final String? subtitle;

  /// 非空时替换标题区域。此时页头固定为折叠高度（输入框不该被缩放）。
  final Widget? content;

  final List<Widget>? actions;

  /// 页头下方的滚动内容。
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return _CollapsibleHeader(
      collapsible: content == null,
      builder: (t) => _HeaderContent(
        t: t,
        title: title,
        subtitle: subtitle,
        content: content,
        actions: actions,
      ),
      child: body,
    );
  }
}

/// 应用统一页头（二级页面用）。
///
/// 与一级页 [AppPageHeader] 共用 [_HeaderContent] 与折叠逻辑，观感完全一致：
/// 展开时返回箭头独占顶部一行、大标题在其下方；折叠后标题收进箭头那一行。
///
/// 因为返回箭头不再挤压标题，**展开态大标题左缘与一级页同为**
/// [kAppHeaderGutter]，从列表页进二级页时标题不会横向跳动。
///
/// 刻意**不复用** Material [AppBar]：AppBar 按 leadingWidth + titleSpacing
/// 推挤标题，实测导致「有返回 64 / 无返回 16」两种左缘，与一级页三方不一致；
/// 且它无法表达大标题折叠。也因此本组件**不是** PreferredSizeWidget，
/// 不能塞进 `Scaffold.appBar`，要当 body 用。
///
/// 用法：`Scaffold(body: AppTopBar(title: '记一笔', body: ListView(...)))`
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions,
    this.backgroundColor = AppColors.canvas,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  /// 整页底色。传 [Colors.transparent] 可让页面在本组件之下自绘背景
  /// （记账页把账单图片铺在这一层）。
  final Color backgroundColor;

  /// 页头下方的滚动内容。
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      child: SafeArea(
        bottom: false,
        child: _CollapsibleHeader(
          collapsible: true,
          background: backgroundColor,
          builder: (t) => _HeaderContent(
            t: t,
            title: title,
            subtitle: subtitle,
            actions: actions,
            showBack: Navigator.of(context).canPop(),
          ),
          child: body,
        ),
      ),
    );
  }
}
