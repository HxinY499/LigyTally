import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/app_widgets.dart';
import 'update_available_sheet.dart';
import 'update_controller.dart';
import 'update_progress.dart';
import 'update_service.dart';

/// 应用内更新的提示层。
///
/// 包在页面外层，负责两件事：
/// 1. 启动自动检查发现新版本时，从下方弹出浮层（版本 + 更新说明）
/// 2. 浮层已关掉但还在下载时，在状态栏下挂一颗不占布局的进度胶囊
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

  /// 浮层还开着时进度画在浮层里，不要再叠一颗胶囊。
  var _sheetOpen = false;

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
    setState(() => _sheetOpen = true);
    final action = await showUpdateAvailableSheet(context, info);
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    if (action == UpdateSheetAction.ignore) {
      ref.read(updateControllerProvider.notifier).ignoreVersionAndDismiss();
    }
  }

  void _showMessageToast(String message) {
    showAppToast(context, message: message, level: AppToastLevel.error);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateControllerProvider);
    final showChip = state.isBusy && !_sheetOpen;

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

    return Stack(
      children: [
        widget.child,
        if (showChip)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 20,
            right: 20,
            child: Center(
              child: UpdateDownloadChip(
                key: const ValueKey('update-download-chip'),
                state: state,
                onCancel: () => ref
                    .read(updateControllerProvider.notifier)
                    .cancelDownload(),
              ),
            ),
          ),
      ],
    );
  }
}
