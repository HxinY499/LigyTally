import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/deepseek_key_store.dart';

/// DeepSeek 当前可用的模型名。
///
/// 旧教程里的 deepseek-chat / deepseek-reasoner 已退役；这里只列官方当前
/// 文档中的模型。默认用 flash，日常查询和记账工具调用足够，延迟也低。
const kDeepSeekModels = <String>['deepseek-flash', 'deepseek-v4-pro'];

const kDeepSeekDefaultModel = 'deepseek-flash';

class AiSettings {
  const AiSettings({this.apiKey, this.model = kDeepSeekDefaultModel});

  final String? apiKey;
  final String model;

  bool get hasKey => (apiKey ?? '').trim().isNotEmpty;

  /// 只给设置页展示用，绝不把完整 Key 回填到输入框。
  String get maskedKey {
    final value = (apiKey ?? '').trim();
    if (value.isEmpty) return '未配置';
    if (value.length <= 8) return '已配置';
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }

  AiSettings copyWith({String? apiKey, String? model}) =>
      AiSettings(apiKey: apiKey ?? this.apiKey, model: model ?? this.model);
}

final deepSeekKeyStoreProvider = Provider<DeepSeekKeyStore>(
  (ref) => DeepSeekKeyStore(),
);

final aiSettingsProvider =
    AsyncNotifierProvider<AiSettingsController, AiSettings>(
      AiSettingsController.new,
    );

class AiSettingsController extends AsyncNotifier<AiSettings> {
  static const _modelPrefsKey = 'ai_deepseek_model_v1';

  @override
  Future<AiSettings> build() async {
    final key = await ref.read(deepSeekKeyStoreProvider).read();
    final prefs = await SharedPreferences.getInstance();
    final storedModel = prefs.getString(_modelPrefsKey);
    final model = kDeepSeekModels.contains(storedModel)
        ? storedModel!
        : kDeepSeekDefaultModel;
    return AiSettings(apiKey: key, model: model);
  }

  Future<void> save({required String apiKey, required String model}) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'API Key 不能为空');
    }
    if (!kDeepSeekModels.contains(model)) {
      throw ArgumentError.value(model, 'model', '不支持的 DeepSeek 模型');
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(deepSeekKeyStoreProvider).write(trimmed);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelPrefsKey, model);
      return AiSettings(apiKey: trimmed, model: model);
    });
  }

  Future<void> setModel(String model) async {
    if (!kDeepSeekModels.contains(model)) {
      throw ArgumentError.value(model, 'model', '不支持的 DeepSeek 模型');
    }
    final current = state.value;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelPrefsKey, model);
    state = AsyncData(current.copyWith(model: model));
  }

  Future<void> clearKey() async {
    final current = state.value;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(deepSeekKeyStoreProvider).clear();
      return AiSettings(
        apiKey: null,
        model: current?.model ?? kDeepSeekDefaultModel,
      );
    });
  }
}
