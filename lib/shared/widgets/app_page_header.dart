import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/theme/app_theme.dart';

/// ── 页头设计令牌（唯一真相源）──────────────────────────────
///
/// 全应用**所有**页头都由本文件渲染。一级 Tab 页与二级页共用同一套紧凑几何，
/// 但只有一级页有大标题折叠。
///
/// 一级页是「大标题 + 滚动折叠 + 吸顶毛玻璃」：静止时 28px 大字左对齐，
/// 内容一滚缩到 20px 收进 56 高的紧凑条，同时转为毛玻璃。
/// 二级页（记一笔、分类管理）默认就是那条紧凑条：返回与标题同一行，
/// 不再展开——任务页要的是立刻动手，大标题只会和返回箭头挤在一起。
///
/// 实现形态是 [SliverPersistentHeader]（pinned），**不是**并列在 Column 里的
/// 固定条。这是毛玻璃唯一可行的形态：Column 形态下内容永远走不到页头背后。
/// 代价是**页面内容必须以 sliver 形式交进来**，见 [AppPageHeader.slivers]。
///
/// 四条硬性一致规则（由 test/app_page_header_test.dart 锁死）：
/// 1. **所有一级页展开高度相同** = [kAppHeaderExpandedHeight]，
///    没有 actions 的页面就留空，不缩高度 —— 否则切 Tab 时内容起始线会跳。
/// 2. **所有紧凑态标题垂直中心线相同**（一级页折叠后、二级页、搜索框）。
/// 3. **操作图标与标题垂直中心对齐**：展开时跟大标题同一条线，折叠后收到
///    紧凑条中心。图标右缘恒为 gutter。
/// 4. 毛玻璃**只在内容穿过后存在**：静止时不该挂 BackdropFilter

/// 折叠态页头高度（不含状态栏）。也是 [AppPageHeader.content]（搜索框）的固定高度。
const double kAppHeaderHeight = 56;

/// 展开态（大标题）页头高度。
///
/// 88 = 大标题顶边 38 + 字高 33.6 + 下留白 16.4。
///
/// 旧版是 112 = 操作行 56 + 大标题行 56，两段上下叠放。问题在于统计页与设置页
/// 的 actions 是空的、也没有返回箭头，那 56 就是一整片纯空白，加上状态栏顶部
/// 要吃掉近 20% 屏高。现在让大标题上缘插进操作行那一带（38 < 56）：横向上
/// 标题在最左、图标在最右。有 actions 时图标垂直中心跟大标题对齐，
/// 不再钉死在顶栏——否则漏斗会浮在「统计」上方，看起来像没排好。
const double kAppHeaderExpandedHeight = 88;

/// 二级页页头占掉的屏幕高度（含状态栏）。
///
/// 二级页没有大标题、恒为 [kAppHeaderHeight] 紧凑条。给「页头之下还压着
/// 常驻面板」的页面用（记一笔页的数字键盘）：页头活在滚动体内部，
/// 量不到自己脚下还剩多少，只能从整页高度里把这段减掉。
double appHeaderRestingExtent(BuildContext context) =>
    MediaQuery.paddingOf(context).top + kAppHeaderHeight;

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

/// 展开态标题垂直中心。有 actions 时图标跟这条线对齐。
const double _kTitleCenterExpanded =
    _kTitleTopExpanded + _kTitleSizeExpanded * _kTitleHeight / 2;

/// 折叠态标题垂直中心，也是紧凑条中心。
const double _kTitleCenterCollapsed =
    _kTitleTopCollapsed + _kTitleSizeCollapsed * _kTitleHeight / 2;

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

/// 壁纸模式下铬层自带的一层实色蒙版。
///
/// 铺了壁纸之后页面底色（`AppColors.canvas`）整块让位给壁纸变成透明，铬层
/// 没有底色可借，而它上面压着 20px 的标题。这一层是标题的可读性下限，
/// 也正是「浓度」滑杆能一路拖到全透明的前提——保护范围收窄到铬层这一条，
/// 用户就能把页面其余部分的照片看全。
///
/// 0.55 是让 `ink` 压在最坏那张照片上仍能过 WCAG AA 的下限。
const double _kChromeScrimOpacity = 0.55;

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

/// 吸顶铬层的底板：底色 + 毛玻璃 + 随通透度淡入的分隔线。
///
/// 页头、记账页月份条、分类管理收支条共用这一份，令牌才能对得上。
/// [translucency] 0 = 背后没有内容穿过（不挂 [BackdropFilter]），
/// 1 = 完全吸顶（底色降到 [_kGlassOpacity]、模糊拉到 [_kGlassBlurSigma]）。
class AppChromeGlass extends StatelessWidget {
  const AppChromeGlass({
    super.key,
    required this.translucency,
    required this.child,
    this.background,
  });

  final double translucency;

