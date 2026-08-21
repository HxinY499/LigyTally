import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_density.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_widgets.dart';

/// 设置页与其二级页共用的行 / 卡片 / 切换器外壳。
///
/// 抽出来是因为「外观」被拆成二级页之后，两屏必须长成同一副样子——
/// 各写一套的话，行高、图标底座尺寸、分割线缩进立刻会漂开，
/// 从设置页点进外观页会像换了个 app。

/// 分组小标题：卡片外的灰色说明文字。
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: context.colors.inactive,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// 设置卡片容器：白底、大圆角、组内发丝分割线。
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: context.radii.cardAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            // 分割线从标题文字起始处开始（左 16 + 图标 32 + 间距 12），
            // 不切到左侧图标，视觉上更整齐。
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 60,
                color: colors.lineSoft,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 设置列表行：左侧图标 + 标题（可带副标题），右侧值 / 控件 / chevron。
///
/// 右侧统一收在 16 的内边距上——chevron、开关、值文字的右边缘对齐同一条线，
/// 所以带 chevron 的行不再额外撑出 8px。
class SettingsItem extends StatelessWidget {
  const SettingsItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.showChevron = false,
    this.accent = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// 右侧灰色只读值。
  final String? value;
  final Widget? trailing;
  final bool showChevron;

  /// true 时标题与图标走品牌色，用于「有新版本可更新」这类强引导。
  final bool accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final density = context.density;
    return InkWell(
      onTap: onTap,
      child: Padding(
        // 垂直内边距跟着显示密度缩，水平不跟：左右留白是版面骨架，
        // 紧凑档跟着缩会让图标贴到卡片边缘。
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: density.space(12),
        ),
        // minHeight 40：让「只有标题」「标题+副标题」「带开关」三种行
        // 的高度都落在 64，否则开关（39 高）会把那一行顶得比邻居高。
        // 这条下限也跟着密度走，否则紧凑档只能压掉内边距那 3px。
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: density.space(40)),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent ? colors.primary : colors.primarySoft,
                  borderRadius: context.radii.chipAll,
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 17,
                  color: accent ? Colors.white : colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: accent ? colors.primary : colors.ink,
                        height: 1.25,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.inactive,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                Text(
                  value!,
                  style: TextStyle(fontSize: 14, color: colors.muted),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              if (showChevron) ...[
                const SizedBox(width: 6),
                Icon(FLucideIcons.chevronRight, size: 18, color: colors.faint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 行尾开关：把 forui 开关的隐形留白补掉，让轨道右边缘和 chevron 对齐。
///
/// [AppSwitch] 内部 FLabel 左右各留 8，CupertinoSwitch 的 59×39 画布相对
/// 51×31 的轨道又各多出 4 —— 右侧共空 12px，不修正就会比其它行内缩。
class TrailingSwitch extends StatelessWidget {
  const TrailingSwitch({
    super.key,
    required this.value,
    required this.onChange,
  });

  final bool value;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(12, 0),
      child: AppSwitch(value: value, onChange: onChange),
    );
  }
}

/// 行内小转圈：与 chevron 同宽，替换时不会让右侧跳动。
class RowSpinner extends StatelessWidget {
  const RowSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: context.colors.primary,
      ),
    );
  }
}

/// 设置行右侧分段切换器的几何，被各个二 / 三态切换器和 [SettingsToggleIcon] 共用。
///
/// 尺寸钉死；圆角走 [AppRadius.block]，和统计页年月日、记账页收支同一档。
/// 真正的胶囊（[AppSwitch]）不在这里。
const double kTogglePadding = 3;
const double kToggleIconWidth = 38;
const double kToggleIconHeight = 28;

/// 分段切换器的轨道：灰底 + 一块滑动的白底滑块 + 内嵌若干枚 [SettingsToggleIcon]。
///
/// 滑块用位移，不用每枚自己淡入淡出背景——`Color.lerp` 到
/// [Colors.transparent]（透明黑）会在取消选中的那枚上闪一层灰。
class SettingsToggleTrack extends StatelessWidget {
  const SettingsToggleTrack({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trackRadius = context.radii.block;
    final selectedIndex = children.indexWhere(
      (child) => child is SettingsToggleIcon && child.selected,
    );
    final index = selectedIndex < 0 ? 0 : selectedIndex;
    return Container(
      padding: const EdgeInsets.all(kTogglePadding),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(trackRadius),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: context.motion(const Duration(milliseconds: 160)),
            curve: Curves.easeOutCubic,
            left: index * kToggleIconWidth,
            top: 0,
            width: kToggleIconWidth,
            height: kToggleIconHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(
                  (trackRadius - kTogglePadding).clamp(0.0, trackRadius),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ],
      ),
    );
  }
}

/// 分段切换器里的单枚图标按钮。白底由轨道上的滑块提供，这里只负责图标和点击。
class SettingsToggleIcon extends StatelessWidget {
  const SettingsToggleIcon({
    super.key,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: kToggleIconWidth,
        height: kToggleIconHeight,
        child: Center(
          child: Icon(
            icon,
            size: 16,
            color: selected ? colors.primary : colors.inactive,
          ),
        ),
      ),
    );
  }
}
