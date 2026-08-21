import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 统计页「不计入支出」的分类。
///
/// 只影响统计口径，不改首页的本月支出，也不改账单本身。
/// id 可以是一级或二级：一级会连同它的二级一起去掉。
/// [ready] 为 false 时还没读完本地缓存——页面应继续显示骨架，
/// 避免先闪出全量数字再跳到排除后的数字。
class StatsExclusion {
  const StatsExclusion({required this.ids, required this.ready});

  static const loading = StatsExclusion(ids: {}, ready: false);

  final Set<String> ids;
  final bool ready;
}

const _prefsKey = 'stats_excluded_expense_roots';

class StatsExclusionController extends Notifier<StatsExclusion> {
  @override
  StatsExclusion build() {
    _load();
    return StatsExclusion.loading;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsKey) ?? const <String>[];
      state = StatsExclusion(ids: Set<String>.unmodifiable(list), ready: true);
    } catch (_) {
      state = const StatsExclusion(ids: {}, ready: true);
    }
  }

  Future<void> setIds(Set<String> ids) async {
    final next = Set<String>.unmodifiable(ids);
    if (state.ready && setEquals(state.ids, next)) return;
    state = StatsExclusion(ids: next, ready: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, next.toList());
  }
}

final statsExclusionProvider =
    NotifierProvider<StatsExclusionController, StatsExclusion>(
      StatsExclusionController.new,
    );
