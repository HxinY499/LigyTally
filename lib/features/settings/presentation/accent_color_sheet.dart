import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/preferences/accent_color.dart';
import '../../../core/theme/app_accent.dart';
import '../../../core/theme/app_theme.dart';
import '../../statistics/presentation/stats_design.dart';

/// 强调色选择浮层：预览带 + 一排预设色点 + 色相 / 浓淡两条滑杆。
///
/// 不做「确定」——主题色是即时观感，二次确认只会让人来回对比时多点一次。
/// 关闭走下滑或点遮罩，和背景模糊浮层同一条交互。
///
/// 预设和滑杆并存而不是二选一：多数时候人只想一眼挑个不难看的（点色点），
/// 想要某支特定颜色时才会去调滑杆。两者共享同一个选中值，点完预设接着拖，
/// 滑杆就从那支预设的位置起步。
///
/// 必须带预览，理由同 `backdrop_blur_sheet`：观感类参数没有预览就只能
/// 反复退出去比对。而主题色比模糊度更需要——浮层占住下半屏、遮罩压暗页面之后，
/// 主色真正的出场面积（Hero 卡、底栏选中态、FAB）一处都不在视野里，
/// 不给预览等于让人盲选。
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
            // 预览挂一份**按当前选中值现算**的色板，而不是等全局主题过渡完。
            // MaterialApp 换主题要走 200ms 淡变，拖色相条时预览会一路拖在滑块
            // 后面；这里直接覆盖 extensions，预览即时跟手，页面在后面追。
            Theme(
              data: Theme.of(context).copyWith(
                extensions: [AppColors.resolve(colors.brightness, selected)],
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _Preview(),
              ),
            ),
            const SizedBox(height: 18),
            // 色点排在预览下方：拇指落在这里点，视线在上面看结果，手不挡视野。
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
    // 深浅（预设是手挑的，自选钉在预设的平均亮度上），芯要和预览里的 FAB 同色。
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

/// 预览带：主色出场面积最大的三处——统计页 Hero 卡、底栏选中态、记一笔 FAB。
///
/// 三样都读**实时主题**而不是自己拼近似色：Hero 渐变直接取
/// [StatsTokens.heroGradient]，就是统计页那一份。所以点色点之后这里会跟着
/// 整个 app 一起做 200ms 主题过渡，看到的就是真实结果。
///
/// 外层铺 [AppColors.canvas] 而不是留白：卡片靠阴影从页底浮起来的关系
/// 也是主色的一部分（[StatsTokens.shadowHero] 带主色调），
/// 压在白面浮层上会看不出来。
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final stats = StatsTokens.of(context);
    return Container(
      // 必须裁剪：底栏是通栏贴底的方角，不裁会画到圆角外面去。
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: context.radii.cardAll,
      ),
      // 描边不是装饰：底栏用的 surface 和浮层自己的底色是同一个值，
      // 没有这条边界，底栏在深浅两套皮肤下都会整块融进浮层，
      // 「选中态长在一条栏里」这个信息就丢了。
      //
      // 走 foregroundDecoration 而不是 decoration.border：后者画在子节点
      // **下面**，会被贴到边的底栏盖掉三条边，只剩顶边看得见。
      foregroundDecoration: BoxDecoration(
        borderRadius: context.radii.cardAll,
        border: Border.all(color: colors.line),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
            decoration: BoxDecoration(
              gradient: stats.heroGradient,
              borderRadius: BorderRadius.circular(stats.radiusCard),
              boxShadow: stats.shadowHero,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('本期支出', style: StatsTokens.heroLabel),
                const SizedBox(height: 4),
                // 字号比真卡的 38 小，但字色与字重照搬：预览要如实反映
                // 白字压在这支渐变上到底够不够看。
                const Text(
                  '1,286.40',
                  style: TextStyle(
                    fontSize: 24,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: StatsTokens.onHeroPrimary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Container(height: 1, color: StatsTokens.onHeroDivider),
                const SizedBox(height: 9),
                Row(
                  children: [
                    const Text('本期收入', style: StatsTokens.heroLabel),
                    const Spacer(),
                    Text(
                      '3,400.00',
                      style: StatsTokens.heroMini.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // FAB 压在底栏上沿，与首页 centerFloat 的位置关系一致。
          SizedBox(
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border(top: BorderSide(color: colors.lineSoft)),
                    ),
                    child: Row(
                      children: const [
                        Expanded(
                          child: _PreviewTab(
                            icon: FLucideIcons.receiptText,
                            label: '明细',
                            selected: true,
                          ),
                        ),
                        Expanded(
                          child: _PreviewTab(
                            icon: FLucideIcons.chartPie,
                            label: '统计',
                          ),
                        ),
                        Expanded(
                          child: _PreviewTab(
                            icon: FLucideIcons.settings2,
                            label: '设置',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  child: Container(
                    width: 34,
                    height: 34,
                    // 不加阴影：真 FAB 的浮起来自 Material elevation，
                    // 这里照搬会变成手写一份阴影值。它压在底栏发丝线上，
                    // 光靠这层遮挡关系就够读出「浮在栏上方」。
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      FLucideIcons.plus,
                      size: 17,
                      // 同 home_shell：深色下提亮的主色压白字对比不够。
                      color: colors.isDark ? colors.canvas : Colors.white,
                    ),
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

/// 预览里的单个 tab，比例照首页底栏缩小。
class _PreviewTab extends StatelessWidget {
  const _PreviewTab({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? colors.primary : colors.inactive;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 8.5,
            height: 1.1,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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
