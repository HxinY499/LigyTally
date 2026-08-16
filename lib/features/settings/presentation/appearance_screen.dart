import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/preferences/app_icon.dart';
import '../../../core/theme/app_density.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/hero_skin.dart';
import '../../../core/theme/sign_palette.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'accent_color_sheet.dart';
import 'app_icon_picker_sheet.dart';
import 'appearance_code_sheet.dart';
import 'appearance_option_sheet.dart';
import 'appearance_preset_row.dart';
import 'appearance_wallpaper_card.dart';
import 'backdrop_blur_sheet.dart';
import 'settings_widgets.dart';

/// 外观二级页。
///
/// ## 两层结构：先成品，再零件
///
/// 顶上是共享样张，紧跟着是一排**风格预设**——按一下同时换掉深浅、主题色、
/// 圆角、密度、动效、Hero 卡和底栏。多数人只想「换一个不难看的样子」，
/// 不想做十几次决策；而对实现方来说，保证六套预设好看是可控的，保证十几个
/// 开关的全部组合都好看是不可能的。
///
/// 预设之下才是逐项开关。改任何一项，上面那排预设就集体取消选中（变成
/// 「自定义」）——这不是 bug，是唯一诚实的表示法。
///
/// ## 为什么值得单开一屏
///
/// 不是为了让设置首页短一点——这些项**互相影响**，而它们原本是各自独立的
/// 浮层：主题色浮层里画一份 Hero 卡预览，圆角浮层里再画一份，想知道
/// 「深色 + 橙色 + 极圆 + 紧凑」合起来长什么样，只能来回开关浮层拿脑子拼。
///
/// 这一屏把预览提到顶部**共享**：底下任何一档一改，同一张样张立刻跟着变。
///
/// ## 什么摊开、什么收进浮层
///
/// 摊开的是「一改样张就变形、且档位名自明」的：深浅、圆角、预设。
/// 收进浮层的是「需要一行说明才说得清」的（密度、动效、Hero 卡、底栏、
/// 收支配色），以及带滑杆的（主题色、背景模糊）——那些摊开会把这一屏
/// 撑成三屏，说明文字还会和样张抢注意力。
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appearanceProvider);
    final notifier = ref.read(appearanceProvider.notifier);
    // 「跟随系统」下纯黑档到底生不生效，取决于当前平台亮度。
    final isDark = context.colors.isDark;
    return AppTopBar(
      title: '外观',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          sliver: SliverList.list(
            children: [
              const _AppearancePreview(),
              const SizedBox(height: 18),

              const SectionLabel('风格'),
              AppearancePresetRow(
                config: config,
                onPick: notifier.applyPreset,
              ),
              const SizedBox(height: 10),
              SettingsCard(
                children: [
                  SettingsItem(
                    icon: FLucideIcons.share2,
                    title: '主题码',
                    subtitle: '把整套外观发给别人，或套用别人的',
                    showChevron: true,
                    onTap: () => _openCodeSheet(context),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const SectionLabel('主题'),
              SettingsCard(
                children: [
                  SettingsItem(
                    icon: FLucideIcons.sunMoon,
                    title: '深浅模式',
                    trailing: _ThemeModeToggle(
                      value: config.themeMode,
                      onChanged: notifier.setThemeMode,
                    ),
                  ),
                  // 只在深色真正生效时出现。浅色下它一个像素都改不了，
                  // 置灰摆在那里让人猜它归谁管，不如跟着深色一起收起来
                  //（与「背景模糊只在背板模式下出现」同一条规则）。
                  if (isDark)
                    SettingsItem(
                      icon: FLucideIcons.contrast,
                      title: '纯黑深色',
                      subtitle: 'OLED 屏更省电，页底压到纯黑',
                      trailing: TrailingSwitch(
                        value: config.trueBlack,
                        onChange: notifier.setTrueBlack,
                      ),
                    ),
                  SettingsItem(
                    icon: FLucideIcons.palette,
                    title: '主题色',
                    trailing: const AccentPreview(),
                    showChevron: true,
                    onTap: () => showAccentColorSheet(context),
                  ),
                  SettingsItem(
                    icon: FLucideIcons.arrowDownUp,
                    title: '收支配色',
                    value: config.signPalette.label,
                    showChevron: true,
                    onTap: () => _pickSignPalette(context, notifier, config),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const SectionLabel('圆角'),
              _CornerCard(value: config.corner, onChanged: notifier.setCorner),

              const SizedBox(height: 18),
              const SectionLabel('排版'),
              SettingsCard(
                children: [
                  SettingsItem(
                    icon: FLucideIcons.textCursorInput,
                    title: '显示密度',
                    subtitle: '字号与行高，决定一屏能看几笔',
                    value: config.density.label,
                    showChevron: true,
                    onTap: () => _pickDensity(context, notifier, config),
                  ),
                  SettingsItem(
                    icon: FLucideIcons.hash,
                    title: '金额千分位',
                    subtitle: '19,042.60',
                    trailing: TrailingSwitch(
                      value: config.moneyGrouped,
                      onChange: notifier.setMoneyGrouped,
                    ),
                  ),
                  SettingsItem(
                    icon: FLucideIcons.alignJustify,
                    title: '数字等宽',
                    subtitle: '金额列的小数点逐行对齐',
                    trailing: TrailingSwitch(
                      value: config.tabularFigures,
                      onChange: notifier.setTabularFigures,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const SectionLabel('版式'),
              SettingsCard(
                children: [
                  SettingsItem(
                    icon: FLucideIcons.creditCard,
                    title: '摘要卡样式',
                    subtitle: '明细页与统计页顶部那张大卡',
                    value: config.heroStyle.label,
                    showChevron: true,
                    onTap: () => _pickHeroStyle(context, notifier, config),
                  ),
                  SettingsItem(
                    icon: FLucideIcons.panelBottom,
                    title: '底栏样式',
                    value: config.navBarStyle.label,
                    showChevron: true,
                    onTap: () => _pickNavBarStyle(context, notifier, config),
                  ),
                  SettingsItem(
                    icon: FLucideIcons.zap,
                    title: '动效强度',
                    subtitle: '也影响页面切换的过渡',
                    value: config.motion.label,
                    showChevron: true,
                    onTap: () => _pickMotion(context, notifier, config),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const SectionLabel('背景'),
              const AppearanceWallpaperCard(),

              const SizedBox(height: 18),
              const SectionLabel('记账页'),
              SettingsCard(
                children: [
                  SettingsItem(
                    icon: FLucideIcons.image,
                    title: '账单图片',
                    subtitle:
                        config.transactionImageStyle ==
                            TransactionImageStyle.backdrop
                        ? '整页背板'
                        : '拍立得贴纸',
                    trailing: _ImageStyleToggle(
                      value: config.transactionImageStyle,
                      onChanged: notifier.setTransactionImageStyle,
                    ),
                  ),
                  // 模糊是背板独有的参数，贴纸模式下怎么调都不会有变化。
                  // 与其置灰摆在那里让人猜它归谁管，不如跟着背板一起收起来。
                  if (config.transactionImageStyle ==
                      TransactionImageStyle.backdrop)
                    SettingsItem(
                      icon: FLucideIcons.aperture,
                      title: '背景模糊',
                      value: config.backdropBlur.round().toString(),
                      showChevron: true,
                      onTap: () => showBackdropBlurSheet(context),
                    ),
                  SettingsItem(
                    icon: FLucideIcons.layoutGrid,
                    title: '分类选择样式',
                    trailing: _LayoutToggle(
                      value: config.categoryPickerLayout,
                      onChanged: notifier.setCategoryPickerLayout,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              // 单独一组：它改的是桌面 launcher 图标，app 内一个像素都不变，
              // 混在上面那些「app 内长什么样」的设置里语义是错的，
              // 顶部那张样张也永远反映不了它。也因此它不进主题码。
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

  Future<void> _openCodeSheet(BuildContext context) async {
    final applied = await showAppearanceCodeSheet(context);
    if (applied == true && context.mounted) {
      showAppToast(context, message: '外观已套用', level: AppToastLevel.success);
    }
  }

  Future<void> _pickSignPalette(
    BuildContext context,
    AppearanceController notifier,
    AppearanceConfig config,
  ) async {
    final picked = await showAppearanceOptionSheet<SignPalette>(
      context,
      title: '收支配色',
      caption: '只换支出和收入两个数字的颜色。删除、报错这些地方一直是红的，不跟着翻。',
      current: config.signPalette,
      options: const [
        AppearanceOption(
          value: SignPalette.warmExpense,
          label: '红支绿收',
          caption: '记账习惯：花掉的钱是红的',
          icon: FLucideIcons.trendingDown,
        ),
        AppearanceOption(
          value: SignPalette.coolExpense,
          label: '绿支红收',
          caption: '行情习惯：红涨绿跌',
          icon: FLucideIcons.trendingUp,
        ),
      ],
    );
    if (picked != null) notifier.setSignPalette(picked);
  }

  Future<void> _pickDensity(
    BuildContext context,
    AppearanceController notifier,
    AppearanceConfig config,
  ) async {
    final picked = await showAppearanceOptionSheet<AppDensityLevel>(
      context,
      title: '显示密度',
      caption: '同时缩放字号和行高。系统里调过的字号仍然生效，这一档是在它之上再乘一次。',
      current: config.density,
      options: const [
        AppearanceOption(
          value: AppDensityLevel.compact,
          label: '紧凑',
          caption: '一屏多看一两笔',
          icon: FLucideIcons.alignJustify,
        ),
        AppearanceOption(
          value: AppDensityLevel.standard,
          label: '适中',
          caption: '默认',
          icon: FLucideIcons.alignLeft,
        ),
        AppearanceOption(
          value: AppDensityLevel.relaxed,
          label: '宽松',
          caption: '字更大、行更松',
          icon: FLucideIcons.stretchVertical,
        ),
      ],
    );
    if (picked != null) notifier.setDensity(picked);
  }

  Future<void> _pickHeroStyle(
    BuildContext context,
    AppearanceController notifier,
    AppearanceConfig config,
  ) async {
    final picked = await showAppearanceOptionSheet<HeroCardStyle>(
      context,
      title: '摘要卡样式',
      caption: '明细页和统计页顶部是同一张卡，一起变。',
      current: config.heroStyle,
      options: const [
        AppearanceOption(
          value: HeroCardStyle.gradient,
          label: '渐变',
          caption: '默认，主题色斜向渐变',
          icon: FLucideIcons.blend,
        ),
        AppearanceOption(
          value: HeroCardStyle.solid,
          label: '纯色',
          caption: '安静一档，深色下不刺眼',
          icon: FLucideIcons.square,
        ),
        AppearanceOption(
          value: HeroCardStyle.outline,
          label: '描边',
          caption: '白面 + 主色描边，整页只剩白卡',
          icon: FLucideIcons.squareDashed,
        ),
      ],
    );
    if (picked != null) notifier.setHeroStyle(picked);
  }

  Future<void> _pickNavBarStyle(
    BuildContext context,
    AppearanceController notifier,
    AppearanceConfig config,
  ) async {
    final picked = await showAppearanceOptionSheet<NavBarStyle>(
      context,
      title: '底栏样式',
      current: config.navBarStyle,
      options: const [
        AppearanceOption(
          value: NavBarStyle.docked,
          label: '贴底',
          caption: '默认，铺满屏幕底部',
          icon: FLucideIcons.panelBottom,
        ),
        AppearanceOption(
          value: NavBarStyle.floating,
          label: '悬浮',
          caption: '四周留白的胶囊',
          icon: FLucideIcons.rectangleHorizontal,
        ),
      ],
    );
    if (picked != null) notifier.setNavBarStyle(picked);
  }

  Future<void> _pickMotion(
    BuildContext context,
    AppearanceController notifier,
    AppearanceConfig config,
  ) async {
    final picked = await showAppearanceOptionSheet<MotionLevel>(
      context,
      title: '动效强度',
      caption: '缩放全应用的动画时长，也换掉页面之间的转场。',
      current: config.motion,
      options: const [
        AppearanceOption(
          value: MotionLevel.full,
          label: '完整',
          caption: '默认',
          icon: FLucideIcons.zap,
        ),
        AppearanceOption(
          value: MotionLevel.reduced,
          label: '减弱',
          caption: '快一倍，转场只淡入',
          icon: FLucideIcons.gauge,
        ),
        AppearanceOption(
          value: MotionLevel.off,
          label: '关闭',
          caption: '点了就到，什么都不动',
          icon: FLucideIcons.zapOff,
        ),
      ],
    );
    if (picked != null) notifier.setMotion(picked);
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
/// 样张里的每一个颜色都从 [HeroSkin] 取，不写死白色：摘要卡样式选到
/// 「描边」时卡面会变白，写死的白字在样张里会先消失一次。
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
    final hero = colors.hero;
    // 样张自己也守动效档位：选了「关闭」却看到样张在那里柔和变形，
    // 用户会以为这个开关没生效。
    final morph = context.motion(_morph);
    return AnimatedContainer(
      duration: morph,
      curve: _curve,
      padding: const EdgeInsets.all(14),
      // 外框代表「浮层」这一档，是全应用最大的圆角。
      decoration: BoxDecoration(
        color: colors.canvasBase,
        borderRadius: radii.sheetAll,
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: morph,
            curve: _curve,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              gradient: hero.gradient,
              color: hero.color,
              border: hero.border,
              borderRadius: radii.cardAll,
              boxShadow: hero.shadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本月支出',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: hero.foregroundSoft,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '1,280.00',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: hero.foreground,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AnimatedContainer(
            duration: morph,
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
                  duration: morph,
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
                        duration: morph,
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
            duration: morph,
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
            duration: context.motion(const Duration(milliseconds: 180)),
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
