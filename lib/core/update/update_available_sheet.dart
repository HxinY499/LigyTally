import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_widgets.dart';
import 'release_notes.dart';
import 'update_controller.dart';
import 'update_progress.dart';
import 'update_service.dart';

/// 启动自动检查发现新版本时，用户在浮层里选的动作。
enum UpdateSheetAction {
  /// 忽略这个版本，下次启动不再提示。
  ignore,

  /// 立刻下载并安装。
  update,
}

/// 从下方弹出「发现新版本」浮层，展示版本、体积和更新说明。
///
/// 点遮罩或下滑关闭返回 null：只收起，不写入忽略，下次启动还会提示。
/// 「忽略」才 pop [UpdateSheetAction.ignore]。
/// 点「更新」不关浮层，进度就画在按钮原来的位置。
Future<UpdateSheetAction?> showUpdateAvailableSheet(
  BuildContext context,
  UpdateInfo info,
) {
  return showFSheet<UpdateSheetAction>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: 0.72,
    builder: (sheetContext) => _UpdateAvailableSheet(info: info),
  );
}

class _UpdateAvailableSheet extends ConsumerStatefulWidget {
  const _UpdateAvailableSheet({required this.info});

  final UpdateInfo info;

  @override
  ConsumerState<_UpdateAvailableSheet> createState() =>
      _UpdateAvailableSheetState();
}

class _UpdateAvailableSheetState extends ConsumerState<_UpdateAvailableSheet> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final notes = parseReleaseNotes(widget.info.releaseNotes);
    final sizeLabel = widget.info.apkSize > 0
        ? '${(widget.info.apkSize / 1024 / 1024).toStringAsFixed(0)}MB'
        : null;
    final subtitle = [
      'v${widget.info.version}',
      ?sizeLabel,
    ].join(' · ');

    final updateState = ref.watch(updateControllerProvider);
    final busy = updateState.isBusy;
    final verifying = updateState.phase == UpdatePhase.verifying;

    ref.listen<UpdateState>(updateControllerProvider, (previous, next) {
      if (next.phase == UpdatePhase.readyToInstall &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    return Material(
      color: colors.surface,
      borderRadius: context.radii.sheetTop,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '发现新版本',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.36,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: notes.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) => _NoteLine(notes[index]),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (busy)
                _DownloadPanel(
                  state: updateState,
                  verifying: verifying,
                  onCancel: verifying
                      ? null
                      : () => ref
                            .read(updateControllerProvider.notifier)
                            .cancelDownload(),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        variant: AppButtonVariant.outline,
                        onPress: () =>
                            Navigator.pop(context, UpdateSheetAction.ignore),
                        child: const Text('忽略'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        onPress: () => ref
                            .read(updateControllerProvider.notifier)
                            .downloadAndInstall(widget.info),
                        child: const Text('更新'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadPanel extends StatelessWidget {
  const _DownloadPanel({
    required this.state,
    required this.verifying,
    required this.onCancel,
  });

  final UpdateState state;
  final bool verifying;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          updateDownloadLabel(state),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: colors.muted),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: UpdateDownloadTrack(
                fraction: verifying ? null : state.progress?.fraction,
                height: 10,
              ),
            ),
            if (onCancel != null) ...[
              const SizedBox(width: 12),
              AppButton(
                variant: AppButtonVariant.outline,
                onPress: onCancel,
                child: const Text('取消'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: colors.ink,
            ),
          ),
        ),
      ],
    );
  }
}
