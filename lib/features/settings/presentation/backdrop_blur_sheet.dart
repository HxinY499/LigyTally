import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/preferences/backdrop_blur.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/image_backdrop.dart';

/// 背景模糊调节浮层：上面一块实时预览，下面一根滑杆。
///
/// 单独开浮层而不是把滑杆塞进设置行：调到多少全看观感，没有预览就只能
/// 反复退回记账页比对。预览拿品牌图当样本——黑白硬边最能看出糊到什么程度。
Future<void> showBackdropBlurSheet(BuildContext context) {
  return showFSheet<void>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (sheetContext) => const _BackdropBlurSheet(),
  );
}

class _BackdropBlurSheet extends ConsumerWidget {
  const _BackdropBlurSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    // 拖到哪就是哪，没有确认步骤：浮层里没有别的东西可改，
    // 再要一次「完成」纯属多一步。关闭走下滑或点遮罩。
    final sigma = ref.watch(backdropBlurProvider);
    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '背景模糊',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '记账页会把账单照片虚化成背景，0 为不虚化',
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _BlurPreview(sigma: sigma),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Icon(FLucideIcons.image, size: 16, color: colors.inactive),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: colors.primary,
                        inactiveTrackColor: colors.line,
                        thumbColor: colors.primary,
                        overlayColor: colors.ripple,
                      ),
                      child: Slider(
                        value: sigma,
                        min: kBackdropBlurMin,
                        max: kBackdropBlurMax,
                        // 20 档够细了，还能顺手把浮点尾数挡在外面。
                        divisions: 20,
                        label: sigma.round().toString(),
                        onChanged: (value) => ref
                            .read(backdropBlurProvider.notifier)
                            .setSigma(value),
                      ),
                    ),
                  ),
                  Icon(FLucideIcons.aperture, size: 16, color: colors.inactive),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 记账页顶部的等比缩样：canvas 底 + 背板 + 压在上面的标题和金额卡。
///
/// 光看一张糊图判断不了这个值好不好——要紧的是正文压上去还读不读得清，
/// 所以预览里必须带上真实版面的深色标题与白卡。
class _BlurPreview extends StatelessWidget {
  const _BlurPreview({required this.sigma});

  final double sigma;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 168,
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageBackdrop(
            // 样本图要挑和 canvas 反差最大的那版：和底色同明度的图虚化后
            // 会糊进背景，滑杆拖到头也看不出差别，等于没有预览。
            image: AssetImage(
              colors.isDark
                  ? 'assets/branding/app-icon-light.png'
                  : 'assets/branding/app-icon-dark.png',
            ),
            blurSigma: sigma,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '记一笔',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.line),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '¥',
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                      const Spacer(),
                      Text(
                        '128.00',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: colors.expense,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '分类',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
