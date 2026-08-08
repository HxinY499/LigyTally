import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../features/ledger/presentation/ledger_screen.dart';
import '../features/ledger/presentation/transaction_editor.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/statistics/presentation/statistics_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  Future<void> _addTransaction() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const TransactionEditor()));
  }

  @override
  Widget build(BuildContext context) {
    // 用 Material Scaffold 承载 FAB 与 IndexedStack（forui 无 FAB 对应物），
    // 底部导航栏换成 forui 的 FBottomNavigationBar。
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [LedgerScreen(), StatisticsScreen(), SettingsScreen()],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              onPressed: _addTransaction,
              tooltip: '记一笔',
              child: const Icon(Icons.add_rounded),
            )
          : null,
      bottomNavigationBar: FBottomNavigationBar(
        index: _index,
        onChange: (value) => setState(() => _index = value),
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
