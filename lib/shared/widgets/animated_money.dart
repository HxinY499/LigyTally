import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

/// 逐位动画的默认时长。
///
/// 240ms 是「看得出动过、又不用等」的下限附近。这里刻意比统计页图表的
/// 520ms 短一半多：那边补间的是**一条曲线的形状**，眼睛要跟着走完才知道
/// 趋势变了；这里每一位只走**一步**（旧字形 → 新字形），走完就没有新信息了，
/// 拖长只是让人多等。
const kMoneyDigitDuration = Duration(milliseconds: 240);

/// 金额里的一段文本。
///
/// [animate] 为 false 的段整段直接换掉（货币符号、正负号这类不该逐位翻的
/// 东西）；为 true 的段按**字符**拆开，每个数字位各自动画。
@immutable
class MoneySegment {
  const MoneySegment(this.text, {required this.style, this.animate = false});

  final String text;
  final TextStyle style;
  final bool animate;
}

/// 金额文本：数值变化时**每一位数字直接翻到它的真实值**。
///
/// ## 和「数值补间」的区别
///
/// 这个组件替掉的上一版是对**分值**做补间：`0 → 242818` 中间经过几十个无意义
/// 的数（`0 → 1.37 → 96.02 → …`），所有位一起乱转，520ms 之后才停在真值上。
///
/// 那个做法在「换月份」这种场景下还说得过去（两个数之间的滚动能表达"变了"），
/// 但它在**打开首页**时暴露了：账单流的首帧没有数据，卡片先渲染 `0.00`，
/// 真实数据到达时就从 0 数上去。也就是说每次进首页都要等半秒才能读到本月支出
/// ——而那正是用户打开这一屏的唯一目的。
///
/// 现在改成逐位：`4` 直接变成 `8`，不经过 `5 6 7`。每一位只走一步，
/// 总时长因此只由动画本身决定（[kMoneyDigitDuration]），和数字大小无关。
///
/// ## 为什么按「从右数第几位」给 key
///
/// 位数会变（`999.99` → `1,234.00`）。如果按从左数的下标给 key，前面插进一位
/// 就会让**所有**位的 key 平移一格，于是每一位都被当成"换了字符"，整排一起
/// 重新动画，看起来像在洗牌。
///
/// 按从右数的位置给 key，个位永远是个位：已有的位各自翻到新值，只有新增的
/// 高位是全新的格子。金额的小数部分恒为两位，所以千分位逗号也落在固定的
/// 从右位置（6、10、14…），跟着一起稳住。
///
/// ## 读屏
///
/// 逐位拆开之后，这串数字在语义树上不再是一个字符串，读屏会一个字符一个字符
/// 念。所以整体套一层 [Semantics] 给出完整文本并屏蔽子节点语义。测试也靠这个
/// 标签定位，不必去拼一堆 [Text]。
class AnimatedMoneyText extends StatelessWidget {
  const AnimatedMoneyText({
    super.key,
    required this.segments,
    this.duration = kMoneyDigitDuration,
  });

  final List<MoneySegment> segments;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final resolved = context.motion(duration);
    final children = <Widget>[];
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (segment.text.isEmpty) continue;
      if (!segment.animate || resolved == Duration.zero) {
        children.add(Text(segment.text, style: segment.style));
        continue;
      }
      children.addAll(_cells(segment, index, resolved));
    }

    return Semantics(
      label: segments.map((segment) => segment.text).join(),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        // 同一行里有两种字号（小号货币符号 + 大号数字），必须按基线对齐，
        // 否则小的那个会挂在行的垂直中间。
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: children,
      ),
    );
  }

  List<Widget> _cells(MoneySegment segment, int segmentIndex, Duration length) {
    final chars = segment.text.split('');
    return [
      for (var i = 0; i < chars.length; i++)
        _DigitCell(
          // 从右数的位置，见类文档。段下标一起进 key，避免两个动画段之间串位。
          key: ValueKey('money-$segmentIndex-${chars.length - 1 - i}'),
          char: chars[i],
          style: segment.style,
          duration: length,
        ),
    ];
  }
}

