import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/preferences/accent_color.dart';
import '../../../core/theme/app_accent.dart';
import '../../../core/theme/app_theme.dart';
import '../../statistics/presentation/stats_design.dart';

/// 强调色选择浮层：预览带 + 一排色点，点选即生效。
///
/// 不做「确定」——主题色是即时观感，二次确认只会让人来回对比时多点一次。
/// 关闭走下滑或点遮罩，和背景模糊浮层同一条交互。
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
              '主题色',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: colors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '用于按钮、选中态和统计图表，不影响收支颜色',
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: _Preview(),
            ),
            const SizedBox(height: 20),
            // 色点排在预览下方：拇指落在这里点，视线在上面看结果，手不挡视野。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 12,
                children: [
                  for (final accent in AppAccent.values)
                    SizedBox(
                      width: 96,
                      child: _AccentSwatch(
                        accent: accent,
                        selected: accent == selected,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref
                              .read(appAccentProvider.notifier)
                              .setAccent(accent);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
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
      // 必须裁剪：底栏是通栏贴底的方角，不裁会画到 16 圆角外面去。
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: BorderRadius.circular(16),
      ),
      // 描边不是装饰：底栏用的 surface 和浮层自己的底色是同一个值，
      // 没有这条边界，底栏在深浅两套皮肤下都会整块融进浮层，
      // 「选中态长在一条栏里」这个信息就丢了。
      //
      // 走 foregroundDecoration 而不是 decoration.border：后者画在子节点
      // **下面**，会被贴到边的底栏盖掉三条边，只剩顶边看得见。
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
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
              borderRadius: BorderRadius.circular(StatsTokens.radiusCard),
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
