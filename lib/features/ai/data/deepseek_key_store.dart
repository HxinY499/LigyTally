import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/ai_platform.dart';

/// 各平台 API Key 的唯一落盘入口。
///
/// 走 Android Keystore（flutter_secure_storage 默认 AES-GCM + RSA 包裹），
/// 不写 SharedPreferences、不进备份、不打日志。Key 只在请求时作为
/// Bearer token 直接发给对应官方平台，不经过本应用服务器。
///
/// DeepSeek 沿用原来的存储键，已经配过的 Key 不会丢。
class DeepSeekKeyStore {
  DeepSeekKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const storageKeys = <AiPlatform, String>{
    AiPlatform.deepseek: 'deepseek_api_key_v1',
    AiPlatform.glm: 'glm_api_key_v1',
    AiPlatform.kimi: 'kimi_api_key_v1',
  };

  final FlutterSecureStorage _storage;

  Future<String?> read() => readFor(AiPlatform.deepseek);

  Future<void> write(String value) => writeFor(AiPlatform.deepseek, value);

  Future<void> clear() => clearFor(AiPlatform.deepseek);

  Future<String?> readFor(AiPlatform platform) =>
      _storage.read(key: storageKeys[platform]!);

  Future<void> writeFor(AiPlatform platform, String value) =>
      _storage.write(key: storageKeys[platform]!, value: value);

  Future<void> clearFor(AiPlatform platform) =>
      _storage.delete(key: storageKeys[platform]!);
}
