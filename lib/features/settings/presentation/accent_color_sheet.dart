import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/preferences/accent_color.dart';
import '../../../core/theme/app_accent.dart';
import '../../../core/theme/app_theme.dart';

/// 强调色选择浮层：一排预设色点 + 色相 / 浓淡两条滑杆。
///
/// 不做「确定」——主题色是即时观感，二次确认只会让人来回对比时多点一次。
/// 关闭走下滑或点遮罩，和背景模糊浮层同一条交互。
///
/// 预设和滑杆并存而不是二选一：多数时候人只想一眼挑个不难看的（点色点），
/// 想要某支特定颜色时才会去调滑杆。两者共享同一个选中值，点完预设接着拖，
/// 滑杆就从那支预设的位置起步。
///
/// 浮层里不再自带预览：外观页顶部已经有一张共享样张，浮层变矮之后
/// 那张样张还露在上面，跟着选色一起变。再画一份等于两处各演各的。
Future<void> showAccentColorSheet(BuildContext context) {
  return showFSheet<void>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (sheetContext) => const _AccentColorSheet(),
  );
}

class _AccentColorSheet extends ConsumerWidget {
  const _AccentColorSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final selected = ref.watch(appAccentProvider);
    return Material(
      color: colors.surface,
      borderRadius: context.radii.sheetTop,
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
              '主题色',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final accent in AppAccent.values)
                    _AccentSwatch(
                      accent: accent,
                      selected: accent == selected.preset,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref
                            .read(appAccentProvider.notifier)
                            .setAccent(AccentChoice.preset(accent));
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: _CustomStrips(selected: selected),
            ),
          ],
        ),
      ),
    );
  }
}

/// 色相 / 浓淡两条渐变滑杆。
///
/// 只开这两维，第三维（深浅）由 [customAccentPrimary] 钉死——理由见那里。
/// 拖动过程走 `previewAccent` 不落盘，松手才写偏好。
class _CustomStrips extends ConsumerWidget {
  const _CustomStrips({required this.selected});

  final AccentChoice selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = context.colors.brightness;
    final hue = selected.hue;
    final saturation = selected.saturation;
    // 滑块芯取**当前真正生效的主色**而不是轨道上那一点：选中预设时两者差一点
    // 深浅（预设是手挑的，自选钉在预设的平均亮度上），芯要和页面上真正用的主色同色。
    final thumb = selected.primaryOf(brightness);

    Color at({double? withHue, double? withSaturation}) => customAccentPrimary(
      hue: withHue ?? hue,
      saturation: withSaturation ?? saturation,
      brightness: brightness,
    );

    void emit(AccentChoice choice, {required bool done}) {
      final notifier = ref.read(appAccentProvider.notifier);
      if (done) {
        HapticFeedback.selectionClick();
        notifier.setAccent(choice);
      } else {
        notifier.previewAccent(choice);
      }
    }

    return Column(
      children: [
        _ColorStrip(
          label: '色相',
          // 轨道按 30° 采样，且每一停都过一遍真正的解析函数：轨道上看到的
          // 颜色就是选中后拿到的颜色。拿「满饱和度的标准色环」当轨道最省事，
          // 但那条彩虹里的亮黄一选下去就变成暗金，等于骗人。
          // 采到 360 而不是 330，首尾都落在红上，两端才接得上。
          track: [for (var h = 0; h <= 360; h += 30) at(withHue: h.toDouble())],
          value: hue / 360,
          thumb: thumb,
          onChanged: (fraction, done) => emit(
            AccentChoice.custom(hue: fraction * 360, saturation: saturation),
            done: done,
          ),
        ),
        const SizedBox(height: 14),
        _ColorStrip(
          label: '浓淡',
          track: [
            for (var i = 0; i <= 6; i++)
              at(
                withSaturation:
                    kAccentMinSaturation + (1 - kAccentMinSaturation) * (i / 6),
              ),
          ],
          value:
              ((saturation - kAccentMinSaturation) / (1 - kAccentMinSaturation))
                  .clamp(0.0, 1.0),
          thumb: thumb,
          onChanged: (fraction, done) => emit(
            AccentChoice.custom(
              hue: hue,
              saturation:
                  kAccentMinSaturation + (1 - kAccentMinSaturation) * fraction,
            ),
            done: done,
          ),
        ),
      ],
    );
  }
}

/// 一条渐变轨道 + 一个圆滑块。
///
/// 没用 Material [Slider]：它的轨道只能是两段实色（active / inactive），
/// 而这里「轨道本身就是取色盘」——把当前值涂在轨道上，人不用先拖再看结果。
class _ColorStrip extends StatelessWidget {
  const _ColorStrip({
    required this.label,
    required this.track,
    required this.value,
    required this.thumb,
    required this.onChanged,
  });

  final String label;
  final List<Color> track;

  /// 归一化位置，0–1。
  final double value;

  /// 滑块中心色：当前选中的实际主色。
  final Color thumb;

  /// [done] 为 true 表示手指离开，可以落盘了。
  final void Function(double fraction, bool done) onChanged;

  static const _thumbSize = 26.0;
  static const _trackHeight = 14.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.muted,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              // 滑块中心要能走到轨道两端，所以轨道左右各内缩半个滑块，
              // 行程按内缩后的宽度算——否则拖到最右边取不到 360°。
              final travel = box.maxWidth - _thumbSize;
              void report(double dx, {required bool done}) {
                if (travel <= 0) return;
                onChanged(
                  ((dx - _thumbSize / 2) / travel).clamp(0.0, 1.0),
                  done,
                );
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                // 点一下直接跳到该位置：滑杆很短，非要拖才动会很别扭。
                onTapDown: (d) => report(d.localPosition.dx, done: false),
                onTapUp: (d) => report(d.localPosition.dx, done: true),
                // onStart 必须接：拖动赢下手势竞争的那一次移动只走 onStart，
                // 不会再补一次 onUpdate（DragStartBehavior.start 把它折进了
                // 起点）。只接 onUpdate 的话，快速拖动的头一段会被整段吞掉。
                onHorizontalDragStart: (d) =>
                    report(d.localPosition.dx, done: false),
                onHorizontalDragUpdate: (d) =>
                    report(d.localPosition.dx, done: false),
                onHorizontalDragEnd: (_) =>
                    onChanged(value.clamp(0.0, 1.0), true),
                child: SizedBox(
                  height: _thumbSize,
                  child: Stack(
                    children: [
                      Positioned(
                        left: _thumbSize / 2,
                        right: _thumbSize / 2,
                        top: (_thumbSize - _trackHeight) / 2,
                        height: _trackHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: track),
                            borderRadius: BorderRadius.circular(
                              _trackHeight / 2,
                            ),
                            border: Border.all(color: colors.lineSoft),
                          ),
                        ),
                      ),
                      Positioned(
                        left: value.clamp(0.0, 1.0) * travel,
                        child: Container(
                          width: _thumbSize,
                          height: _thumbSize,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.line),
                            boxShadow: colors.shadowCard,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: thumb,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AppAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final swatch = accent.primaryOf(colors.brightness);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: swatch,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colors.ink : colors.line,
                width: selected ? 2.5 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: selected
                ? Icon(
                    FLucideIcons.check,
                    size: 18,
                    color: colors.isDark ? colors.canvas : Colors.white,
                  )
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            accent.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colors.ink : colors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
