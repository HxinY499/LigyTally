import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  final service = UpdateService();
  ref.onDispose(service.dispose);
  return service;
});

/// 更新流程的阶段。
enum UpdatePhase {
  /// 没有可用更新，或还没检查完—— UI 不显示任何东西
  idle,

  /// 发现新版本，等用户决定
  available,

  /// 正在下载
  downloading,

  /// 下载完成正在校验 SHA-256
  verifying,

  /// 已就绪，等待系统安装器
  readyToInstall,

  /// 出错了
  failed,
}

@immutable
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.info,
    this.progress,
    this.message,
    this.autoPrompt = false,
  });

  final UpdatePhase phase;
  final UpdateInfo? info;
  final DownloadProgress? progress;

  /// 失败原因或提示文案
  final String? message;

  /// 是否由启动自动检查带出来的「有更新」。
  /// 为 true 时才弹全局提示；设置页里用户自己点「检查更新」已经能在
  /// 关于卡片上看到结果，再弹一层是重复打扰。
  final bool autoPrompt;

  bool get isBusy =>
      phase == UpdatePhase.downloading || phase == UpdatePhase.verifying;

  UpdateState copyWith({
    UpdatePhase? phase,
    UpdateInfo? info,
    DownloadProgress? progress,
    String? message,
    bool? autoPrompt,
    bool clearMessage = false,
    bool clearProgress = false,
  }) {
    return UpdateState(
      phase: phase ?? this.phase,
      info: info ?? this.info,
      progress: clearProgress ? null : (progress ?? this.progress),
      message: clearMessage ? null : (message ?? this.message),
      autoPrompt: autoPrompt ?? this.autoPrompt,
    );
  }
}

/// 手动检查要给用户看的一句话，以及它是不是一次失败。
///
/// [failed] 决定 toast 用哪个级别。这个判断必须由控制器给出而不是让 UI 去猜
/// 文案内容——「更新服务暂时不可用」和「当前已是最新版本」在 UI 眼里都只是
/// 一个字符串。
@immutable
class ManualCheckOutcome {
  const ManualCheckOutcome._(this.message, {this.failed = false});

  /// 组件已经销毁，不必提示。
  const ManualCheckOutcome._silent() : message = '', failed = false;

  final String message;
  final bool failed;

  bool get isSilent => message.isEmpty;
}

class UpdateController extends StateNotifier<UpdateState> {
  UpdateController(this._service) : super(const UpdateState());

  final UpdateService _service;
  bool _checked = false;
  bool _cancelRequested = false;

  /// 启动时调用一次。
  ///
  /// **失败静默**：用户此刻在记账，检查不到新版本不该弹任何东西。这条策略只
  /// 属于启动路径，所以判断写在这里而不是服务层——手动检查要的正好相反。
  Future<void> checkOnLaunch() async {
    if (_checked) return;
    _checked = true;

    // 清掉上次遗留的安装包，避免缓存堆积
    unawaited(_service.cleanupOldApks());

    final result = await _service.checkForUpdate();
    if (result is! UpdateAvailable || !mounted) return;
    // 手动检查已经把结果摊在设置页上了，启动检查回来时别再弹一层。
    if (state.phase != UpdatePhase.idle) return;

    state = UpdateState(
      phase: UpdatePhase.available,
      info: result.info,
      autoPrompt: true,
    );
  }

  /// 用户手动触发检查（设置页入口用）。
  ///
  /// 与启动检查有两处不同：
  /// - 不理会「忽略此版本」。忽略只关掉启动弹窗，手动检查仍应能看到这个版本。
  /// - **失败要说出来。** 用户点这一下就是在问「有没有新版本」，
  ///   把查不到答成「已是最新」是给假答案，见 [UpdateCheckResult]。
  Future<ManualCheckOutcome> checkManually() async {
    // 手动查过就不必再跑启动检查；两边同时在飞时，启动检查结束会看到
    // phase 已经不是 idle，也不会再弹全局提示。
    _checked = true;
    final result = await _service.checkForUpdate(respectIgnore: false);
    if (!mounted) return const ManualCheckOutcome._silent();

    switch (result) {
      case UpdateAvailable(:final info):
        state = UpdateState(phase: UpdatePhase.available, info: info);
        return ManualCheckOutcome._('发现新版本 v${info.version}');
      case UpdateUpToDate(:final current):
        return ManualCheckOutcome._('当前已是最新版本 (v$current)');
      case UpdateCheckFailed(:final reason):
        return ManualCheckOutcome._(_failureMessage(reason), failed: true);
    }
  }

