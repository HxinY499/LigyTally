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

/// 安装包在临时目录下的子目录名。
///
/// 与 `update_provider_paths.xml` 里 FileProvider 的声明一一对应；占用空间
/// 统计也要认这个目录才能把几十 MB 的残包算成可清理缓存。
const kUpdateCacheDirName = 'updates';

/// 线上可用的新版本信息。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.apkUrl,
    required this.apkName,
    required this.apkSize,
    this.sha256,
    this.releaseNotes,
  });

  final AppVersion version;
  final String tagName;
  final String apkUrl;
  final String apkName;
  final int apkSize;

  /// latest.json 里的 SHA-256 十六进制摘要，下载后用来验完整性。
  final String? sha256;
  final String? releaseNotes;
}

/// 一次更新检查的结论。
///
/// ## 为什么不是 `UpdateInfo?`
///
/// 这个方法原来返回可空的 [UpdateInfo]，`null` 同时表示四件事：已是最新、
/// 网络失败、清单格式不认识、读不到本机版本号。
///
/// 对**启动自动检查**来说这四种确实等价（都不该打扰正在记账的人），
/// 所以那样写了很久也没出问题。但**手动检查**的语义正好相反：用户点那一下就是
/// 在问「有没有新版本」，把「我没查到」答成「没有新版本」是给了一个假答案，
/// 而且提示里还带着旧版本号——「当前已是最新版本 (v1.6.1)」在 1.7.0 已发布时
/// 自相矛盾，用户看不出这其实是一次失败。
///
/// 所以「要不要打扰用户」这个判断从服务层挪到了调用点：这里只报事实。
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// 线上有更新，且没有被用户忽略。
final class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.info);

  final UpdateInfo info;
}

/// 确实比较过了，本机就是最新。
///
/// 也涵盖「线上有新版本但被用户忽略了」这一支：对启动检查来说两者后果相同
/// （都不弹），而手动检查传 `respectIgnore: false`，永远走不到那里。
final class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate(this.current);

  final AppVersion current;
}

/// 没查出结论。**不等于**没有新版本。
///
/// 刻意不带本机版本号：一旦提示里出现版本号，那句话就会被读成一个结论，
/// 而失败的时候恰恰没有结论。
final class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(this.reason);

  final UpdateFailure reason;
}

/// 检查失败的原因。分这三档是因为用户能做的事不同：网络问题自己能重试，
/// 其余两种只能等作者修。
enum UpdateFailure {
  /// 请求发不出去、连不上或超时。
  network,

  /// 服务器答了，但状态码不是 200，或清单内容不认识。
  manifest,

  /// 读不到本机版本号，没法比较。
  localVersion,
}

/// 清单本身有问题（非 200、或格式不认识），区别于连不上服务器。
class _ManifestException implements Exception {
  const _ManifestException(this.detail);

  final String detail;

  @override
  String toString() => '清单不可用：$detail';
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

/// OSS 上固定的更新清单地址。应用只硬编码这一条，APK 路径以清单为准。
const kUpdateManifestUrl =
    'https://ligy-tally-releases.oss-cn-hangzhou.aliyuncs.com/latest.json';

/// 解析 OSS 上的 `latest.json`。字段不对或校验值格式错误时返回 null，
/// 调用方据此静默跳过，不打扰记账。
UpdateInfo? parseUpdateManifest(String source) {
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final body = Map<String, dynamic>.from(decoded);

  final version = AppVersion.tryParse(body['tag_name'] as String?);
  if (version == null) return null;

  final apkUrl = body['apk_url'] as String?;
  if (apkUrl == null || apkUrl.isEmpty) return null;
  final uri = Uri.tryParse(apkUrl);
  if (uri == null || uri.scheme != 'https') return null;

  final apkName = body['apk_name'] as String? ?? 'LigyTally-$version.apk';
  if (!apkName.endsWith('.apk')) return null;

  String? sha256;
  final rawSha = body['sha256'] as String?;
  if (rawSha != null && rawSha.trim().isNotEmpty) {
    final hex = rawSha.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return null;
    sha256 = hex;
  }

  return UpdateInfo(
    version: version,
    tagName: body['tag_name'] as String? ?? 'v$version',
    apkUrl: apkUrl,
    apkName: apkName,
    apkSize: (body['apk_size'] as num?)?.toInt() ?? 0,
    sha256: sha256,
    releaseNotes: body['body'] as String?,
  );
}

/// 应用内更新服务。
///
/// 更新源是阿里云 OSS 桶 `ligy-tally-releases` 上的 [kUpdateManifestUrl]。
/// 设计原则：
/// - 检查失败一律静默（无网络、格式变化都不该打扰记账）
/// - 下载完成后必须校验 SHA-256，避免装上损坏的包
/// - 安装动作交给系统安装器，本应用不静默安装
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _channel = MethodChannel('com.ligy.ligy_tally/app_update');

