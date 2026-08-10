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
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
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
    (icon: FLucideIcons.chartColumn, label: '统计'),
    (icon: FLucideIcons.settings2, label: '设置'),
  ];

  /// 内容区高度（不含系统安全区）。
  static const _barHeight = 58.0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.lineSoft)),
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
/// 选中态只改颜色（渐变到品牌蓝），不加底色块；
/// 同时图标从 0.6 倍弹到 1 倍（[Curves.easeOutBack] 带一点回弹超调）。
class _NavItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 340),
        // easeOutBack 在 0→1 途中会冲过 1 再回落，做出「弹一下」的手感；
        // 反向（取消选中）用 easeOutCubic 平静收回，避免两个 tab 同时弹。
        curve: selected ? Curves.easeOutBack : Curves.easeOutCubic,
        tween: Tween(end: selected ? 1.0 : 0.0),
        builder: (context, t, _) {
          // t 会被 easeOutBack 推到 1 以上，颜色插值必须夹回 [0,1]。
          final color = Color.lerp(
            AppColors.inactive,
            AppColors.primary,
            t.clamp(0.0, 1.0),
          );
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.scale(
                // 0.6 → 1.0：起点不能太小，否则图标像「从无到有」而非放大。
                scale: 0.6 + 0.4 * t,
                child: Icon(icon, size: 21, color: color),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  height: 1.1,
                  // 小字用常规字重，灰色粗体会发脏；选中态靠颜色区分即可。
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
