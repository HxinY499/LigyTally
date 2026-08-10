import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../features/ledger/presentation/ledger_screen.dart';
import '../features/ledger/presentation/transaction_editor.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';

/// 三个主页面 + 底部导航栏。
///
/// 换 IndexedStack 为 PageView：左右滑动即可切页，与底部导航双向同步。
/// 手势物理关掉 keepAlive 会让 StreamBuilder 重订阅，性能上不划算——
/// 用 [AutomaticKeepAliveClientMixin]？三页都是流数据 + Riverpod，
/// 直接 PageView 已够用，实测没有明显开销。
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
    _controller.animateToPage(
      value,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              onPressed: _addTransaction,
              tooltip: '记一笔',
              child: const Icon(FLucideIcons.plus),
            )
          : null,
      bottomNavigationBar: FBottomNavigationBar(
        index: _index,
        onChange: _jumpTo,
        children: const [
          FBottomNavigationBarItem(
            icon: Icon(FLucideIcons.receiptText),
            label: Text('明细'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(FLucideIcons.chartColumn),
            label: Text('统计'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(FLucideIcons.settings2),
            label: Text('设置'),
          ),
        ],
      ),
    );
  }
}
