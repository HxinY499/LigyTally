import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/theme/app_theme.dart';

/// ── 页头设计令牌（唯一真相源）──────────────────────────────
///
/// 全应用**所有**页头都由本文件渲染，一级 Tab 页与二级页共用同一套几何。
///
/// 视觉语言是「大标题 + 滚动折叠 + 吸顶毛玻璃」：静止时标题以 28px 大字左对齐，
/// 页面像有个封面；内容一滚，标题平滑缩到 20px 收进 56 高的紧凑条，同时页头
/// 底色转为半透明并模糊背后穿过的内容，浮现一道发丝线把两层分开。
/// 滚回顶部再原样展开、恢复不透明。
///
/// 实现形态是 [SliverPersistentHeader]（pinned），**不是**并列在 Column 里的
/// 固定条。这是毛玻璃唯一可行的形态：Column 形态下内容永远走不到页头背后，
/// 半透明只能露出同色底、模糊只能模糊纯色，视觉上等于什么都没做。
/// pinned sliver 在 viewport 里是最后绘制（靠前的 sliver 盖在后面之上），
/// 因此 [BackdropFilter] 读得到后续 sliver 已经画好的像素。
/// 代价是**页面内容必须以 sliver 形式交进来**，见 [AppPageHeader.slivers]。
///
/// 三条硬性一致规则（由 test/app_page_header_test.dart 锁死）：
/// 1. **所有页面展开高度相同** = [kAppHeaderExpandedHeight]，
///    没有 actions / 没有返回箭头的页面就留空，不缩高度 —— 否则切 Tab 时
///    内容起始线会上下跳。
/// 2. **所有页面大标题左缘相同** = [kAppHeaderGutter]。返回箭头独占标题
///    上方一行，不再横向挤压标题（旧版被挤到 56，与一级页的 20 对不齐）。
/// 3. **操作行位置完全不随折叠变化**：返回箭头与 actions 恒定居中在顶部
///    56 区内（中心线 28）。只有标题在动，图标不跟着漂。

/// 折叠态页头高度（不含状态栏）。也是 [AppPageHeader.content]（搜索框）的固定高度。
const double kAppHeaderHeight = 56;

/// 展开态（大标题）页头高度。
///
/// 88 = 大标题顶边 38 + 字高 33.6 + 下留白 16.4。
///
/// 旧版是 112 = 操作行 56 + 大标题行 56，两段上下叠放。问题在于统计页与设置页
/// 的 actions 是空的、也没有返回箭头，那 56 就是一整片纯空白，加上状态栏顶部
/// 要吃掉近 20% 屏高。现在让大标题上缘插进操作行那一带（38 < 56）：横向上
/// 标题在最左、图标在最右，两者根本碰不到面，于是这 24px 是纯赚的。
const double kAppHeaderExpandedHeight = 88;

/// 页头静止时占掉的屏幕高度（含状态栏）。
///
/// 给「页头之下还压着常驻面板」的页面用（记一笔页的数字键盘）：这类页面要靠
/// 剩余高度决定面板形态，而页头现在活在滚动体内部，量不到自己脚下还剩多少。
double appHeaderRestingExtent(BuildContext context) =>
    MediaQuery.paddingOf(context).top + kAppHeaderExpandedHeight;

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

/// 展开态标题顶边。见 [kAppHeaderExpandedHeight] 里的高度构成说明。
const double _kTitleTopExpanded = 38;

/// 折叠态标题左缘：有返回箭头时让位到箭头右侧。
const double _kTitleLeftCollapsedWithBack = 56;

/// 折叠后页头底部的分隔线。
///
/// 用 [AppColors.lineSoft] 而非 [AppColors.line]：贴边长直线上深一档的灰
/// 会压出明显硬边，显脏。厚度 0.6 存在感刚够分层，不至于变成装饰线。
const double _kDividerThickness = 0.6;

/// 吸顶毛玻璃的模糊半径（完全折叠时的值）。
const double _kGlassBlurSigma = 20;

/// 吸顶毛玻璃的底色不透明度（完全折叠时的值）。
///
/// 0.82 而非更低：页头里是 20px 的标题文字，背后穿过的可能是深色卡片或账单
/// 图片，底色一薄标题就发灰。留 18% 的通透已经足够看出内容在下面流动。
const double _kGlassOpacity = 0.82;

/// 页头标题统一样式（折叠态基准）。
///
/// - w700：比 w800 更透气，大字重在中文黑体上容易糊成一坨
/// - letterSpacing -0.2：中文标题收紧一点更精致（现代 App 的通用手法）
TextStyle kAppHeaderTitleStyle(AppColors colors) => TextStyle(
  fontSize: _kTitleSizeCollapsed,
  fontWeight: FontWeight.w700,
  height: _kTitleHeight,
  letterSpacing: -0.2,
  color: colors.ink,
);

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
    final colors = context.colors;
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
            color: active ? colors.ink : colors.inactive,
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