  /// 底色。
  ///
  /// null = 「借页面底色」，也把「壁纸模式下该自带蒙版」的判断交给本组件。
  /// 显式传一个颜色 = 调用方自己负责背后是什么，本组件一个像素都不加——
  /// 记一笔页传 [Colors.transparent] 就是要让自己铺的账单图背板透上来，
  /// 那里不能被蒙版糊住。
  final Color? background;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final explicit = background;
    // 壁纸模式下页面底色是透明的（让位给壁纸），铬层没有底色可借，
    // 得自己铺一层最薄的实色，见 [_kChromeScrimOpacity]。
    final scrim = explicit == null && colors.hasWallpaper;
    final base =
        explicit ??
        (scrim
            ? colors.canvasBase.withValues(alpha: _kChromeScrimOpacity)
            : colors.canvas);
    // 蒙版不跟着折叠变薄。
    //
    // 那套变薄的算法是为「背后有内容流过」准备的通透感，而蒙版存在的理由
    // 恰好相反：内容开始从铬层背后穿过去的那一刻，正是标题最需要底的时候，
    // 再薄一档就白铺了。
    //
    // 全透明底（记一笔页的图片背板）同样不参与插值：对 alpha 为 0 的颜色
    // 再乘一个系数，只会得到另一个全透明色。
    final fill = scrim || base.a == 0
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
/// 布局是「一层跟着标题走的操作行 + 一个会移动缩放的标题」：
/// 标题随 t 动（字号 28↔20、顶边 38↔16），操作行的垂直中心同步对齐标题，
/// 展开时和「统计」同一条线，折叠后收到紧凑条中心。
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
        // ── 操作行：垂直中心跟着标题走 ──
        Positioned(
          top: _lerp(
            _kTitleCenterExpanded - kAppHeaderHeight / 2,
            _kTitleCenterCollapsed - kAppHeaderHeight / 2,
          ),
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
        // ── 标题：字号和顶边随 t 走，操作行中心跟着它对齐 ──
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

  /// false 时恒为折叠态（二级页、搜索框）。
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
    // range 为 0：二级页 / 搜索框，没有可折叠的余量，标题按紧凑态渲染。
    final t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    // 紧凑条的 shrinkOffset 仍随滚动从 0 涨到 maxExtent（Flutter 传的是
    // min(scrollOffset, maxExtent)，不是 max-min）。用它开毛玻璃：
    // 静止为 0，内容一开始上移就淡入。overlapsContent 不能用——
    // 它表示「上面的 sliver 压到我」，第一个 sliver 上永远是 false。
    final translucency = range <= 0
        ? (minExtent <= 0 ? 0.0 : (shrinkOffset / minExtent).clamp(0.0, 1.0))
        : t;
    return SizedBox.expand(
      child: AppChromeGlass(
        translucency: translucency,
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
    this.collapsible = true,
    this.background,
  }) : assert(title != null || content != null, 'title 与 content 至少提供一个');

  final String? title;

  /// 非空时替换标题区域。此时页头固定为折叠高度（输入框不该被缩放）。
  final Widget? content;

  final List<Widget>? actions;
  final bool showBack;

  /// false 时恒为 [kAppHeaderHeight] 紧凑条，不随滚动展开。
  /// 二级页和搜索框走这条；一级 Tab 页才有大标题折叠。
  final bool collapsible;

  /// 页头条底色，null 表示取页面底色。
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _HeaderDelegate(
        topPadding: MediaQuery.paddingOf(context).top,
        collapsible: collapsible && content == null,
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
/// 与一级页共用 [_HeaderContent] 的紧凑态：返回箭头与 20px 标题同一行，
/// **没有**大标题、也不随滚动折叠。任务页（记一笔、分类管理）要的是
/// 立刻动手，不是再看一遍封面。
///
/// 毛玻璃仍在：内容滚过页头背后时挂上，和一级页吸顶后同一套令牌。
///
/// 刻意**不复用** Material [AppBar]：AppBar 按 leadingWidth + titleSpacing
/// 推挤标题，实测导致「有返回 64 / 无返回 16」两种左缘；也因此本组件
/// **不是** PreferredSizeWidget，不能塞进 `Scaffold.appBar`，要当 body 用。
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
    final scroll = CustomScrollView(
      controller: controller,
      slivers: [
        AppHeaderSliver(
          title: title,
          actions: actions,
          showBack: Navigator.of(context).canPop(),
          collapsible: false,
          // 刻意把**没解析过**的值传下去：页头要能分清「调用方没指定」和
          // 「调用方指定了透明」——前者在壁纸模式下需要自带一层蒙版，
          // 后者（记一笔页）绝不能被糊住。解析成 canvas 再传，这两种就
          // 变成同一个透明色，分不出来了。
          background: backgroundColor,
        ),
        ...slivers,
      ],
    );
    return Material(
      // 页底仍然要解析：壁纸模式下它是透明的，壁纸从这里透上来。
      color: backgroundColor ?? context.colors.canvas,
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
