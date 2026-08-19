import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 新建「今天」的账单时自动取当前位置。默认关闭。
///
/// 读法与其它偏好一致：先返回默认值，异步覆盖。
/// [ready] 给记账页用——必须等盘上的值回来再决定采不采，
/// 否则会按默认「关」漏掉已经打开自动定位的用户。
const _prefsKey = 'auto_location';

class AutoLocationController extends Notifier<bool> {
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

final autoLocationProvider = NotifierProvider<AutoLocationController, bool>(
  AutoLocationController.new,
);
