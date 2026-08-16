import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';

/// 一排可横滑的风格预设卡。
///
/// ## 每张卡上画的是那套风格自己的颜色
///
/// 卡片里那块小样张用的是**预设自己解析出来的色板**，而不是当前生效的色板——
/// 浅色主题下也能看到「墨夜」是深的。这靠 [AppColors.resolve] 是个纯函数：
/// 给它一个亮度和一套配置就能算出色板，不需要真的把主题换过去。
///
/// 小样张同时表现三件事：页底色、主题色、圆角档位。密度和动效表现不出来，
/// 交给卡片下面那行小字。
class AppearancePresetRow extends StatelessWidget {
  const AppearancePresetRow({
    super.key,
    required this.config,
    required this.onPick,
  });

  final AppearanceConfig config;
  final ValueChanged<AppearancePreset> onPick;

  /// 卡片宽度。96 是「三张半露出第四张」的宽度，在 6 英寸屏上刚好提示
  /// 「右边还有」，不需要额外的箭头或小圆点。
  static const _cardWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    final matched = matchedPreset(config);
    // 「跟随系统」的预设要按当前平台亮度画样张，否则浅色手机上
    // 「素白」会画成一张深色卡。
    final platform = context.colors.brightness;
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // 卡片本身没有左右外边距，靠这里统一给：ListView 的第一 / 最后一张
        // 才能和页面 gutter 对齐，中间的间距也只有一处定义。
        padding: EdgeInsets.zero,
        itemCount: kAppearancePresets.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final preset = kAppearancePresets[index];
          return _PresetCard(
            width: _cardWidth,
            preset: preset,
            platform: platform,
            selected: preset == matched,
            onTap: () {
              HapticFeedback.selectionClick();
              onPick(preset);
            },
          );
        },
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.width,
    required this.preset,
    required this.platform,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final AppearancePreset preset;
  final Brightness platform;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // 这套预设自己的色板与圆角，与当前生效的主题无关。
    final brightness = preset.brightnessFor(platform);
    final swatch = AppColors.resolve(
      brightness,
      preset.applyTo(AppearanceConfig.initial),
    );
    final radius = AppRadius(scale: preset.corner.scale);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: context.motion(const Duration(milliseconds: 180)),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: swatch.canvasBase,
                  borderRadius: context.radii.cardAll,
                  // 选中态用主色粗描边。不做「打勾角标」：卡片只有 96 宽，
                  // 角标会压在样张上，反而看不清这套风格长什么样。
                  border: Border.all(
                    color: selected ? colors.primary : colors.line,
                    width: selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _Swatch(colors: swatch, radius: radius, preset: preset),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              preset.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? colors.primary : colors.ink,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              preset.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                color: colors.inactive,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡内小样张：一条 Hero 卡 + 两行占位。
///
/// 只画这三块，是因为它们对应用户在这一排里唯一想比较的三件事：
/// 底色深浅、主色是什么、圆角有多圆。
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colors,
    required this.radius,
    required this.preset,
  });

  final AppColors colors;
  final AppRadius radius;
  final AppearancePreset preset;

  @override
  Widget build(BuildContext context) {
    final hero = colors.hero;
    final floating = preset.navBarStyle == NavBarStyle.floating;
    // 除了首尾两块，中间的占位行全部用 Expanded 分摊剩余高度。
    //
    // 这不是偷懒：卡片的可用高度会随「显示密度」变（下面那两行标签的字号
    // 跟着 textScaler 走，字一大卡片就矮一截）。任何写死的行高都会在某一档
    // 上溢出 3px，而这块小样张不值得为它算一套自适应高度。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 24,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: hero.gradient,
              color: hero.color,
              border: hero.border,
              // 小样张里的块只有 24 高，直接套 card 档会被圆角吃成药丸，
              // 按高度折算（与圆角档位示意块同一条换算）。
              borderRadius: BorderRadius.circular(
                AppRadius.cardBase * preset.corner.scale * 24 / 88,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Expanded(child: _placeholderRow()),
        const SizedBox(height: 3),
        Expanded(child: _placeholderRow()),
        const SizedBox(height: 5),
        // 底栏形态：贴底档是一条贴边的横杠，悬浮档是一颗内缩的胶囊。
        // 这是这一排里唯一能顺手表现出来的第四个差别。
        Container(
          height: 7,
          margin: floating
              ? const EdgeInsets.symmetric(horizontal: 6)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.lineSoft),
            borderRadius: floating
                ? BorderRadius.circular(3.5)
                : BorderRadius.zero,
          ),
        ),
      ],
    );
  }

  /// 一行账单占位：左边一枚图标底座，右边一条文字条。
  Widget _placeholderRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: BorderRadius.circular(
                AppRadius.chipBase * preset.corner.scale * 12 / 32,
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Center(
            child: SizedBox(
              height: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.fill,
                  borderRadius: BorderRadius.circular(radius.block / 2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
