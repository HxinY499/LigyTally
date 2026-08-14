import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_accent.dart';

const _prefsKey = 'app_accent';

/// 强调色偏好，SharedPreferences 持久化。
///
/// 读路径与 [AppThemeMode] 相同：启动先给默认蓝，异步读盘后再覆盖。
/// 不在 `runApp` 前 await，避免把启动白屏拉长。
class AppAccentController extends Notifier<AccentChoice> {
  @override
  AccentChoice build() {
    _load();
    return AccentChoice.initial;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = AccentChoice.decode(prefs.getString(_prefsKey));
    if (loaded != state) state = loaded;
  }

  /// 只改内存里的选中值，不落盘。
  ///
  /// 给色相 / 浓淡滑杆的拖动过程用：一次拖动会产生上百个中间值，每个都写一次
  /// 偏好纯属拿磁盘当画布。松手时再调 [setAccent] 落最终值。
  void previewAccent(AccentChoice accent) {
    if (accent != state) state = accent;
  }

  Future<void> setAccent(AccentChoice accent) async {
    // 不能在这里对 state 做提前返回：滑杆松手时 state 已经被 [previewAccent]
    // 改成最终值了，比一次就直接不落盘。
    state = accent;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, accent.encode());
  }
}

final appAccentProvider = NotifierProvider<AppAccentController, AccentChoice>(
  AppAccentController.new,
);