/// 一个字符位。
///
/// 只有**数字**才动画：逗号和小数点在右对齐下位置固定，不会换字符，给它们
/// 套一层 [AnimatedSwitcher] 只是白付渲染；而万一真换了（位数跨越千分位时
/// 新增的那个逗号），它落在一个全新的格子里，本来也不该有过渡。
class _DigitCell extends StatefulWidget {
  const _DigitCell({
    super.key,
    required this.char,
    required this.style,
    required this.duration,
  });

  final String char;
  final TextStyle style;
  final Duration duration;

  @override
  State<_DigitCell> createState() => _DigitCellState();
}

/// 位移幅度，占字号的比例。
///
/// 刻意很小：一格只有一个字符宽、一行高，大幅位移会滑出行外压到相邻内容。
const _kGlyphShift = 0.34;

class _DigitCellState extends State<_DigitCell>
    with SingleTickerProviderStateMixin {
  /// 起始值是 1（终点）而不是 0。
  ///
  /// 首次出现不做入场动画：首页的账单流首帧没有数据，卡片先渲染 `0.00`，
  /// 如果连这一帧都要动，用户会看到「数字滑进来」紧接着「数字翻一次」两段
  /// 动作，读起来像闪了一下。新增的高位格子同理直接出现。
  late final AnimationController _controller = AnimationController(
    duration: widget.duration,
    vsync: this,
    value: 1,
  );

  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  /// 正在退场的旧字形。null 表示这一格此刻是静止的。
  String? _outgoing;

  @override
  void initState() {
    super.initState();
    // 动画走完就把旧字形摘掉，让这一格回到「一个字符一个 Text」的静止形态。
    // 不摘的话它会一直挂在树上（透明度为 0），白付一次绘制。
    _controller.addStatusListener((status) {
      if (status != AnimationStatus.completed || _outgoing == null) return;
      setState(() => _outgoing = null);
    });
  }

  /// 这里刻意**不**用 AnimatedSwitcher。
  ///
  /// 它没法区分「首次出现」和「字符变了」：初始 child 也会被播一次入场动画。
  /// 想绕开就只能首帧先渲染裸 [Text]、之后再换成 AnimatedSwitcher——而那一换
  /// 会让第一次变化时旧字形压根不在 switcher 里，于是只有新数字淡入、旧数字
  /// 瞬间消失，观感是闪一下而不是交叉溶解。自己拿一个控制器反而更短更准。
  @override
  void didUpdateWidget(_DigitCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (oldWidget.char == widget.char) return;
    if (widget.duration == Duration.zero) {
      _outgoing = null;
      _controller.value = 1;
      return;
    }
    _outgoing = oldWidget.char;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isDigit =>
      widget.char.codeUnitAt(0) >= 0x30 && widget.char.codeUnitAt(0) <= 0x39;

  @override
  Widget build(BuildContext context) {
    final glyph = Text(widget.char, style: widget.style);
    final outgoing = _outgoing;
    if (outgoing == null || !_isDigit) return glyph;

    final shift = (widget.style.fontSize ?? 16) * _kGlyphShift;
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final t = _progress.value;
        // 两个字形同向往上走：旧的从原位升出去，新的从下方升进来。
        // 反向（旧的往下退）会读成「旧值缩回去」，不像一次翻位。
        return Stack(
          alignment: Alignment.center,
          children: [
            _shifted(Text(outgoing, style: widget.style), -shift * t, 1 - t),
            _shifted(glyph, shift * (1 - t), t),
          ],
        );
      },
    );
  }

  Widget _shifted(Widget child, double dy, double opacity) => Opacity(
    opacity: opacity.clamp(0.0, 1.0),
    child: Transform.translate(offset: Offset(0, dy), child: child),
  );
}
