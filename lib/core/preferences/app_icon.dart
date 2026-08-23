import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面图标风格，四款可选。
///
/// Android 侧每款对应一个 `activity-alias`（.LauncherDark / .LauncherBlue /
/// .LauncherLight / .LauncherTint），各自带不同的 `<icon>` 属性；运行时用
/// PackageManager 的 setComponentEnabledSetting 在它们之间切换。切换后桌面上的
/// 图标由 launcher 刷新，通常需要几秒；本 app 内的 UI 立刻反映选择结果。
///
/// key 同时是三处资源的命名依据，改动需三处同步：
///   - `assets/branding/app-icon-<key>.png`（应用内预览图）
///   - `android/.../mipmap-*/ic_launcher[_<key>].png`（dark 落在无后缀上）
///   - `.Launcher<Key>` alias 名
enum AppIconStyle {
  /// 黑底白标。默认，也是旧版本 `dark` 的原义。
  dark('dark', '墨黑'),

  /// 蓝底白标。品牌主色。
  blue('blue', '品牌蓝'),

  /// 白底黑标。旧版本 `light` 的原义。
  light('light', '素白'),

  /// 白底蓝标。
  tint('tint', '浅蓝');

  const AppIconStyle(this.key, this.label);

  final String key;

  /// 选择器里的中文名。图标本身已说明样式，标签只用于辅助确认。
  final String label;

  /// 应用内预览图路径。与安卓 mipmap 同源。
  String get asset => 'assets/branding/app-icon-$key.png';

  /// 未知或缺失的 key 一律落回默认值，不抛异常 ——
  /// 降级到 dark 只是图标不符预期，抛异常会让整个设置页打不开。
  static AppIconStyle fromKey(String? key) => values.firstWhere(
    (style) => style.key == key,
    orElse: () => AppIconStyle.dark,
  );
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
