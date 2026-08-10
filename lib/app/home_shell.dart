import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../core/theme/app_theme.dart';
import '../features/ledger/presentation/ledger_screen.dart';
import '../features/ledger/presentation/transaction_editor.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';

/// 三个主页面 + 自定义现代底部导航栏。
///
/// 换IndexedStack 为 PageView：左右滑动即可切页，与底部导航双向同步。
/// 导航栏采用「选中态滑动高亮胶囊 + 中央凸起主按钮」形态：
/// 左侧两个 tab（明细/统计）、右侧一个 tab（设置），中间嵌入凸起的
/// 品牌绿「记一笔」主按钮。选中项用 [_PillNavBar] 内部的
/// [AnimatedAlign] 高亮胶囊平滑滑动，图标/文字随之切换颜色。
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
        children: const [
          LedgerScreen(),
          StatisticsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _PillNavBar(
        index: _index,
        onChange: _jumpTo,
        onAdd: _addTransaction,
      ),
    );
  }
}

/// 悬浮胶囊导航栏。
///
/// 布局：`[明细] [统计]  (＋)  [设置]`
/// - 选中态是一颗随 index 平滑滑动的品牌绿高亮胶囊；
/// - 中央 `＋` 是凸起的品牌绿主按钮，点击进入记账。
class _PillNavBar extends StatelessWidget {
  const _PillNavBar({
    required this.index,
    required this.onChange,
    required this.onAdd,
  });

  final int index;
  final ValueChanged<int> onChange;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            height: 64,
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
            child: Row(
              children: [
                Expanded(
                  child: _NavItem(
                    icon: FLucideIcons.receiptText,
                    label: '明细',
                    selected: index == 0,
                    onTap: () => onChange(0),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: FLucideIcons.chartColumn,
                    label: '统计',
                    selected: index == 1,
                    onTap: () => onChange(1),
                  ),
                ),
                // 中央主按钮留白位。
                const SizedBox(width: 72),
                Expanded(
                  child: _NavItem(
                    icon: FLucideIcons.settings2,
                    label: '设置',
                    selected: index == 2,
                    onTap: () => onChange(2),
                  ),
                ),
              ],
            ),
          ),
          // 中央凸起主按钮：记一笔。
          Positioned(
            top: -16,
            child: _CenterAddButton(onTap: onAdd),
          ),
        ],
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
    final color = selected ? AppColors.primary : AppColors.muted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            // 选中态才展开文字，未选中收起——形成胶囊内滑动的观感。
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterAddButton extends StatelessWidget {
  const _CenterAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 4),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.36),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(FLucideIcons.plus, color: Colors.white, size: 26),
      ),
    );
  }
}
