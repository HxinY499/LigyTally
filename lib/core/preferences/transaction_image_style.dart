import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记一笔页里账单图片的展示方式。
///
/// [backdrop] 整页背板：高斯模糊 + 向下渐隐，图只贡献色调与氛围，
/// 模糊强度另由 `backdropBlurProvider` 控制；
/// [polaroid] 拍立得贴纸：清晰的小照片叠成一摞贴在分类区上方，可点开管理。
///
/// 两者互斥而不是叠加：同一张图在一屏里出现两次，清晰那份会把模糊那份
/// 显成脏底，视觉上像没处理干净。
enum TransactionImageStyle { backdrop, polaroid }

const _prefsKey = 'transaction_image_style';

/// 账单图片展示方式偏好，SharedPreferences 持久化。
///
/// 默认 [TransactionImageStyle.backdrop]：这是本页原本就有的表现，
/// 升级上来的用户不该因为多了个开关就换一副样子。
/// 读法与其它偏好一致：先返回默认值，异步加载后覆盖，不让 UI 去 await 读盘。
class TransactionImageStyleController extends Notifier<TransactionImageStyle> {
  @override
  TransactionImageStyle build() {
    _load();
    return TransactionImageStyle.backdrop;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefsKey);
    if (value == TransactionImageStyle.polaroid.name) {
      state = TransactionImageStyle.polaroid;
    }
  }

  Future<void> setStyle(TransactionImageStyle style) async {
    if (style == state) return;
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, style.name);
  }
}

final transactionImageStyleProvider =
    NotifierProvider<TransactionImageStyleController, TransactionImageStyle>(
      TransactionImageStyleController.new,
    );
