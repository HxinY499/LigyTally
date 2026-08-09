import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记住每种收支类型下「上次选中的分类 id」，新建账单时预选，减少翻找。
///
/// 不落数据库（避免动 schema 与备份格式），仅本地 SharedPreferences 缓存。
class LastCategoryController extends Notifier<Map<int, String>> {
  static const _prefix = 'last_category_';

  @override
  Map<int, String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <int, String>{};
    for (final kind in const [0, 1]) {
      final value = prefs.getString('$_prefix$kind');
      if (value != null && value.isNotEmpty) result[kind] = value;
    }
    if (result.isNotEmpty) state = result;
  }

  String? forKind(int kind) => state[kind];

  Future<void> remember(int kind, String categoryId) async {
    state = {...state, kind: categoryId};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$kind', categoryId);
  }
}

final lastCategoryProvider =
    NotifierProvider<LastCategoryController, Map<int, String>>(
      LastCategoryController.new,
    );
