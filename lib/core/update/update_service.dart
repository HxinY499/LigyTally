import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version.dart';

/// 线上可用的新版本信息。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.apkUrl,
    required this.apkName,
    required this.apkSize,
    this.sha256Url,
    this.releaseNotes,
  });

  final AppVersion version;
  final String tagName;
  final String apkUrl;
  final String apkName;
  final int apkSize;

  /// Release 里附带的 `.sha256` 校验文件地址，用于下载后验完整性。
  final String? sha256Url;
  final String? releaseNotes;
}

/// 下载阶段。
enum DownloadStage { downloading, verifying, done }

/// 下载进度快照。
class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    required this.stage,
  });

  final int received;
  final int total;
  final DownloadStage stage;

  /// total 为 0（服务端没给 Content-Length）时返回 null，
  /// UI 据此显示不确定进度条而不是假的 0%。
  double? get fraction {
    if (total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }
}

/// 下载被用户取消。
class UpdateCancelledException implements Exception {
  const UpdateCancelledException();
  @override
  String toString() => '下载已取消';
}

/// 应用内更新服务。
///
/// 更新源是公开仓库 HxinY499/LigyTally-Releases 的 latest release。
/// 设计原则：
/// - 检查失败一律静默（无网络、限流、格式变化都不该打扰记账）
/// - 下载完成后必须校验 SHA-256，避免装上损坏的包
/// - 安装动作交给系统安装器，本应用不静默安装
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _channel = MethodChannel('com.ligy.ligy_tally/app_update');

  static const _latestReleaseApi =
      'https://api.github.com/repos/HxinY499/LigyTally-Releases/releases/latest';

  /// 记录用户选择「忽略」的版本号，之后不再为该版本提示。
  static const _prefsIgnoredVersion = 'update.ignored_version';

  /// 读取当前安装的版本号（原生 PackageInfo，避免引入 package_info_plus）。
  Future<AppVersion?> currentVersion() async {
    try {
      final info = await _channel.invokeMapMethod<String, Object?>(
        'getVersionInfo',
      );
      return AppVersion.tryParse(info?['versionName'] as String?);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // 非 Android 平台（如桌面调试）没有这个 channel
      return null;
    }
  }

  /// 查询是否有新版本。
  ///
  /// 返回 null 表示「不需要提示」，涵盖：已是最新、网络失败、
  /// 接口限流、响应格式不认识、用户已忽略该版本。
  Future<UpdateInfo?> checkForUpdate() async {
    final current = await currentVersion();
    if (current == null) return null;

    final UpdateInfo? latest;
    try {
      latest = await _fetchLatestRelease();
    } catch (_) {
      // 静默失败：更新检查不该影响正常使用
      return null;
    }
    if (latest == null) return null;

    if (!latest.version.isNewerThan(current)) return null;

    // 用户忽略过这个版本
    final prefs = await SharedPreferences.getInstance();
    final ignored = prefs.getString(_prefsIgnoredVersion);
    if (ignored != null && ignored == latest.version.toString()) {
      return null;
    }

    return latest;
  }

  Future<UpdateInfo?> _fetchLatestRelease() async {
    final response = await _client
        .get(
          Uri.parse(_latestReleaseApi),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) return null;

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, Object?>) return null;

    final version = AppVersion.tryParse(body['tag_name'] as String?);
    if (version == null) return null;

    final assets = body['assets'];
    if (assets is! List) return null;

    Map<String, Object?>? apkAsset;
    String? sha256Url;
    for (final asset in assets) {
      if (asset is! Map<String, Object?>) continue;
      final name = asset['name'] as String?;
      if (name == null) continue;
      if (name.endsWith('.apk')) {
        apkAsset = asset;
      } else if (name.endsWith('.apk.sha256')) {
        sha256Url = asset['browser_download_url'] as String?;
      }
    }
    if (apkAsset == null) return null;

    final apkUrl = apkAsset['browser_download_url'] as String?;
    if (apkUrl == null) return null;

    return UpdateInfo(
      version: version,
      tagName: body['tag_name'] as String? ?? version.toString(),
      apkUrl: apkUrl,
      apkName: apkAsset['name'] as String? ?? 'LigyTally-$version.apk',
      apkSize: (apkAsset['size'] as num?)?.toInt() ?? 0,
      sha256Url: sha256Url,
      releaseNotes: body['body'] as String?,
    );
  }

  /// 记住用户忽略的版本。
  Future<void> ignoreVersion(AppVersion version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsIgnoredVersion, version.toString());
  }

  /// 下载 APK 并校验完整性，返回本地文件路径。
  ///
  /// [onProgress] 会被频繁调用，UI 侧需自行节流。
  /// [cancelled] 返回 true 时中止下载并清理临时文件。
  Future<File> downloadApk(
    UpdateInfo info, {
    required void Function(DownloadProgress) onProgress,
    bool Function()? cancelled,
  }) async {
    final dir = await _updateDir();
    final target = File(p.join(dir.path, info.apkName));
    // 边下边写到 .part，只有校验通过才改名为正式文件，
    // 避免中断留下的半包被当成可安装的包。
    final part = File('${target.path}.part');

    // 已存在且校验通过的包直接复用，省一次 57MB 下载
    if (await target.exists()) {
      final expected = await _fetchExpectedSha256(info);
      if (expected == null || await _verify(target, expected)) {
        onProgress(
          DownloadProgress(
            received: await target.length(),
            total: await target.length(),
            stage: DownloadStage.done,
          ),
        );
        return target;
      }
      await target.delete();
    }

    if (await part.exists()) await part.delete();

    final request = http.Request('GET', Uri.parse(info.apkUrl));
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('下载失败：HTTP ${response.statusCode}');
    }

    final total = response.contentLength ?? info.apkSize;
    var received = 0;
    final sink = part.openWrite();

    try {
      await for (final chunk in response.stream) {
        if (cancelled?.call() ?? false) {
          throw const UpdateCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(
          DownloadProgress(
            received: received,
            total: total,
            stage: DownloadStage.downloading,
          ),
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // 校验完整性
    onProgress(
      DownloadProgress(
        received: received,
        total: total,
        stage: DownloadStage.verifying,
      ),
    );
    final expected = await _fetchExpectedSha256(info);
    if (expected != null && !await _verify(part, expected)) {
      await part.delete();
      throw const FileSystemException('安装包校验失败，可能下载已损坏');
    }

    if (await target.exists()) await target.delete();
    await part.rename(target.path);

    onProgress(
      DownloadProgress(
        received: received,
        total: total,
        stage: DownloadStage.done,
      ),
    );
    return target;
  }

  /// 读取 Release 附带的 `.sha256` 文件内容。
  /// 拿不到就返回 null——此时跳过校验而不是拒绝安装，
  /// 因为老版本 Release 可能没上传校验文件。
  Future<String?> _fetchExpectedSha256(UpdateInfo info) async {
    final url = info.sha256Url;
    if (url == null) return null;
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      // 文件格式是 `<hash>  <filename>`
      final first = response.body.trim().split(RegExp(r'\s+')).firstOrNull;
      if (first == null || first.length != 64) return null;
      return first.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _verify(File file, String expectedSha256) async {
    final digest = await file.openRead().transform(sha256).first;
    return digest.toString().toLowerCase() == expectedSha256;
  }

  /// 缓存目录下的 updates/，与 FileProvider 的 update_provider_paths.xml 对应。
  Future<Directory> _updateDir() async {
    final cache = await getTemporaryDirectory();
    final dir = Directory(p.join(cache.path, 'updates'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Android 8+ 需要「安装未知应用」授权才能拉起安装器。
  Future<bool> canInstallPackages() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 跳转到系统的「安装未知应用」设置页。
  Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallPermissionSettings');
    } on PlatformException {
      // 打不开设置页也无需报错，用户可手动去系统设置
    } on MissingPluginException {
      // 忽略
    }
  }

  /// 交给系统安装器。用户在系统弹窗里确认后才会真正安装。
  Future<void> installApk(File apk) async {
    await _channel.invokeMethod<void>('installApk', {'path': apk.path});
  }

  /// 清理历史遗留的安装包与半包，避免缓存长期占几百 MB。
  Future<void> cleanupOldApks({String? keepName}) async {
    try {
      final dir = await _updateDir();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (keepName != null && name == keepName) continue;
        if (name.endsWith('.apk') || name.endsWith('.part')) {
          await entity.delete();
        }
      }
    } catch (_) {
      // 清理失败无所谓
    }
  }

  void dispose() => _client.close();
}
