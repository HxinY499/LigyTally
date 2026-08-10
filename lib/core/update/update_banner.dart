import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/app_widgets.dart';
import 'update_controller.dart';
import 'update_service.dart';

/// 应用内更新的提示层。
///
/// 包在页面外层，负责两件事：
/// 1. 发现新版本时弹一条 forui toast（不是大弹窗，不打断记账）
/// 2. 下载期间在底部显示一条常驻细进度条
///
/// 刻意不用 AlertDialog：更新不是必须马上处理的事，
/// 拦住用户记账才是真的烦。
class UpdateNotificationLayer extends ConsumerStatefulWidget {
  const UpdateNotificationLayer({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateNotificationLayer> createState() =>
      _UpdateNotificationLayerState();
}

class _UpdateNotificationLayerState
    extends ConsumerState<UpdateNotificationLayer> {
  /// 记录已经为哪个版本弹过 toast，避免重复打扰
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

  void _showAvailableToast(UpdateInfo info) {
    final version = info.version.toString();
    if (_promptedVersion == version) return;
    _promptedVersion = version;

    final controller = ref.read(updateControllerProvider.notifier);
    final sizeLabel = info.apkSize > 0
        ? ' · ${(info.apkSize / 1024 / 1024).toStringAsFixed(0)}MB'
        : '';

    showAppToast(
      context,
      message: '发现新版本',
      description: 'v$version$sizeLabel',
      suffixBuilder: (context, entry) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            variant: AppButtonVariant.ghost,
            onPress: () {
              entry.dismiss();
              controller.ignoreVersionAndDismiss();
            },
            child: const Text('忽略'),
          ),
          const SizedBox(width: 4),
          AppButton(
            variant: AppButtonVariant.ghost,
            onPress: () {
              entry.dismiss();
              controller.downloadAndInstall();
            },
            child: const Text('更新'),
          ),
        ],
      ),
      duration: null, // 不自动消失：等用户主动交互
    );
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
      if (next.phase == UpdatePhase.available && next.info != null) {
        _showAvailableToast(next.info!);
      } else if (next.phase == UpdatePhase.failed && next.message != null) {
        _showMessageToast(next.message!);
      }
    });

    // 进度条占据真实空间把内容往下推，而不是浮在上面盖住页面标题。
    // 外层套 Scaffold 以提供 Material 背景与 MediaQuery 边距，
    // 否则裸 Column 会让内部页面失去背景色。
    // 底部不放浮层：那里有导航栏和记账悬浮按钮，压住就违背
    // 「更新不打断记账」的初衷。
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
    final theme = Theme.of(context);
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
      color: theme.colorScheme.secondaryContainer,
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isVerifying)
                    TextButton(
                      onPressed: controller.cancelDownload,
                      style: TextButton.styleFrom(
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
                backgroundColor: theme.colorScheme.secondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
