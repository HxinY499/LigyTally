import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'update_controller.dart';

/// 浮层 / 设置行用的进度文案：有体积就写 `12 / 25 MB`，校验中换短句。
String updateDownloadLabel(UpdateState state) {
  if (state.phase == UpdatePhase.verifying) return '正在校验';
  final total = state.progress?.total ?? state.info?.apkSize ?? 0;
  final received = state.progress?.received ?? 0;
  if (total > 0) {
    return '${_mb(received)} / ${_mb(total)} MB';
  }
  final fraction = state.progress?.fraction;
  if (fraction != null) return '下载 ${(fraction * 100).round()}%';
  return '正在下载';
}

/// 关掉浮层后那颗胶囊上的短文案，宽度有限。
String updateDownloadChipLabel(UpdateState state) {
  if (state.phase == UpdatePhase.verifying) return '正在校验';
  final fraction = state.progress?.fraction;
  if (fraction != null) return '下载 ${(fraction * 100).round()}%';
  return '正在下载';
}

String _mb(int bytes) => (bytes / (1024 * 1024)).round().toString();

/// 圆角轨道。和分段选择器同一档圆角，不用 Material 默认进度条那条硬边。
///
/// [fraction] 为 null 时是校验中的不确定态，一条色块在轨道里来回走。
class UpdateDownloadTrack extends StatelessWidget {
  const UpdateDownloadTrack({
    super.key,
    required this.fraction,
    this.height = 8,
  });

  final double? fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(context.radii.block),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.primarySoft),
            if (fraction == null)
              const _IndeterminateFill()
            else
              // 控制器按 1% 节流推送，直接把 fraction 交给 widthFactor
              // 会一格一格地跳。补间到下一个百分点，读起来才是连续推进。
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: fraction!.clamp(0.0, 1.0),
                ),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                builder: (context, value, child) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value,
                    heightFactor: 1,
                    child: child,
                  ),
                ),
                child: ColoredBox(color: colors.primary),
              ),
          ],
        ),
      ),
    );
  }
}

class _IndeterminateFill extends StatefulWidget {
  const _IndeterminateFill();

  @override
  State<_IndeterminateFill> createState() => _IndeterminateFillState();
}

class _IndeterminateFillState extends State<_IndeterminateFill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Align(
          alignment: Alignment(-1.2 + 2.4 * _controller.value, 0),
          child: child,
        );
      },
      child: FractionallySizedBox(
        widthFactor: 0.34,
        heightFactor: 1,
        child: ColoredBox(color: colors.primary),
      ),
    );
  }
}

/// 浮层关掉后贴在状态栏下方的进度胶囊。不进布局、不推页头。
class UpdateDownloadChip extends StatelessWidget {
  const UpdateDownloadChip({
    super.key,
    required this.state,
    required this.onCancel,
  });

  final UpdateState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final verifying = state.phase == UpdatePhase.verifying;
    final fraction = verifying ? null : state.progress?.fraction;

    // 底色和阴影只画在 DecoratedBox 上，Material 退成透明层，
    // 单纯为「取消」提供水波纹和裁切。
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: context.radii.blockAll,
        boxShadow: colors.shadowCard,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: context.radii.blockAll,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                child: UpdateDownloadTrack(fraction: fraction, height: 6),
              ),
              const SizedBox(width: 10),
              // 锁死宽度：「下载 7%」和「正在校验」不一样宽，
              // 不锁的话胶囊会跟着进度一路改宽度。
              SizedBox(
                width: 62,
                child: Text(
                  updateDownloadChipLabel(state),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
              ),
              // 校验阶段取消已经没有意义，但位置留着并置灰，
              // 否则胶囊会在最后一秒突然缩短。
              InkWell(
                onTap: verifying ? null : onCancel,
                borderRadius: context.radii.chipAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Text(
                    '取消',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: verifying ? colors.inactive : colors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
