import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../core/appearance/appearance.dart';
import '../core/preferences/quick_tally_mode.dart';
import '../core/theme/app_motion.dart';
import '../core/theme/app_theme.dart';
import '../features/ledger/presentation/ledger_screen.dart';
import '../features/ledger/presentation/transaction_editor.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';

/// 三个主页面 + 贴底固定导航栏。
///
/// 换 IndexedStack 为 PageView：左右滑动即可切页，与底部导航双向同步。
/// 导航栏贴底铺满（不再是悬浮胶囊），三个 tab 均分宽度，选中态是一颗随
/// index 平滑滑动的高亮胶囊——胶囊内缩留呼吸，不撑满格子。
/// 「记一笔」是居中悬浮的主按钮（FAB），落在导航栏上方：
/// 居中比右下角更适合单手（尤其左手）拇指够到。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 等首帧挂上 Navigator 再读偏好：开了快速记账就推记账页。
    // 只在本次挂载走一次，设置里中途打开开关不会立刻弹页。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openQuickTallyIfNeeded();
    });
  }

  Future<void> _openQuickTallyIfNeeded() async {
    await ref.read(quickTallyModeProvider.notifier).ready;
    if (!mounted || !ref.read(quickTallyModeProvider)) return;
    await _addTransaction();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addTransaction() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const TransactionEditor()));
  }

  void _jumpTo(int value) {
    if (value == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = value);
    // 点击底部导航直接跳转，不走滚动动画；滑动切换仍保留 PageView 的滑动动画。
    _controller.jumpToPage(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _controller,
        onPageChanged: (value) => setState(() => _index = value),
        physics: const ClampingScrollPhysics(),
        children: [
          const LedgerScreen(),
          const StatisticsScreen(),
          SettingsScreen(active: _index == 2),
        ],
      ),
      // 记一笔：居中悬浮在导航栏上方，只在首页（明细）出现，
      // 避免遮挡统计/设置页内容。居中比右下角更好按，左右手都够得到。
      // 用 centerFloat 而非 centerDocked：docked 会让 FAB 半嵌进栏里，
      // 正好压住中间的「统计」tab。
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: AnimatedSwitcher(
        duration: context.motion(const Duration(milliseconds: 200)),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: _index == 0
            ? FloatingActionButton(
                key: const ValueKey('add'),
                onPressed: _addTransaction,
                backgroundColor: context.colors.primary,
                // 深色下品牌蓝被提亮，白字对比不够；与 forui primaryForeground 同一条规则。
                // canvasBase 而不是 canvas：这是压在主色圆按钮上的**前景色**，
                // 壁纸模式下拿到透明的话加号会直接消失。
                foregroundColor: context.colors.isDark
                    ? context.colors.canvasBase
                    : Colors.white,
                elevation: 3,
                shape: const CircleBorder(),
                child: const Icon(FLucideIcons.plus, size: 26),
              )
            : const SizedBox.shrink(key: ValueKey('none')),
      ),
      bottomNavigationBar: _BottomNavBar(
        index: _index,
        onChange: _jumpTo,
        style: ref.watch(navBarStyleProvider),
      ),
    );
  }
}

