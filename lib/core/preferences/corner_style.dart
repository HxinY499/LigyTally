import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_radius.dart';

const _prefsKey = 'app_corner_style';

/// 圆角档位偏好，SharedPreferences 持久化。
///
/// 读路径与 [AppAccentController] 相同：启动先给标准档，异步读盘后再覆盖。
/// 不在 `runApp` 前 await，避免把启动白屏拉长。
class AppCornerStyleController extends Notifier<AppCornerStyle> {
  @override
  AppCornerStyle build() {
    _load();
    return AppCornerStyle.fallback;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = AppCornerStyle.decode(prefs.getString(_prefsKey));
    if (loaded != state) state = loaded;
  }

  Future<void> setStyle(AppCornerStyle style) async {
    if (style == state) return;
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
  }
}

final appCornerStyleProvider =
    NotifierProvider<AppCornerStyleController, AppCornerStyle>(
      AppCornerStyleController.new,
    );