/// 页头的底板：底色 + 吸顶毛玻璃 + 折叠后浮现的分隔线。
///
/// [translucency] 就是折叠进度：0 = 完全展开（页头背后是空的，什么都不用做），
/// 1 = 完全吸顶（底色降到 [_kGlassOpacity]、模糊拉到 [_kGlassBlurSigma]）。
class _HeaderGlass extends StatelessWidget {
  const _HeaderGlass({
    required this.translucency,
    required this.background,
    required this.child,
  });

  final double translucency;

  /// 页头条底色。透明时页面自身的背景（如记一笔页的图片背板）会透上来。
  /// null 表示取页面底色。
  final Color? background;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = background ?? colors.canvas;
    // 全透明底（记一笔页把图片背板铺在页头之下）不参与插值：
    // 对 alpha 为 0 的颜色再乘一个系数，只会得到另一个全透明色。
    final fill = base.a == 0
        ? base
        : base.withValues(
            alpha: base.a * (1 - (1 - _kGlassOpacity) * translucency),
          );

    Widget layer = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: Border(
          bottom: BorderSide(
            // 分隔线随折叠淡入：静止时页头与内容同色无缝，
            // 一滚才分层 —— iOS / Notion 的通用手法。
            color: colors.lineSoft.withValues(alpha: translucency),
            width: _kDividerThickness,
          ),
        ),
      ),
      child: child,
    );

    // 展开态页头背后没有内容，套 BackdropFilter 纯属白烧一次离屏合成 ——
    // 它每帧都要把背后已绘制的像素读回来重新模糊，而这恰好是最常见的静止态。
    if (translucency > 0) {
      layer = BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: _kGlassBlurSigma * translucency,
          sigmaY: _kGlassBlurSigma * translucency,
        ),
        child: layer,
      );
    }

    // 两件事都要它：给 BackdropFilter 划定作用范围，
    // 以及裁掉折叠过程中短暂超出高度的标题。
    return ClipRect(child: layer);
  }
}

/// 页头内容 —— 一级页与二级页共用的唯一布局实现。
///
/// [t] 是折叠进度（0 = 完全展开的大标题，1 = 完全折叠的紧凑条）。
/// 所有随滚动变化的量都由它线性插值，过渡连续无跳变。
///
/// 布局是「一层钉死的操作行 + 一个会移动缩放的标题」：
/// 只有标题随 t 动（字号 28↔20、顶边 38↔16、左缘 20↔56），
/// 操作行始终居中在顶部 56 区内，绝不漂移。
class _HeaderContent extends StatelessWidget {
  const _HeaderContent({
    required this.t,
    this.title,
    this.content,
    this.actions,
    this.showBack = false,
  });

  final double t;
  final String? title;
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
    final colors = context.colors;

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
          child: Text(
            title!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kAppHeaderTitleStyle(colors).copyWith(
              fontSize: _lerp(_kTitleSizeExpanded, _kTitleSizeCollapsed),
              // 字号越大字距越要收紧，否则大字显松散。
              letterSpacing: _lerp(-0.6, -0.2),
            ),
          ),
        ),
      ],
    );
  }

  double _lerp(double expanded, double collapsed) =>
      expanded + (collapsed - expanded) * t;
}

/// 折叠页头的 sliver 实现。
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  const _HeaderDelegate({
    required this.topPadding,
    required this.collapsible,
    required this.title,
    required this.content,
    required this.actions,
    required this.showBack,
    required this.background,
  });

  /// 状态栏高度。页头把它包进自己的 extent，毛玻璃才能一路铺到屏幕顶端 ——
  /// 若把状态栏留给外层 SafeArea，那块会是一条不透明的纯色带，
  /// 和它下面的毛玻璃之间压出一道横向色阶，比不做毛玻璃更难看。
  final double topPadding;

  /// false 时恒为折叠态（[AppPageHeader.content] 搜索框模式）。
  final bool collapsible;

  final String? title;
  final Widget? content;
  final List<Widget>? actions;
  final bool showBack;
  final Color? background;

  @override
  double get minExtent => topPadding + kAppHeaderHeight;

  @override
  double get maxExtent =>
      topPadding + (collapsible ? kAppHeaderExpandedHeight : kAppHeaderHeight);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    // range 为 0 即搜索框模式：没有可折叠的余量，恒定按吸顶态渲染。
    final t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    return SizedBox.expand(
      child: _HeaderGlass(
        translucency: t,
        background: background,
        child: Padding(
          padding: EdgeInsets.only(top: topPadding),
          // 页头浮在内容之上，水波必须画在毛玻璃这一层。
          // 若沿用祖先 Scaffold 的 Material，水波会落到滚动内容底下看不见。
          child: Material(
            type: MaterialType.transparency,
            child: _HeaderContent(
              t: t,
              title: title,
              content: content,
              actions: actions,
              showBack: showBack,
            ),
          ),
        ),
      ),
    );
  }

  // actions 是每帧新建的 widget 列表，无从逐个比对；
  // 而本方法只在外层重建时被问一次（不是每个滚动帧），恒真的代价可以忽略。
  @override
  bool shouldRebuild(covariant _HeaderDelegate oldDelegate) => true;
}

