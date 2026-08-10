import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面图标风格：黑底白字（品牌默认）或白底黑字。
///
/// Android 侧通过两个 `activity-alias`（.LauncherDark / .LauncherLight）
/// 承载不同的 `<icon>` 属性，运行时用 PackageManager 的
/// setComponentEnabledSetting 在两者之间切换。切换后桌面上的图标由 launcher
/// 刷新，通常需要几秒；本 app 内的 UI 立刻反映选择结果。
enum AppIconStyle {
  dark('dark'),
  light('light');

  const AppIconStyle(this.key);
  final String key;

  static AppIconStyle fromKey(String? key) => switch (key) {
    'light' => AppIconStyle.light,
    _ => AppIconStyle.dark,
  };
}

const _prefsKey = 'app_icon_style';
const _channel = MethodChannel('com.ligy.ligy_tally/app_icon');

class AppIconController extends Notifier<AppIconStyle> {
  @override
  AppIconStyle build() {
    _load();
    return AppIconStyle.dark;
  }

  /// 先读 SharedPreferences 让 UI 立刻显示上次的选择，再向原生对齐一次。
  ///
  /// 原生优先级更高：如果用户在系统层重装或恢复出厂后 pref 与实际 alias
  /// 状态错开，以 PackageManager 报的实际图标为准。
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsKey);
    if (cached != null) {
      final value = AppIconStyle.fromKey(cached);
      if (value != state) state = value;
    }
    try {
      final native = await _channel.invokeMethod<String>('getCurrent');
      final value = AppIconStyle.fromKey(native);
      if (value != state) state = value;
    } on PlatformException {
      // 桌面平台或旧版本没实现该 channel——保留 pref/默认值即可
    }
  }

  /// 切换图标；原生返回成功后再持久化，失败时状态回滚。
  Future<void> setStyle(AppIconStyle value) async {
    if (value == state) return;
    final previous = state;
    state = value;
    try {
      await _channel.invokeMethod<bool>('setIcon', {'key': value.key});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, value.key);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

final appIconProvider = NotifierProvider<AppIconController, AppIconStyle>(
  AppIconController.new,
);
