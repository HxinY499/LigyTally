import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../core/theme/app_theme.dart';
import '../features/ledger/presentation/ledger_screen.dart';
import '../features/ledger/presentation/transaction_editor.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';

/// 三个主页面 + 悬浮胶囊底部导航栏。
///
/// 换 IndexedStack 为 PageView：左右滑动即可切页，与底部导航双向同步。
/// 导航栏三个 tab 均分宽度，选中态是一颗随 index 平滑滑动的高亮胶囊。
/// 「记一笔」不再占用导航栏中位，改为首页右下角的悬浮主按钮（FAB）。
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
    setState(() => _index = value);
    // 点击底部导航直接跳转，不走滚动动画；滑动切换仍保留 PageView 的滑动动画。
    _controller.jumpToPage(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _controller,
        onPageChanged: (value) => setState(() => _index = value),
        physics: const ClampingScrollPhysics(),
        children: const [LedgerScreen(), StatisticsScreen(), SettingsScreen()],
      ),
      // 记一笔：只在首页（明细）出现，避免遮挡统计/设置页内容。
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
                elevation: 4,
                shape: const CircleBorder(),
                child: const Icon(FLucideIcons.plus, size: 26),
              )
            : const SizedBox.shrink(key: ValueKey('none')),
      ),
      bottomNavigationBar: _PillNavBar(index: _index, onChange: _jumpTo),
    );
  }
}

/// 悬浮胶囊导航栏：三个 tab 均分，选中态为平滑滑动的高亮胶囊。
class _PillNavBar extends StatelessWidget {
  const _PillNavBar({required this.index, required this.onChange});

  final int index;
  final ValueChanged<int> onChange;

  static const _items = [
    (icon: FLucideIcons.receiptText, label: '明细'),
    (icon: FLucideIcons.chartColumn, label: '统计'),
    (icon: FLucideIcons.settings2, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
      child: Container(
        height: 64,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 滑动高亮胶囊：占 1/3 宽，随选中项平移。
            AnimatedAlign(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment(index - 1.0, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / _items.length,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            Row(
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
          ],
        ),
      ),
    );
  }
}

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
      child: TweenAnimationBuilder<Color?>(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        tween: ColorTween(end: selected ? AppColors.primary : AppColors.muted),
        builder: (context, color, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
