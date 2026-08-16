import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/media/image_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/providers.dart';
import 'settings_widgets.dart';

/// 全局壁纸设置卡：一块实时预览 + 选图 / 移除 + 浓度与模糊两根滑杆。
///
/// ## 为什么壁纸能安全地做
///
/// 「照片当背景」在记账 app 里最容易翻车的地方是可读性：账单列表里 12px 的
/// 备注压在一张花照片上就没法看了。这里的做法是**只让页底让位，卡片一律
/// 保持实底**（见 [AppColors.canvas]）——照片只出现在卡片之间的缝隙、页头
/// 背后和页面边缘，正文永远压在白卡上。
///
/// 浓度滑杆的上限也钉死在 [kWallpaperOpacityMax]：页面色最少留一半，
/// 卡片外那些分组小标题才有底可压。
///
/// ## 预览为什么必须带上白卡
///
/// 光看一张糊图判断不出这个浓度好不好，要紧的是「卡片和页头压上去还认不认
/// 得出」。所以预览里必须有一张卡和一行小字，和背景模糊那个浮层同一条理由。
class AppearanceWallpaperCard extends ConsumerStatefulWidget {
  const AppearanceWallpaperCard({super.key});

  @override
  ConsumerState<AppearanceWallpaperCard> createState() =>
      _AppearanceWallpaperCardState();
}

class _AppearanceWallpaperCardState
    extends ConsumerState<AppearanceWallpaperCard> {
  bool _busy = false;

  Future<void> _pick() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final stamp = await ref
          .read(imageStorageProvider)
          .storeWallpaper(picked);
      ref.read(appearanceProvider.notifier).enableWallpaper(stamp: stamp);
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          message: '设置壁纸失败：$error',
          level: AppToastLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    // 先关配置再删文件：反过来的话，删完文件到状态更新之间的那几帧，
    // 壁纸层会去读一个已经不在的文件。
    ref.read(appearanceProvider.notifier).disableWallpaper();
    await ref.read(imageStorageProvider).deleteWallpaper();
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = ref.watch(wallpaperProvider);
    final notifier = ref.read(appearanceProvider.notifier);
    return SettingsCard(
      children: [
        if (wallpaper.enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: _WallpaperPreview(wallpaper: wallpaper),
          ),
          SettingsItem(
            icon: FLucideIcons.sunDim,
            title: '浓度',
            trailing: _MiniSlider(
              value: wallpaper.opacity,
              min: kWallpaperOpacityMin,
              max: kWallpaperOpacityMax,
              // 10 档：这条滑杆的全程只有 0.05~0.5，再细分用户分辨不出。
              divisions: 9,
              onChanged: notifier.setWallpaperOpacity,
            ),
          ),
          SettingsItem(
            icon: FLucideIcons.aperture,
            title: '模糊',
            trailing: _MiniSlider(
              value: wallpaper.blur,
              min: kWallpaperBlurMin,
              max: kWallpaperBlurMax,
              divisions: 20,
              onChanged: notifier.setWallpaperBlur,
            ),
          ),
        ],
        SettingsItem(
          icon: FLucideIcons.wallpaper,
          title: wallpaper.enabled ? '换一张' : '选择壁纸',
          trailing: _busy ? const RowSpinner() : null,
          showChevron: !_busy,
          onTap: _busy ? null : _pick,
        ),
        if (wallpaper.enabled)
          SettingsItem(
            icon: FLucideIcons.trash2,
            title: '移除壁纸',
            onTap: _busy ? null : _remove,
          ),
      ],
    );
  }
}

/// 壁纸预览：真实的壁纸层（照片 + 模糊 + 蒙版）+ 压在上面的页头和一张卡。
class _WallpaperPreview extends StatelessWidget {
  const _WallpaperPreview({required this.wallpaper});

  final WallpaperConfig wallpaper;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final path = ImageStorage.resolveSyncPath(kWallpaperRelativePath);
    return Container(
      height: 132,
      decoration: BoxDecoration(
        borderRadius: context.radii.blockAll,
        border: Border.all(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (path != null)
            ImageFiltered(
              enabled: wallpaper.blur > 0,
              imageFilter: ui.ImageFilter.blur(
                sigmaX: wallpaper.blur,
                sigmaY: wallpaper.blur,
              ),
              child: Image(
                key: ValueKey(wallpaper.stamp),
                image: FileImage(File(path)),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    const SizedBox.shrink(),
              ),
            ),
          ColoredBox(
            color: colors.canvasBase.withValues(alpha: 1 - wallpaper.opacity),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '明细',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: context.radii.blockAll,
                    boxShadow: colors.shadowCard,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: colors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '午餐',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colors.ink,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '-32.00',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.expense,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // 这行小字是整块预览的重点：它压在照片上而不是白卡上，
                // 浓度调过头时第一个变糊的就是它。
                Text(
                  '卡片外的小字压在壁纸上',
                  style: TextStyle(fontSize: 11, color: colors.inactive),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置行尾的紧凑滑杆。
///
/// 收在行尾而不是各开一个浮层：壁纸的浓度和模糊必须**看着预览调**，
/// 而预览就在同一张卡的顶部。开浮层反而把预览挡住了。
class _MiniSlider extends StatelessWidget {
  const _MiniSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      // 140 而不是更宽：这一行左边还有图标底座和标题，320 宽的机型上再宽
      // 就会把「浓度」两个字挤到省略号。
      width: 140,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: colors.primary,
          inactiveTrackColor: colors.line,
          thumbColor: colors.primary,
          overlayColor: colors.ripple,
          trackHeight: 3,
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