  /// 记录用户选择「忽略」的版本号，之后启动时不再为该版本弹窗。
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

  /// 查询是否有比当前安装更新的版本。
  ///
  /// 结果是 [UpdateCheckResult] 而不是可空的 [UpdateInfo]——「没查到」和
  /// 「没有新版本」必须能被调用点分开，理由见 [UpdateCheckResult] 的文档。
  ///
  /// 本方法**不抛异常**：网络与解析失败都收敛成 [UpdateCheckFailed]。
  /// 检查更新不该让调用点承担 try/catch。
  ///
  /// [respectIgnore] 只给启动自动检查用。用户点「忽略」的意思是
  /// 「这个版本别再弹启动提示」，不是「这个版本不存在」——
  /// 设置页手动检查必须传 false，否则忽略后会误报已是最新。
  Future<UpdateCheckResult> checkForUpdate({bool respectIgnore = true}) async {
    final current = await currentVersion();
    if (current == null) {
      return const UpdateCheckFailed(UpdateFailure.localVersion);
    }

    final UpdateInfo latest;
    try {
      latest = await _fetchLatestRelease();
    } on _ManifestException {
      return const UpdateCheckFailed(UpdateFailure.manifest);
    } catch (_) {
      // 连不上、DNS 失败、超时、TLS 出错，对用户是同一件事：网络没通。
      return const UpdateCheckFailed(UpdateFailure.network);
    }

    if (!latest.version.isNewerThan(current)) return UpdateUpToDate(current);

    if (respectIgnore) {
      final prefs = await SharedPreferences.getInstance();
      final ignored = prefs.getString(_prefsIgnoredVersion);
      if (ignored != null && ignored == latest.version.toString()) {
        return UpdateUpToDate(current);
      }
    }

    return UpdateAvailable(latest);
  }

  /// 抓取并解析清单。
  ///
  /// 网络层的异常原样往上抛（由调用点归到 [UpdateFailure.network]）；
  /// 「服务器答了但答的不对」单独抛 [_ManifestException]——那两种情况用户能做
  /// 的事不一样，混成一个 `return null` 就分不出来了。
  Future<UpdateInfo> _fetchLatestRelease() async {
    final response = await _client
        .get(Uri.parse(kUpdateManifestUrl))
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw _ManifestException('HTTP ${response.statusCode}');
    }
    final info = parseUpdateManifest(utf8.decode(response.bodyBytes));
    if (info == null) throw const _ManifestException('内容不是认识的清单格式');
    return info;
  }

  /// 记住用户忽略的版本。只影响启动自动提示，不影响手动检查。
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

    // 已存在且校验通过的包直接复用，省一次下载
    if (await target.exists()) {
      final expected = _expectedSha256(info);
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
    final expected = _expectedSha256(info);
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

  /// 清单里带了合法 SHA-256 就必须用；没有则跳过校验而不是拒绝安装。
  String? _expectedSha256(UpdateInfo info) => info.sha256;

  Future<bool> _verify(File file, String expectedSha256) async {
    final digest = await file.openRead().transform(sha256).first;
    return digest.toString().toLowerCase() == expectedSha256;
  }

  /// 缓存目录下的 updates/，与 FileProvider 的 update_provider_paths.xml 对应。
  Future<Directory> _updateDir() async {
    final cache = await getTemporaryDirectory();
    final dir = Directory(p.join(cache.path, kUpdateCacheDirName));
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
