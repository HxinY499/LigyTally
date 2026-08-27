import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_theme.dart';
import 'stats_design.dart';

/// 骨架屏色块：底色 + 左右扫过的高光。
///
/// 统计数据来自本地库的Stream，首帧通常没有数据。之前用「暂无数据」占位，
/// 会导致有数据时先闪一下空态文案，观感像出错。改成骨架屏后，
/// 加载态与空态在语义上彻底分开：骨架 = 还没到，空态 = 到了但没有。
class StatsSkeleton extends StatefulWidget {
  const StatsSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<StatsSkeleton> createState() => _StatsSkeletonState();
}

class _StatsSkeletonState extends State<StatsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            // -1 → 2 让高光完整扫过并留出间隔，不至于首尾相接显得抖动。
            final shift = -1.0 + _controller.value * 3.0;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(shift - 1, 0),
                  end: Alignment(shift, 0),
                  colors: [
                    stats.fillMuted,
                    stats.skeletonHighlight,
                    stats.fillMuted,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 图表区加载骨架：一排高低不等的竖条，形状上贴近真实图表。
class StatsChartSkeleton extends StatelessWidget {
  const StatsChartSkeleton({super.key, required this.height, this.bars = 7});

  final double height;
  final int bars;

  @override
  Widget build(BuildContext context) {
    // 固定比例数组而不是随机数：随机会导致每次重建高度跳动。
    const ratios = [0.45, 0.72, 0.38, 0.86, 0.56, 0.66, 0.5];
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < bars; i++)
            StatsSkeleton(
              width: 18,
              height: height * ratios[i % ratios.length],
              radius: 6,
            ),
        ],
      ),
    );
  }
}

/// 环形图区加载骨架：一个圆 + 右侧几行图例条。
class StatsDonutSkeleton extends StatelessWidget {
  const StatsDonutSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const StatsSkeleton(width: 132, height: 132, radius: 66),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == 3 ? 0 : 12),
                  child: StatsSkeleton(width: i.isEven ? 118 : 92, height: 11),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 空数据占位：淡色图标底座 + 标题 + 说明。
///
/// 和异常态用同一套骨架（[_StatsPlaceholder]），只换图标与配色，
/// 保证两种状态在视觉上是「同一家族」，不会让人以为是两套设计。
class StatsEmpty extends StatelessWidget {
  const StatsEmpty({
    super.key,
    required this.title,
    this.body,
    this.icon = FLucideIcons.chartNoAxesColumn,
    this.height = 168,
  });

  final String title;
  final String? body;
  final IconData icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return _StatsPlaceholder(
      height: height,
      icon: icon,
      iconColor: stats.textFaint,
      iconBackground: stats.fillMuted,
      title: title,
      body: body,
    );
  }
}

/// 异常占位：红色语义，附带可选重试。
class StatsError extends StatelessWidget {
  const StatsError({
    super.key,
    this.title = '数据加载失败',
    this.body,
    this.onRetry,
    this.height = 168,
  });

  final String title;
  final String? body;
  final VoidCallback? onRetry;
  final double height;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    final colors = context.colors;
    return _StatsPlaceholder(
      height: height,
      icon: FLucideIcons.triangleAlert,
      // 错误态走 danger：支出色可以被用户翻成绿的，绿色的报错图标很怪。
      iconColor: colors.danger,
      iconBackground: colors.dangerSoft,
      title: title,
      body: body,
      action: onRetry == null
          ? null
          : TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: stats.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(StatsTokens.radiusPill),
                ),
              ),
              child: const Text(
                '重新加载',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
    );
  }
}

class _StatsPlaceholder extends StatelessWidget {
  const _StatsPlaceholder({
    required this.height,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    this.body,
    this.action,
  });

