import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_widgets.dart';
import 'update_available_sheet.dart';
import 'update_controller.dart';
import 'update_service.dart';

/// 应用内更新的提示层。
///
/// 包在页面外层，负责两件事：
/// 1. 启动自动检查发现新版本时，从下方弹出浮层（版本 + 更新说明）
/// 2. 下载期间在顶部显示一条常驻细进度条
///
/// 用可下滑关掉的底部浮层，而不是 AlertDialog：更新不是必须马上处理
/// 的事，拦住用户记账才是真的烦。下滑或点遮罩只收起，不写入「忽略」。
class UpdateNotificationLayer extends ConsumerStatefulWidget {
  const UpdateNotificationLayer({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateNotificationLayer> createState() =>
      _UpdateNotificationLayerState();
}

class _UpdateNotificationLayerState
    extends ConsumerState<UpdateNotificationLayer> {
  /// 记录已经为哪个版本弹过浮层，避免同一次会话里重复打开。
  String? _promptedVersion;

  @override
  void initState() {
    super.initState();
    // 等首帧渲染完再查，不拖慢启动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(updateControllerProvider.notifier).checkOnLaunch();
    });
  }

  void _showAvailableSheet(UpdateInfo info) {
    final version = info.version.toString();
    if (_promptedVersion == version) return;
    _promptedVersion = version;
    unawaited(_presentAvailableSheet(info));
  }

  Future<void> _presentAvailableSheet(UpdateInfo info) async {
    final action = await showUpdateAvailableSheet(context, info);
    if (!mounted) return;
    final controller = ref.read(updateControllerProvider.notifier);
    switch (action) {
      case UpdateSheetAction.update:
        unawaited(controller.downloadAndInstall());
      case UpdateSheetAction.ignore:
        controller.ignoreVersionAndDismiss();
      case null:
        break;
    }
  }

  void _showMessageToast(String message) {
    showAppToast(context, message: message, level: AppToastLevel.error);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateControllerProvider);

    // 状态变化时触发提示。用 listen 而不是在 build 里直接调，
    // 避免 build 期间操作 overlay。
    ref.listen<UpdateState>(updateControllerProvider, (previous, next) {
      if (next.phase == UpdatePhase.available &&
          next.autoPrompt &&
          next.info != null) {
        _showAvailableSheet(next.info!);
      } else if (next.phase == UpdatePhase.failed && next.message != null) {
        _showMessageToast(next.message!);
      }
    });

    // 进度条占据真实空间把内容往下推，而不是浮在上面盖住页面标题。
    // 外层套 Scaffold 以提供 Material 背景与 MediaQuery 边距，
    // 否则裸 Column 会让内部页面失去背景色。
    // 下载进度仍放顶部：底部有导航栏和记账悬浮按钮，细条压在那里
    // 会挡操作；发现新版本的说明则走可关掉的底部浮层。
    return Scaffold(
      body: Column(
        children: [
          if (state.isBusy) _UpdateProgressBar(state: state),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

/// 顶部细进度条 + 一行状态文字，不遮挡任何可点击区域。
class _UpdateProgressBar extends ConsumerWidget {
  const _UpdateProgressBar({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(updateControllerProvider.notifier);
    final colors = context.colors;
    final info = state.info;
    if (info == null) return const SizedBox.shrink();

    final fraction = state.progress?.fraction;
    final isVerifying = state.phase == UpdatePhase.verifying;

    final label = isVerifying
        ? '正在校验安装包…'
        : fraction != null
        ? '正在下载 v${info.version} · ${(fraction * 100).toStringAsFixed(0)}%'
        : '正在下载 v${info.version}…';

    return Material(
      color: colors.primarySoft,
      // 顶部留出状态栏高度；不用 SafeArea 是因为内部页面
      // 自己也有 SafeArea，叠加会多留一次边距。
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: colors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isVerifying)
                    TextButton(
                      onPressed: controller.cancelDownload,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('取消'),
                    ),
                ],
              ),
            ),
            // 细进度条压在整条的下沿，高度 3，不抢视觉
            SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                value: isVerifying ? null : fraction,
                color: colors.primary,
                backgroundColor: colors.primary.withValues(alpha: 0.22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