/// 页头 sliver。放在 [CustomScrollView.slivers] 的**第一位**。
///
/// 由 [AppPageHeader] / [AppTopBar] 内部使用；页面若要自建 CustomScrollView
/// （例如底部还压着一块常驻面板），直接用这个。
class AppHeaderSliver extends StatelessWidget {
  const AppHeaderSliver({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.showBack = false,
    this.background,
  }) : assert(title != null || content != null, 'title 与 content 至少提供一个');

  final String? title;

  /// 非空时替换标题区域。此时页头固定为折叠高度（输入框不该被缩放）。
  final Widget? content;

  final List<Widget>? actions;
  final bool showBack;

  /// 页头条底色，null 表示取页面底色。
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _HeaderDelegate(
        topPadding: MediaQuery.paddingOf(context).top,
        collapsible: content == null,
        title: title,
        content: content,
        actions: actions,
        showBack: showBack,
        background: background,
      ),
    );
  }
}

/// 应用统一页头（一级 Tab 页用）。
///
/// 静止时是 [kAppHeaderExpandedHeight] 高的大标题封面，内容滚动时平滑折叠成
/// [kAppHeaderHeight] 紧凑条、转为毛玻璃并浮现分隔线。
///
/// 页面内容以 sliver 交进 [slivers]，本组件负责套 [CustomScrollView] 并把
/// 页头插在最前 —— 页头是 pinned sliver，必须和内容同处一个滚动体，
/// 内容才能滚到它背后去（毛玻璃的前提）。
///
/// 页头自带状态栏留白，**外层不要再包 SafeArea(top: true)**，否则会双倍留白，
/// 毛玻璃也铺不到屏幕顶端。
///
/// 用法：`AppPageHeader(title: '设置', slivers: [SliverList(...)])`
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.slivers,
    this.title,
    this.content,
    this.actions,
    this.controller,
  }) : assert(title != null || content != null, 'title 与 content 至少提供一个');

  final String? title;

  /// 非空时替换标题区域（如记账页的搜索框）。此时页头固定为折叠高度。
  final Widget? content;

  final List<Widget>? actions;

  /// 页头下方的滚动内容。
  final List<Widget> slivers;

  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      slivers: [
        AppHeaderSliver(title: title, content: content, actions: actions),
        ...slivers,
      ],
    );
  }
}

/// 应用统一页头（二级页面用）。
///
/// 与一级页 [AppPageHeader] 共用 [_HeaderDelegate]，观感完全一致：
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
/// 用法：`Scaffold(body: AppTopBar(title: '记一笔', slivers: [...]))`
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    required this.slivers,
    this.actions,
    this.backgroundColor,
    this.bottom,
    this.controller,
  });

  final String title;
  final List<Widget>? actions;

  /// 整页底色。传 [Colors.transparent] 可让页面在本组件之下自绘背景
  /// （记一笔页把账单图片铺在这一层）。null 表示取页面底色。
  final Color? backgroundColor;

  /// 页头下方的滚动内容。
  final List<Widget> slivers;

  /// 贴在滚动区**下方**的常驻面板（记一笔页的数字键盘）。
  ///
  /// 它不进滚动体，所以内容不会滚到它背后 —— 这是「常驻输入面板」的定义，
  /// 不是遗漏。要自己处理底部安全区。
  final Widget? bottom;

  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final background = backgroundColor ?? context.colors.canvas;
    final scroll = CustomScrollView(
      controller: controller,
      slivers: [
        AppHeaderSliver(
          title: title,
          actions: actions,
          showBack: Navigator.of(context).canPop(),
          background: background,
        ),
        ...slivers,
      ],
    );
    return Material(
      color: background,
      child: bottom == null
          ? scroll
          : Column(
              children: [
                Expanded(child: scroll),
                bottom!,
              ],
            ),
    );
  }
}