  final double height;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final stats = StatsTokens.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 21, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(title, style: stats.emptyTitle),
          if (body != null) ...[
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                body!,
                textAlign: TextAlign.center,
                style: stats.emptyBody,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

/// Stream 三态渲染器：加载 / 异常 / 数据。
///
/// 统计页有 5 处StreamBuilder，如果每处都手写
/// `snapshot.hasError ? ... : snapshot.hasData ? ... : ...`，
/// 很容易漏掉某一态（原实现就是全部用 `?? const []` 兜底，
/// 于是加载中和空数据都显示「暂无数据」，异常则被完全吞掉）。
/// 收敛到这里后，三态在所有卡片上行为一致。
///
/// ## 换了一份数据也算「换态」
///
/// 切换支出/收入这类口径时，卡片换的是 [stream] 本身。这条路径上**不会**
/// 经过加载态：[StreamBuilder] 换 stream 时走 `afterDisconnected`，那个方法
/// 只改 `connectionState`、**保留旧的 data**，所以旧内容会一直挂在屏幕上，
/// 直到新 stream 吐出第一份数据的那一帧整块换掉。
///
/// 于是三态之间明明有淡入淡出，口径切换却是硬切——因为数据态的 key 是个常量，
/// [AnimatedSwitcher] 把它当成「同一个 child 更新了」。[dataKey] 就是来补这
/// 一刀的：调用点把「谁在决定这份数据」交进来，key 跟着它变，切口径才有过渡。
class StatsStreamBuilder<T> extends StatelessWidget {
  const StatsStreamBuilder({
    super.key,
    required this.stream,
    required this.loading,
    required this.builder,
    this.dataKey,
    this.errorHeight = 168,
  });

  final Stream<T> stream;

  /// 加载骨架。
  final Widget loading;

  /// 拿到数据后的渲染（空数据判断交给业务侧，它才知道什么算空）。
  final Widget Function(BuildContext context, T data) builder;

  /// 这份数据的「身份」：变了就当成换了一份数据，做一次淡入淡出。
  ///
  /// 传当前口径（支出/收入/结余）即可。**不要**把随时间连续变动的东西传进来
  /// （比如金额合计）——那会让每次数据刷新都闪一下。
  ///
  /// 为空表示「这张卡的数据没有口径之分」，行为与加入本参数之前一致。
  final Object? dataKey;

  final double errorHeight;

  @override
  Widget build(BuildContext context) {
    // 统计页其余动效时长都是 StatsTokens 里的静态常量，不受「动效强度」设置
    // 影响。这一处过渡覆盖的是整块卡片内容，是全页最大的一次视觉变动，
    // 选了「关闭」还看到它在淡入淡出会显得开关失灵，所以走 motion。
    final motion = context.motion;
    final duration = motion(StatsTokens.durTap);
    final curve = motion.curve(StatsTokens.curveEnter);
    return StreamBuilder<T>(
      stream: stream,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.hasError) {
          child = KeyedSubtree(
            key: const ValueKey('error'),
            child: StatsError(body: '${snapshot.error}', height: errorHeight),
          );
        } else if (snapshot.data case final data?) {
          child = KeyedSubtree(
            key: ValueKey(('data', dataKey)),
            child: builder(context, data),
          );
        } else {
          child = KeyedSubtree(key: const ValueKey('loading'), child: loading);
        }
        // 动效关闭档整段跳过，不是「时长设成 0」。
        //
        // 后者会崩：`RenderAnimatedSize` 在自己的 performLayout 里启动控制器，
        // 零时长的控制器**同步**跑完并回调监听者，于是 markNeedsLayout 落在
        // 自身布局期间，撞上「RenderObject 不得在自身布局期间再次置脏」。
        if (motion.isOff) return child;
        // 三态与「换口径」之间淡入淡出。key 必须随状态改变，否则 AnimatedSwitcher
        // 会当成「同一个 child 更新」而硬切，动画根本不触发。
        //
        // 外面那层 [AnimatedSize] 是给两张**变高**的卡（分类构成、分类变化）
        // 收尾的：淡入淡出期间 AnimatedSwitcher 的 Stack 按新旧内容的最大值
        // 定尺，旧内容被移除的那一刻高度会掉下来——分类构成从 6 行支出切到
        // 1 行收入要掉三百多像素，卡片下方的整块内容跟着往上一跳。
        //
        // 于是这两段动画是**先后**跑的：先 220ms 交叉溶解，再 220ms 收高度，
        // 总共约 440ms。想让它们并行，就得让 Stack 只按新内容定尺，而那需要
        // 把旧内容改成定位子节点——[Positioned] 只能给出无界高度，卡里凡是
        // 用了 [Expanded] 的地方（周期对比卡就是）会直接触发布局断言。
        // 多花一段收尾时间换布局安全，是这里刻意做的取舍。
        //
        // 两张定高的图表卡（趋势 176、周期对比 196）压根不经过这一段，
        // 它们的高度由外面的 SizedBox 钉死。
        return AnimatedSize(
          duration: duration,
          curve: curve,
          // 顶边对齐：卡片从上往下读，高度变化该让底边动、顶边不动。
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: curve,
            // 淡出必须用 easeIn，不能和淡入共用同一条 easeOutCubic。
            //
            // AnimatedSwitcher 让退场的那一份倒着跑控制器，再把曲线原样套上：
            // easeOutCubic 在 0.55 处是 0.91，也就是过渡走完一半时旧内容还有
            // 九成不透明度，最后几十毫秒骤降——观感是「旧的赖着不走，然后忽然
            // 消失」。easeIn 在 0.55 处只有 0.17，旧的先退、新的接上，
            // 才叠得出一次真正的交叉溶解。
            switchOutCurve: motion.curve(Curves.easeIn),
            child: child,
          ),
        );
      },
    );
  }
}
