import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外观偏好：深浅皮肤的取值来源。
///
/// [system] 跟随系统，[light] / [dark] 由用户手动锁定。
/// 默认 [system]——记账是「随手掏出手机」的场景，跟随系统才能在夜里
/// 自动变暗，而不是让用户想起来去设置里翻一下。
enum AppThemeMode {
  system('跟随系统'),
  light('浅色'),
  dark('深色');

  const AppThemeMode(this.label);

  final String label;

  ThemeMode get materialMode => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
}

const _prefsKey = 'app_theme_mode';

/// 外观偏好，SharedPreferences 持久化。
///
/// 读路径：启动时先给默认值（system），异步加载后覆盖——
/// 不让 UI 去 await 一次读盘（与其它偏好一致）。
///
/// 代价是手动锁定深色的用户冷启动时会看到一帧浅色再翻深色。
/// 要消掉这一帧只能在 `runApp` 前 await 读盘，那会把启动白屏拉长，
/// 权衡后选择前者。
class AppThemeModeController extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    _load();
    return AppThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefsKey);
    final loaded = AppThemeMode.values.where((mode) => mode.name == value);
    if (loaded.isNotEmpty) state = loaded.first;
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}

final appThemeModeProvider =
    NotifierProvider<AppThemeModeController, AppThemeMode>(
      AppThemeModeController.new,
    );