/// 底部导航栏：三个 tab 均分宽度。
///
/// 选中态不做底色块——只靠图标/文字变品牌蓝 + 图标弹入来表达，
/// 是三个 tab 场景下最干净的处理。
///
/// 两种形态（见 [NavBarStyle]）共用同一个 [Row]，区别只在外壳：
/// - 贴底：铺满 + 一道极淡顶线，安全区留白吃在栏内；
/// - 悬浮：四周留白的胶囊 + 阴影，安全区留白吃在栏外。
///
/// 悬浮档**没有**让内容滚到栏下面。那需要三个一级页各自重算滚动内边距，
/// 而用户感知到的「悬浮」全部来自这圈留白和圆角，穿透与否看不出来。
class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.index,
    required this.onChange,
    required this.style,
  });

  final int index;
  final ValueChanged<int> onChange;
  final NavBarStyle style;

  static const _items = [
    (icon: FLucideIcons.receiptText, label: '明细'),
    (icon: FLucideIcons.chartPie, label: '统计'),
    (icon: FLucideIcons.settings2, label: '设置'),
  ];

  /// 内容区高度（不含系统安全区）。
  static const _barHeight = 58.0;

  /// 悬浮档的胶囊四周留白。左右取 16 与一级页内容的 gutter 同源；
  /// 底部 10 是「离屏幕边缘足够远才像浮着」与「别把内容挤太多」之间的折中。
  static const _floatInset = EdgeInsets.fromLTRB(16, 0, 16, 10);

  /// 悬浮档的胶囊高度。比贴底档矮一档：它已经靠阴影和留白分层了，
  /// 不需要再靠高度撑存在感，矮一点还能把留白的成本抵掉一半。
  static const _floatHeight = 54.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final row = Row(
      children: [
        for (var i = 0; i < _items.length; i++)
          Expanded(
            child: _NavItem(
              icon: _items[i].icon,
              label: _items[i].label,
              selected: index == i,
              onTap: () => onChange(i),
            ),
          ),
      ],
    );

    if (style == NavBarStyle.floating) {
      return Padding(
        padding: _floatInset.add(EdgeInsets.only(bottom: bottomInset)),
        child: Container(
          height: _floatHeight,
          decoration: BoxDecoration(
            color: colors.surface,
            // 胶囊：半径 = 高度一半，不跟全局圆角档位走。选「直角」时把
            // 悬浮栏压成方块，那不是圆角设置该管的事（见 AppRadius 文档）。
            borderRadius: BorderRadius.circular(_floatHeight / 2),
            border: Border.all(color: colors.lineSoft),
            // 沿用卡片阴影而不是另调一份：悬浮栏和内容卡是同一个「浮起来的
            // 白面」，浮在不同高度会让人以为它们不是一套东西。
            boxShadow: colors.shadowCard,
          ),
          clipBehavior: Clip.antiAlias,
          child: row,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.lineSoft)),
      ),
      child: SizedBox(
        height: _barHeight + bottomInset,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: row,
        ),
      ),
    );
  }
}

/// 单个 tab：图标在上、小字在下。
///
/// 图标常态就是正常大小（1.0）；**只在被激活的那一刻**播一次脉冲——
/// 先快速压到 [_dip] 再弹回 1.0（[Curves.easeOutBack]带一点超调）。
/// 缩放只作用在图标上，文字仅跟随颜色渐变。
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  /// 下压到的最小倍率：再小图标就像「闪没了」，不像被按下去。
  static const _dip = 0.72;

  static const _pulseDuration = Duration(milliseconds: 380);

  late final AnimationController _pulse = AnimationController(
    duration: _pulseDuration,
    vsync: this,
  );

  /// 控制器停在 0 时序列给出 1.0，所以静止态天然是正常大小，无需额外分支。
  /// 下压占 30% 时长（要快，才有「被按了一下」的因果感），回弹占 70%。
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: _dip,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: _dip,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 70,
    ),
  ]).animate(_pulse);

  @override
  void didUpdateWidget(_NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在「未选中 → 选中」的瞬间播；取消选中不播，
    // 否则切页时旧 tab 也会跟着抖一下。
    if (widget.selected && !oldWidget.selected) {
      // 时长在这里而不是在 build 里定：`forward()` 会把当时的 duration 抄进
      // 一条 simulation，之后再改字段影响不到已经跑起来的这一次。
      // 动效关闭档下这里是 Duration.zero，控制器直接落到终点，不需要分支。
      _pulse.duration = context.motion(_pulseDuration);
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: TweenAnimationBuilder<Color?>(
        duration: context.motion(const Duration(milliseconds: 220)),
        curve: Curves.easeOutCubic,
        tween: ColorTween(
          end: widget.selected ? colors.primary : colors.inactive,
        ),
        builder: (context, color, _) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // AnimatedBuilder 只包Icon：脉冲的每一帧都不去重建下面的文字。
            AnimatedBuilder(
              animation: _scale,
              builder: (context, child) =>
                  Transform.scale(scale: _scale.value, child: child),
              child: Icon(widget.icon, size: 21, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              widget.label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                height: 1.1,
                // 小字用常规字重，灰色粗体会发脏；选中态靠颜色区分即可。
                fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
