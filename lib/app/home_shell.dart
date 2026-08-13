import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

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
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final PageController _controller = PageController();
  int _index = 0;

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
        children: const [LedgerScreen(), StatisticsScreen(), SettingsScreen()],
      ),
      // 记一笔：居中悬浮在导航栏上方，只在首页（明细）出现，
      // 避免遮挡统计/设置页内容。居中比右下角更好按，左右手都够得到。
      // 用 centerFloat 而非 centerDocked：docked 会让 FAB 半嵌进栏里，
      // 正好压住中间的「统计」tab。
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: _index == 0
            ? FloatingActionButton(
                key: const ValueKey('add'),
                onPressed: _addTransaction,
                backgroundColor: context.colors.primary,
                // 深色下品牌蓝被提亮，白字对比不够；与 forui primaryForeground 同一条规则。
                foregroundColor: context.colors.isDark
                    ? context.colors.canvas
                    : Colors.white,
                elevation: 3,
                shape: const CircleBorder(),
                child: const Icon(FLucideIcons.plus, size: 26),
              )
            : const SizedBox.shrink(key: ValueKey('none')),
      ),
      bottomNavigationBar: _BottomNavBar(index: _index, onChange: _jumpTo),
    );
  }
}

/// 贴底固定导航栏：白底 + 一道极淡顶线，三个 tab 均分宽度。
///
/// 选中态不做底色块——只靠图标/文字变品牌蓝 + 图标弹入来表达，
/// 是三个 tab 场景下最干净的处理。
class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({required this.index, required this.onChange});

  final int index;
  final ValueChanged<int> onChange;

  static const _items = [
    (icon: FLucideIcons.receiptText, label: '明细'),
    (icon: FLucideIcons.chartPie, label: '统计'),
    (icon: FLucideIcons.settings2, label: '设置'),
  ];

  /// 内容区高度（不含系统安全区）。
  static const _barHeight = 58.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.lineSoft)),
      ),
      child: SizedBox(
        height: _barHeight + bottomInset,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Row(
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
          ),
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

  late final AnimationController _pulse = AnimationController(
    duration: const Duration(milliseconds: 380),
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
    if (widget.selected && !oldWidget.selected) _pulse.forward(from: 0);
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
        duration: const Duration(milliseconds: 220),
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
