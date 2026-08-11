import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记账页背景图的高斯模糊半径，全局设置。
///
/// 只作用于记账页：明细列表里的行背景面积太小，跟着调没有意义，写死一档。
/// 读法与其它偏好一致：先返回默认值，异步覆盖，避免 UI 层 await 一次读盘。
const _prefsKey = 'backdrop_blur_sigma';

/// 0 是原图直出——仍然有渐隐，只是不糊。
const double kBackdropBlurMin = 0;

/// 再往上加只剩一片色，看不出还有张照片。
const double kBackdropBlurMax = 40;

const double kBackdropBlurDefault = 24;

class BackdropBlurController extends Notifier<double> {
  Timer? _saveTimer;

  @override
  double build() {
    _load();
    return kBackdropBlurDefault;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_prefsKey);
    if (value == null) return;
    final clamped = value.clamp(kBackdropBlurMin, kBackdropBlurMax);
    if (clamped != state) state = clamped;
  }

  /// 值立刻生效，落盘攒一下再写。
  ///
  /// 滑杆是边拖边改的，一次拖动会调到这里十几次，每一档都过一趟
  /// platform channel 没有必要。定时器闭包里带着要写的值而不是回头读
  /// [state]，这样即使 provider 先一步销毁，最后一次写也还是对的。
  void setSigma(double value) {
    final next = value.clamp(kBackdropBlurMin, kBackdropBlurMax);
    if (next == state) return;
    state = next;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () => _persist(next));
  }

  Future<void> _persist(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsKey, value);
  }
}

final backdropBlurProvider = NotifierProvider<BackdropBlurController, double>(
  BackdropBlurController.new,
);
