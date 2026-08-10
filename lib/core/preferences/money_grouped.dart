import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 金额是否用千分位分组展示（`19,042.60`），全局设置。
///
/// 默认打开。读法与其它偏好一致：先返回默认值，异步覆盖，
/// 避免 UI 层await一次读盘。
const _prefsKey = 'money_grouped';

class MoneyGroupedController extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_prefsKey);
    if (value != null && value != state) state = value;
  }

  Future<void> setGrouped(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }
}

final moneyGroupedProvider =
    NotifierProvider<MoneyGroupedController, bool>(MoneyGroupedController.new);
