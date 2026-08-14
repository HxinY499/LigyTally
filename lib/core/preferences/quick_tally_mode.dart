import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 快速记账：打开 App 后直接进入记账页。
///
/// 默认关闭。读法与其它偏好一致：先返回默认值，异步覆盖，
/// 不让 UI 去 await 一次读盘。
///
/// [ready] 在首次读盘结束后完成，给启动跳转用——必须等盘上的值回来
/// 再决定推不推记账页，否则会按默认「关」漏掉已打开的用户。
const _prefsKey = 'quick_tally_mode';

class QuickTallyModeController extends Notifier<bool> {
  final Completer<void> _ready = Completer<void>();

  Future<void> get ready => _ready.future;

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_prefsKey);
      if (value != null && value != state) state = value;
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<void> setEnabled(bool value) async {
    if (value == state) return;
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }
}

final quickTallyModeProvider = NotifierProvider<QuickTallyModeController, bool>(
  QuickTallyModeController.new,
);
