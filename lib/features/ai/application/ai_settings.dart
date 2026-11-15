import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/deepseek_key_store.dart';
import 'ai_platform.dart';

export 'ai_platform.dart';

/// DeepSeek 思考档位。
///
/// Chat Completions 真正生效的是 `low` / `high` / `max`，外加把思考关掉。
/// 默认 `high`，和官方未传 `reasoning_effort` 时的行为一致。
enum AiReasoningEffort {
  off('off', '关'),
  low('low', '低'),
  high('high', '高'),
  max('max', '最高');

  const AiReasoningEffort(this.wireName, this.label);

  final String wireName;
  final String label;

  static const fallback = AiReasoningEffort.high;

  static AiReasoningEffort fromWire(String? value) {
    for (final effort in values) {
      if (effort.wireName == value) return effort;
    }
    return fallback;
  }
}

/// 写进 DeepSeek 请求的思考参数。
Map<String, Object?> thinkingRequestExtra(AiReasoningEffort effort) {
  if (effort == AiReasoningEffort.off) {
    return const {
      'thinking': {'type': 'disabled'},
    };
  }
  return {
    'thinking': const {'type': 'enabled'},
    'reasoning_effort': effort.wireName,
  };
}

/// 按模型所属平台写思考参数。
///
/// DeepSeek 可以关掉。智谱 GLM-5.3 和 Kimi K3 不能关，传 disabled 会 400；
/// 选「关」时改成官方允许的最低强度。Kimi 只认顶层 `reasoning_effort`。
Map<String, Object?> thinkingExtraFor(String model, AiReasoningEffort effort) {
  final spec = aiModelById(model);
  if (spec == null || !spec.thinkingAlwaysOn) {
    return thinkingRequestExtra(effort);
  }
  final wire = effort == AiReasoningEffort.off
      ? AiReasoningEffort.low.wireName
      : effort.wireName;
  if (spec.platform == AiPlatform.kimi) {
    return {'reasoning_effort': wire};
  }
  return {
    'thinking': const {'type': 'enabled'},
    'reasoning_effort': wire,
  };
}

class AiSettings {
  const AiSettings({
    this.keys = const {},
    this.model = kDeepSeekDefaultModel,
    this.reasoning = AiReasoningEffort.fallback,
  });

  final Map<AiPlatform, String> keys;
  final String model;
  final AiReasoningEffort reasoning;

  bool hasKeyFor(AiPlatform platform) =>
      (keys[platform] ?? '').trim().isNotEmpty;

  bool get hasKey => AiPlatform.values.any(hasKeyFor);

  String? keyFor(AiPlatform platform) {
    final value = (keys[platform] ?? '').trim();
    return value.isEmpty ? null : value;
  }

  /// 只给设置页展示用，绝不把完整 Key 回填到输入框。
  String maskedKeyFor(AiPlatform platform) => _mask(keys[platform]);

  Set<AiPlatform> get configuredPlatforms => {
    for (final platform in AiPlatform.values)
      if (hasKeyFor(platform)) platform,
  };

  List<AiModelSpec> get availableModels =>
      modelsForConfigured(configuredPlatforms);

  AiSettings copyWith({
    Map<AiPlatform, String>? keys,
    String? model,
    AiReasoningEffort? reasoning,
  }) => AiSettings(
    keys: keys ?? this.keys,
    model: model ?? this.model,
    reasoning: reasoning ?? this.reasoning,
  );

  static String _mask(String? apiKey) {
    final value = (apiKey ?? '').trim();
    if (value.isEmpty) return '未配置';
    if (value.length <= 8) return '已配置';
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }
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
  static const _reasoningPrefsKey = 'ai_deepseek_reasoning_v1';

  @override
  Future<AiSettings> build() async {
    final store = ref.read(deepSeekKeyStoreProvider);
    final keys = <AiPlatform, String>{};
    for (final platform in AiPlatform.values) {
      final value = (await store.readFor(platform))?.trim();
      if (value != null && value.isNotEmpty) keys[platform] = value;
    }
    final prefs = await SharedPreferences.getInstance();
    final configured = keys.keys.toSet();
    final model = resolveSelectedModel(
      prefs.getString(_modelPrefsKey),
      configured,
    );
    final reasoning = AiReasoningEffort.fromWire(
      prefs.getString(_reasoningPrefsKey),
    );
    return AiSettings(keys: keys, model: model, reasoning: reasoning);
  }

  Future<void> saveKey({
    required AiPlatform platform,
    required String apiKey,
  }) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'API Key 不能为空');
    }
    final current = state.value;
    final reasoning = current?.reasoning ?? AiReasoningEffort.fallback;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(deepSeekKeyStoreProvider).writeFor(platform, trimmed);
      final keys = Map<AiPlatform, String>.from(current?.keys ?? const {});
      keys[platform] = trimmed;
      final model = resolveSelectedModel(current?.model, keys.keys.toSet());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelPrefsKey, model);
      return AiSettings(keys: keys, model: model, reasoning: reasoning);
    });
  }

  Future<void> setModel(String model) async {
    final spec = aiModelById(model);
    final current = state.value;
    if (spec == null || current == null || !current.hasKeyFor(spec.platform)) {
      throw ArgumentError.value(model, 'model', '这个模型还不可用');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelPrefsKey, model);
    state = AsyncData(current.copyWith(model: model));
  }

  Future<void> setReasoning(AiReasoningEffort effort) async {
    final current = state.value;
    if (current == null || current.reasoning == effort) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reasoningPrefsKey, effort.wireName);
    state = AsyncData(current.copyWith(reasoning: effort));
  }

  Future<void> clearKey(AiPlatform platform) async {
    final current = state.value;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(deepSeekKeyStoreProvider).clearFor(platform);
      final keys = Map<AiPlatform, String>.from(current?.keys ?? const {});
      keys.remove(platform);
      final model = resolveSelectedModel(current?.model, keys.keys.toSet());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelPrefsKey, model);
      return AiSettings(
        keys: keys,
        model: model,
        reasoning: current?.reasoning ?? AiReasoningEffort.fallback,
      );
    });
  }
}
