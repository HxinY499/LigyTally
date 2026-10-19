import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// DeepSeek API Key 的唯一落盘入口。
///
/// 走 Android Keystore（flutter_secure_storage 默认 AES-GCM + RSA 包裹），
/// 不写 SharedPreferences、不进备份、不打日志。Key 只在请求时作为
/// Bearer token 直接发给 DeepSeek，不经过本应用服务器。
class DeepSeekKeyStore {
  DeepSeekKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'deepseek_api_key_v1';

  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: _storageKey);

  Future<void> write(String value) =>
      _storage.write(key: _storageKey, value: value);

  Future<void> clear() => _storage.delete(key: _storageKey);
}
