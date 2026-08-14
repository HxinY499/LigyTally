import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/preferences/accent_color.dart';
import '../../../core/preferences/app_icon.dart';
import '../../../core/preferences/backdrop_blur.dart';
import '../../../core/preferences/category_picker_layout.dart';
import '../../../core/preferences/corner_style.dart';
import '../../../core/preferences/theme_mode.dart';
import '../../../core/preferences/transaction_image_style.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'accent_color_sheet.dart';
import 'app_icon_picker_sheet.dart';
import 'backdrop_blur_sheet.dart';
import 'settings_widgets.dart';

/// 外观二级页：深浅、主题色、圆角、记账页版式、桌面图标。
///
/// ## 为什么值得单开一屏
///
/// 不是为了让设置首页短一点——这几项**互相影响**，而之前它们是六个各自
/// 独立的浮层：主题色浮层里画一份 Hero 卡预览，圆角浮层里再画一份，
/// 想知道「深色 + 橙色 + 极圆」合起来长什么样，只能来回开关浮层拿脑子拼。
///
/// 这一屏把预览提到顶部**共享**：底下任何一档一改，同一张样张立刻跟着变。
/// 深浅、圆角、记账页版式因此直接摊在页面里（不再各开浮层），改完不用退出去看。
///
/// 主题色仍然是浮层：它带色相 / 浓淡两条滑杆，摊开会把这一屏撑成两屏，
/// 而且拖滑杆时需要浮层自己那份「按当前值现算」的即时预览。
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageStyle = ref.watch(transactionImageStyleProvider);
    return AppTopBar(
      title: '外观',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          sliver: SliverList.list(
            children: [
              const _AppearancePreview(),
              const SizedBox(height: 18),
              const SectionLabel('主题'),
              SettingsCard(
                children: [
                  SettingsItem(
                    icon: FLucideIcons.sunMoon,
                    title: '深浅模式',
                    trailing: _ThemeModeToggle(
                      value: ref.watch(appThemeModeProvider),
                      onChanged: (value) => ref
                          .read(appThemeModeProvider.notifier)
                          .setMode(value),
                    ),
                  ),
                  SettingsItem(
                    icon: FLucideIcons.palette,
                    title: '主题色',
                    trailing: const AccentPreview(),
                    showChevron: true,
                    onTap: () => showAccentColorSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const SectionLabel('圆角'),
              _CornerCard(
                value: ref.watch(appCornerStyleProvider),
                onChanged: (value) =>
                    ref.read(appCornerStyleProvider.notifier).setStyle(value),
              ),
              const SizedBox(height: 18),
              const SectionLabel('记账页'),
              SettingsCard(
                children: [
                  SettingsItem(
                    icon: FLucideIcons.image,
                    title: '账单图片',
                    subtitle: imageStyle == TransactionImageStyle.backdrop
                        ? '整页背板'
                        : '拍立得贴纸',
                    trailing: _ImageStyleToggle(
                      value: imageStyle,
                      onChanged: (value) => ref
                          .read(transactionImageStyleProvider.notifier)
                          .setStyle(value),
                    ),
                  ),
                  // 模糊是背板独有的参数，贴纸模式下怎么调都不会有变化。
                  // 与其置灰摆在那里让人猜它归谁管，不如跟着背板一起收起来。
                  if (imageStyle == TransactionImageStyle.backdrop)
                    SettingsItem(
                      icon: FLucideIcons.aperture,
                      title: '背景模糊',
                      value: ref.watch(backdropBlurProvider).round().toString(),
                      showChevron: true,
                      onTap: () => showBackdropBlurSheet(context),
                    ),
                  SettingsItem(
                    icon: FLucideIcons.layoutGrid,
                    title: '分类选择样式',
                    trailing: _LayoutToggle(
                      value: ref.watch(categoryPickerLayoutProvider),
                      onChanged: (value) => ref
                          .read(categoryPickerLayoutProvider.notifier)
                          .setLayout(value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // 单独一组：它改的是桌面 launcher 图标，app 内一个像素都不变，
              // 混在上面那些「app 内长什么样」的设置里语义是错的，
              // 顶部那张样张也永远反映不了它。
              const SectionLabel('桌面'),
              SettingsCard(
                children: [
                  SettingsItem(
                    icon: FLucideIcons.smartphone,
                    title: '应用图标',
                    subtitle: '仅影响桌面上的图标',
                    trailing: AppIconPreview(style: ref.watch(appIconProvider)),
                    showChevron: true,
                    onTap: () => _pickAppIcon(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickAppIcon(BuildContext context, WidgetRef ref) async {
    final current = ref.read(appIconProvider);
    final picked = await showAppIconPickerSheet(context, current: current);
    if (picked == null || picked == current || !context.mounted) return;
    try {
      await ref.read(appIconProvider.notifier).setStyle(picked);
      if (context.mounted) {
        showAppToast(context, message: '图标已切换，桌面可能需要几秒刷新');
      }
    } catch (error) {
      if (context.mounted) {
        showAppToast(
          context,
          message: '切换失败：$error',
          level: AppToastLevel.error,
        );
      }
    }
  }
}

/// 页面顶部的共享样张：Hero 卡 + 一行账单 + 一颗通栏按钮。
///
/// 挑这三样是因为它们正好覆盖三档圆角（卡片 / 卡内小块 / 浮层按钮），
/// 同时也是主题色出场面积最大的三处。只放一张卡的话，用户看不出
/// 「弹窗按钮会跟着变多圆」。
///
/// 通栏上写「按钮」而不是「确定」：这是示意块，不是操作，写成确定会让人去点。
class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview();

  static const _morph = Duration(milliseconds: 200);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    return AnimatedContainer(
      duration: _morph,
      curve: _curve,
      padding: const EdgeInsets.all(14),
      // 外框代表「浮层」这一档，是全应用最大的圆角。
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: radii.sheetAll,
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: _morph,
            curve: _curve,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              gradient: colors.heroGradient,
              borderRadius: radii.cardAll,
              boxShadow: colors.shadowHeroPrimary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本月支出',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xCCFFFFFF),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '1,280.00',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AnimatedContainer(
            duration: _morph,
            curve: _curve,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: radii.cardAll,
              boxShadow: colors.shadowCard,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: _morph,
                  curve: _curve,
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    borderRadius: radii.chipAll,
                  ),
                  child: Icon(
                    FLucideIcons.utensils,
                    size: 16,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '午餐',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: _morph,
                        curve: _curve,
                        height: 8,
                        width: 96,
                        decoration: BoxDecoration(
                          color: colors.fill,
                          borderRadius: radii.blockAll,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '-32.00',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.expense,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AnimatedContainer(
            duration: _morph,
            curve: _curve,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: colors.primary, width: 1.5),
              borderRadius: radii.sheetAll,
            ),
            child: Text(
              '按钮',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 圆角档位卡：一排示意方块，直接摊在页面里而不是再开一层浮层。
///
/// 顶部样张就在同一屏，点一下立刻看到整套版式重新成型——
/// 这正是把外观收进二级页想换来的东西。
class _CornerCard extends StatelessWidget {
  const _CornerCard({required this.value, required this.onChanged});

  final AppCornerStyle value;
  final ValueChanged<AppCornerStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: context.radii.cardAll,
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final style in AppCornerStyle.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _CornerOption(
                      style: style,
                      selected: style == value,
                      onTap: () => onChanged(style),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '卡片、弹窗、输入框整体缩放；开关和徽章保持胶囊',
            style: TextStyle(fontSize: 11.5, color: colors.inactive),
          ),
        ],
      ),
    );
  }
}

/// 单个档位：上面一枚示意方块，下面一行档位名。
///
/// 示意方块用**这一档自己的圆角**而不是当前生效的圆角，所以五枚方块摆在
/// 一起就是一条从方到圆的梯子，不用逐个点开也看得出差别。
class _CornerOption extends StatelessWidget {
  const _CornerOption({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final AppCornerStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 34,
            decoration: BoxDecoration(
              color: selected ? colors.primarySoft : colors.fill,
              borderRadius: BorderRadius.circular(swatchRadius(style, 34)),
              border: Border.all(
                color: selected ? colors.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            style.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colors.primary : colors.inactive,
            ),
          ),
        ],
      ),
    );
  }
}

/// 圆角示意小方块的圆角。
///
/// 不能直接套 `card` 档：示意块只有 30~34 高，18 的圆角会把它吃成一颗药丸，
/// 五档看起来一模一样。按方块高度相对一张真实卡片的高度折算，
/// 「哪档更圆」这个唯一要传达的信息才保得住。
double swatchRadius(AppCornerStyle style, double boxHeight) =>
    AppRadius.cardBase * style.scale * boxHeight / 88;

/// 主题色行的右侧色点：当前强调色，点进浮层再换。
class AccentPreview extends ConsumerWidget {
  const AccentPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 必须自己订阅偏好，不能只读 `context.colors.primary`：MaterialApp 换主题
    // 要走 200ms 淡变，浮层里拖色相条时这颗点会一路拖在滑块后面。
    ref.watch(appAccentProvider);
    final colors = context.colors;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: colors.line),
      ),
    );
  }
}

/// 应用图标行的右侧小缩略图：让用户在列表里就能看到当前选中的图标样式，
/// 不需要文字说明。尺寸和其它行右侧的开关 / 胶囊控件视觉重量对齐。
class AppIconPreview extends StatelessWidget {
  const AppIconPreview({super.key, required this.style});

  final AppIconStyle style;

  @override
  Widget build(BuildContext context) {
    final asset = style == AppIconStyle.dark
        ? 'assets/branding/app-icon-dark.png'
        : 'assets/branding/app-icon-light.png';
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        borderRadius: context.radii.chipAll,
        border: Border.all(color: context.colors.line, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(asset, fit: BoxFit.cover),
    );
  }
}

/// 外观的三态切换器：跟随系统 / 浅色 / 深色。
///
/// 摊平在行尾而不是另开一级浮层：只有三个互斥选项，一眼就能看清当前档位，
/// 还省掉一次跳转。每一档都是「显式指定」，没有「关闭」这种隐含态：
/// 用户选了浅色，就算系统入夜也不该被翻成深色。
class _ThemeModeToggle extends StatelessWidget {
  const _ThemeModeToggle({required this.value, required this.onChanged});

  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  static const _icons = {
    AppThemeMode.system: FLucideIcons.sunMoon,
    AppThemeMode.light: FLucideIcons.sun,
    AppThemeMode.dark: FLucideIcons.moon,
  };

  @override
  Widget build(BuildContext context) {
    return SettingsToggleTrack(
      children: [
        for (final mode in AppThemeMode.values)
          SettingsToggleIcon(
            icon: _icons[mode]!,
            selected: value == mode,
            onTap: () => onChanged(mode),
          ),
      ],
    );
  }
}

/// 分类选择样式的紧凑二态切换器：列表 / 网格。
class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({required this.value, required this.onChanged});

  final CategoryPickerLayout value;
  final ValueChanged<CategoryPickerLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsToggleTrack(
      children: [
        SettingsToggleIcon(
          icon: FLucideIcons.list,
          selected: value == CategoryPickerLayout.list,
          onTap: () => onChanged(CategoryPickerLayout.list),
        ),
        SettingsToggleIcon(
          icon: FLucideIcons.layoutGrid,
          selected: value == CategoryPickerLayout.grid,
          onTap: () => onChanged(CategoryPickerLayout.grid),
        ),
      ],
    );
  }
}

/// 记账页账单图片展示方式的二态切换器：整页背板 / 拍立得贴纸。
class _ImageStyleToggle extends StatelessWidget {
  const _ImageStyleToggle({required this.value, required this.onChanged});

  final TransactionImageStyle value;
  final ValueChanged<TransactionImageStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsToggleTrack(
      children: [
        SettingsToggleIcon(
          icon: FLucideIcons.wallpaper,
          selected: value == TransactionImageStyle.backdrop,
          onTap: () => onChanged(TransactionImageStyle.backdrop),
        ),
        SettingsToggleIcon(
          icon: FLucideIcons.sticker,
          selected: value == TransactionImageStyle.polaroid,
          onTap: () => onChanged(TransactionImageStyle.polaroid),
        ),
      ],
    );
  }
}
