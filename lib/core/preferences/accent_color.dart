import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_accent.dart';

const _prefsKey = 'app_accent';

/// 强调色偏好，SharedPreferences 持久化。
///
/// 读路径与 [AppThemeMode] 相同：启动先给默认蓝，异步读盘后再覆盖。
/// 不在 `runApp` 前 await，避免把启动白屏拉长。
class AppAccentController extends Notifier<AppAccent> {
  @override
  AppAccent build() {
    _load();
    return AppAccent.blue;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = AppAccent.fromName(prefs.getString(_prefsKey));
    if (loaded != state) state = loaded;
  }

  Future<void> setAccent(AppAccent accent) async {
    if (accent == state) return;
    state = accent;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, accent.name);
  }
}

final appAccentProvider = NotifierProvider<AppAccentController, AppAccent>(
  AppAccentController.new,
);
