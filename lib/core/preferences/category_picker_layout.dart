import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记账页分类选择的展示布局。
///
/// [list] 一级分类纵向列表，二级分类在所属一级下方原地展开；
/// [grid] 一级分类 4 列网格，二级分类面板插入在被展开项所在行的下方。
enum CategoryPickerLayout { list, grid }

const _prefsKey = 'category_picker_layout';

/// 分类选择布局偏好，SharedPreferences 持久化。
///
/// 读路径：启动时先给默认值（list），异步加载后覆盖——
/// 不让 UI 去 await 一次读盘（与 update 模块的写法一致）。
class CategoryPickerLayoutController extends Notifier<CategoryPickerLayout> {
  @override
  CategoryPickerLayout build() {
    _load();
    return CategoryPickerLayout.list;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefsKey);
    if (value == CategoryPickerLayout.grid.name) {
      state = CategoryPickerLayout.grid;
    }
  }

  Future<void> setLayout(CategoryPickerLayout layout) async {
    state = layout;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, layout.name);
  }
}

final categoryPickerLayoutProvider =
    NotifierProvider<CategoryPickerLayoutController, CategoryPickerLayout>(
      CategoryPickerLayoutController.new,
    );