  /// 失败提示的措辞。
  ///
  /// 三种原因分开说，因为用户能做的事不同：网络问题自己能重试，
  /// 其余两种只能等修，全都说成「请稍后重试」会让人白重试很多次。
  ///
  /// 一律**不带**本机版本号。带上就又成了「已是最新版本 (v1.6.1)」那种会被读成
  /// 结论的句子——而失败的时候恰恰没有结论，这正是原来那个 bug 的样子。
  String _failureMessage(UpdateFailure reason) {
    return switch (reason) {
      UpdateFailure.network => '检查更新失败，请确认网络后重试',
      UpdateFailure.manifest => '更新服务暂时不可用，请稍后再试',
      UpdateFailure.localVersion => '读不到当前版本号，无法检查更新',
    };
  }

  /// 用户点了「忽略此版本」。
  Future<void> ignoreCurrent() async {
    final info = state.info;
    if (info == null) return;
    await _service.ignoreVersion(info.version);
    if (!mounted) return;
    state = const UpdateState();
  }

  /// UI 侧的同步入口：立刻收起提示，忽略记录在后台写入。
  /// 不让UI 去await 一次 SharedPreferences 写盘。
  void ignoreVersionAndDismiss() {
    unawaited(ignoreCurrent());
  }

  /// 收起提示但不写入忽略记录，下次启动还会提示。
  void dismiss() {
    if (state.isBusy) return;
    state = const UpdateState();
  }

  void cancelDownload() {
    if (!state.isBusy) return;
    _cancelRequested = true;
  }

  /// 下载并拉起安装。
  Future<void> downloadAndInstall([UpdateInfo? explicit]) async {
    final info = explicit ?? state.info;
    if (info == null || state.isBusy) return;

    // 先确认有「安装未知应用」权限，否则下载完也装不上，
    // 白等57MB 才提示体验很差。
    if (!await _service.canInstallPackages()) {
      if (!mounted) return;
      state = state.copyWith(
        phase: UpdatePhase.failed,
        message: '需要允许「安装未知应用」才能更新',
      );
      await _service.openInstallPermissionSettings();
      return;
    }

    _cancelRequested = false;
    state = state.copyWith(
      phase: UpdatePhase.downloading,
      info: info,
      progress: DownloadProgress(
        received: 0,
        total: info.apkSize,
        stage: DownloadStage.downloading,
      ),
      clearMessage: true,
    );

    try {
      final file = await _service.downloadApk(
        info,
        onProgress: _onProgress,
        cancelled: () => _cancelRequested,
      );
      if (!mounted) return;

      state = state.copyWith(
        phase: UpdatePhase.readyToInstall,
        message: '正在打开安装程序',
      );
      await _service.installApk(file);
      // 其它版本的残包这时可以清掉
      unawaited(_service.cleanupOldApks(keepName: info.apkName));
    } on UpdateCancelledException {
      if (!mounted) return;
      state = UpdateState(phase: UpdatePhase.available, info: info);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        phase: UpdatePhase.failed,
        message: _friendlyError(error),
        clearProgress: true,
      );
    }
  }

  /// 下载进度回调频率很高（每个 chunk 一次），
  /// 按 1% 或阶段变化节流，避免无意义的 UI 重建。
  void _onProgress(DownloadProgress progress) {
    if (!mounted) return;
    final previous = state.progress;
    final changedStage = previous?.stage != progress.stage;
    if (!changedStage && previous != null) {
      final before = ((previous.fraction ?? 0) * 100).floor();
      final now = ((progress.fraction ?? 0) * 100).floor();
      if (before == now) return;
    }
    state = state.copyWith(
      phase: progress.stage == DownloadStage.verifying
          ? UpdatePhase.verifying
          : UpdatePhase.downloading,
      progress: progress,
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('校验失败')) return '安装包校验失败，请稍后重试';
    if (error is TimeoutException) return '网络超时，请稍后重试';
    return '更新失败，请稍后重试';
  }
}

final updateControllerProvider =
    StateNotifierProvider<UpdateController, UpdateState>((ref) {
      return UpdateController(ref.watch(updateServiceProvider));
    });
