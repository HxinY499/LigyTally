import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/color_luminance.dart';

/// 统计页设计令牌：配色、圆角、阴影、字阶、动效时长。
///
/// 统计页是全应用「图表密度最高」的一屏，颜色和字号一旦各处硬编码，
/// 很快就会失控（同一种灰出现四个色值、同一级标题三种字号）。
/// 所以本文件是统计页唯一的样式源：页面与图表组件只引用这里的令牌，
/// 不再就地写 `Color(0xFF...)` 或 `fontSize: 13`。
///
/// 基色仍然复用 [AppColors]（品牌蓝 / 支出红 / 收入绿），
/// 这里只做「统计场景专用」的扩展：图表配色梯度、卡片阴影、数字字阶。
///
/// ## 为什么颜色是实例成员、几何是静态成员
///
/// 深浅两套皮肤只影响颜色和带颜色的字阶，圆角 / 间距 / 时长在两套皮肤下
/// 完全一致。把后者留作 `static const`，调用点（`StatsTokens.gutter`、
/// `const EdgeInsets.all(StatsTokens.gapCard)`）可以继续写在 const 表达式里；
/// 只有颜色相关的令牌需要 `StatsTokens.of(context)` 先解析亮度。
class StatsTokens {
  const StatsTokens._(this._colors, this._chart);

  /// 解析当前亮度下的统计令牌。
  ///
  /// 颜色一律从 [AppColors] 转发，而不是自己再存一份——主题过渡动画里
  /// [AppColors] 是插值出来的中间态，自己存一份会导致统计页在过渡途中
  /// 和其它页面差半拍。
  static StatsTokens of(BuildContext context) {
    final colors = AppColors.of(context);
    return StatsTokens._(colors, colors.isDark ? _chartDark : _chartLight);
  }

  final AppColors _colors;
  final _StatsChartColors _chart;

  // ---------------------------------------------------------------- 圆角

  /// 卡片圆角。比全局 8更大，让密集图表区显得舒展、现代。
  static const radiusCard = 20.0;

  /// 卡片内小块（分段轨道、徽章、图标底座）圆角。
  static const radiusInner = 12.0;

  ///胶囊圆角：分段选择器滑块、徽章。
  static const radiusPill = 999.0;

  // ---------------------------------------------------------------- 间距

  /// 页面左右安全边距。
  static const gutter = 16.0;

  /// 卡片之间的垂直间距。
  static const gapCard = 14.0;

  /// 卡片内边距。
  static const padCard = EdgeInsets.fromLTRB(18, 18, 18, 18);

  // ---------------------------------------------------------------- 阴影

  /// 卡片阴影。转发到 [AppColors.shadowCard]——阴影是全应用统一的视觉语言，
  /// 记账页日卡与统计页图表卡必须浮起在同一高度，所以不在这里另开一份。
  List<BoxShadow> get shadowCard => _colors.shadowCard;

  /// 概览 Hero 卡阴影：带主色调的彩色阴影，比中性灰更有「发光感」。
  List<BoxShadow> get shadowHero => _colors.shadowHeroPrimary;

  // ---------------------------------------------------------------- 颜色

  /// Hero 卡渐变：手挑的三色停转到主题色的色相上，**并保住原有的相对亮度**。
  ///
  /// 两条都必须做到：
  /// - 不能「从 [AppColors.primary] 沿明度轴现算」。手挑的色停是边压暗边
  ///   降饱和的（浅色饱和度从 0.86 收到 0.65），只挪明度会得到一支电光蓝，
  ///   深色那套刻意压暗（深页面里高亮卡会刺眼）也一起丢掉。
  /// - 不能只转色相。HSL 明度相同时青色比蓝色亮得多，纯转色相会让青色主题
  ///   下的白字压在 #6BF7ED 上，对比度从 2.56 掉到 1.30，等于看不见。
  ///
  /// 所以转完色相再沿明度轴二分回原色停的相对亮度：这张卡上的白字
  /// （[onHeroPrimary] 那一族）对比度与选了哪个主题色无关。
  LinearGradient get heroGradient {
    final rotation = _hueRotation;
    final source = _chart.heroGradient;
    if (rotation == 0) return source;
    return LinearGradient(
      begin: source.begin,
      end: source.end,
      colors: [
        for (final stop in source.colors)
          withRelativeLuminance(
            _rotate(stop, rotation),
            relativeLuminance(stop),
          ),
      ],
      stops: source.stops,
    );
  }

  /// Hero 卡上的次级文字（标签、说明）：白色降透明度，
  /// 比直接给一个灰色更干净——灰色压在彩色卡面上会发浊。
  ///
  /// Hero 卡在任何主题色下都是同一支色相的深浅渐变，
  /// 所以这四个值既不随亮度也不随主题色变化。
  static const onHeroPrimary = Colors.white;
  static const onHeroSecondary = Color(0xCCFFFFFF);
  static const onHeroTertiary = Color(0x99FFFFFF);
  static const onHeroDivider = Color(0x33FFFFFF);

  /// 卡片面色/ 页面底色。
  Color get surface => _colors.surface;
  Color get canvas => _colors.canvas;

  /// 文字三级灰阶。统计页只用这三档，不再引入第四种灰。
  Color get textStrong => _colors.ink;
  Color get textMuted => _chart.textMuted;
  Color get textFaint => _chart.textFaint;

  /// 图表网格线/ 分割线：比 [AppColors.line] 更淡，
  /// 避免密集横线把图表压成「格子纸」。
  Color get gridLine => _chart.gridLine;
  Color get divider => _chart.divider;

  /// 中性填充：分段轨道底、进度条槽、骨架屏。
  Color get fillMuted => _chart.fillMuted;

  /// 骨架屏扫光的高光色，只比 [fillMuted] 亮一档。
  ///
  /// 必须单列一个令牌而不是复用 [fillMuted]：三个色停取同一个值时渐变会
  /// 退化成纯色，那条来回扫的高光会彻底消失，只剩一个静止的灰块。
  Color get skeletonHighlight => _chart.skeletonHighlight;

  /// tooltip 深底。深色皮肤下改用更亮的面色，否则深底压深页面看不出层次。
  Color get tooltip => _chart.tooltip;

  /// tooltip 文字色：跟着 [tooltip] 底色取反，不能固定白色。
  Color get onTooltip => _chart.onTooltip;

  /// 支出 / 收入语义色（沿用全局，转出别名便于图表内直接引用）。
  Color get expense => _colors.expense;
  Color get income => _colors.income;
  Color get primary => _colors.primary;

  // ---------------------------------------------------------------- 图表配色

  /// 分类环形图配色。
  ///
  /// 选色原则：色相尽量拉开（蓝 → 橙 → 青 → 珊瑚 → 紫 → 天蓝），
  /// 明度与饱和度保持在同一档，避免某一片「跳出来」抢视觉。
  ///
  /// 整条调色板跟着主题色**转色相**（见 [_hueRotation]）：第一片是最大的
  /// 分类，占的面积最多，固定成蓝色的话，换成橙色主题后同一屏里会出现
  /// 「橙 Hero 卡 + 蓝色主片」两个主色。旋转而不是只换第一片，是因为
  /// 只换第一片会撞上后面固定的橙 / 青——整条一起转才保住相对间距。
  List<Color> get categoryPalette {
    final rotation = _hueRotation;
    return [
      for (final color in _chart.categoryPalette) _rotate(color, rotation),
    ];
  }

  /// 「其他」聚合项固定用低饱和灰蓝，视觉上自然退到后面。
  ///
  /// 不跟着转色相：它的饱和度本来就压到最低，转了看不出差别，
  /// 而「退到后面」正是它唯一的职责。
  Color get categoryRest => _chart.categoryRest;

  /// 取第 [index] 个分类色；超出调色板长度时回落到 [categoryRest]，
  /// 而不是循环取色——循环会让第 7 项和第 1 项同色，图例失去区分度。
  ///
  /// 只转要用的那一个，不走 [categoryPalette]：这个方法在每片扇形和每行
  /// 图例上都会调一次，整条转一遍再取下标是 O(n²) 次色彩空间换算。
  Color categoryColor(int index) {
    final palette = _chart.categoryPalette;
    if (index >= palette.length) return categoryRest;
    return _rotate(palette[index], _hueRotation);
  }

  /// 趋势折线：主色渐变（左浅右深），比单色更有纵深。
  LinearGradient get trendLineGradient =>
      _rotateGradient(_chart.trendLineGradient);

  /// 趋势折线下方面积填充：主色到透明。
  LinearGradient get trendAreaGradient =>
      _rotateGradient(_chart.trendAreaGradient);

  /// 柱状图当期高亮柱渐变。
  LinearGradient get barActiveGradient =>
      _rotateGradient(_chart.barActiveGradient);

  /// 柱状图历史柱：低饱和主色，和高亮柱形成明确主次。
  Color get barIdle => _rotate(_chart.barIdle, _hueRotation);

  /// 当前主色相对**默认主色**的色相偏移量（度）。
  ///
  /// 锚点取同一亮度下的默认色板，所以默认主题的偏移恒为 0，
  /// 所有手挑色值原样返回。
  double get _hueRotation {
    final anchor = _colors.isDark
        ? AppColors.dark.primary
        : AppColors.light.primary;
    return HSLColor.fromColor(_colors.primary).hue -
        HSLColor.fromColor(anchor).hue;
  }

  /// 转色相，饱和度、明度、透明度全部保持原样。
  ///
  /// 只动色相是为了保住原手挑色值里的明度 / 饱和度走势；
  /// 全透明的色停（面积填充的末端）转完仍然全透明。
  Color _rotate(Color color, double rotation) {
    if (rotation == 0) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl.withHue((hsl.hue + rotation) % 360).toColor();
  }

  LinearGradient _rotateGradient(LinearGradient gradient) {
    final rotation = _hueRotation;
    if (rotation == 0) return gradient;
    return LinearGradient(
      begin: gradient.begin,
      end: gradient.end,
      colors: [for (final c in gradient.colors) _rotate(c, rotation)],
      stops: gradient.stops,
    );
  }

  /// 柱状图背景轨道：给每根柱一个浅槽，柱子矮时也不会「悬空」。
  Color get barTrack => _chart.barTrack;

  // ---------------------------------------------------------------- 字阶

  /// 页面内区块标题（卡片标题）。
  TextStyle get titleSection => TextStyle(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: textStrong,
    letterSpacing: 0.1,
  );

  /// 卡片标题下的补充说明。
  TextStyle get captionSection => TextStyle(
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: textFaint,
  );

  /// Hero 卡主数字。
  static const heroAmount = TextStyle(
    fontSize: 38,
    height: 1.08,
    fontWeight: FontWeight.w800,
    color: onHeroPrimary,
    letterSpacing: 0.4,
  );

  /// Hero 卡次级数字（收入 / 净收支 / 日均）。
  static const heroMini = TextStyle(
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: onHeroPrimary,
    letterSpacing: 0.2,
  );

  /// Hero 卡标签。
  static const heroLabel = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: onHeroSecondary,
    letterSpacing: 0.2,
  );

  /// 环形图中心金额。
  TextStyle get donutCenterAmount => TextStyle(
    fontSize: 17,
    height: 1.15,
    fontWeight: FontWeight.w800,
    color: textStrong,
    letterSpacing: 0.2,
  );

  /// 图表坐标轴刻度。
  TextStyle get axisLabel => TextStyle(
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w500,
    color: textFaint,
  );

  /// 坐标轴当期刻度（高亮）。
  TextStyle get axisLabelActive => TextStyle(
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: primary,
  );

  /// 图表 tooltip 文案。
  TextStyle get tooltipText => TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: onTooltip,
  );

  /// 排行行：分类名。
  TextStyle get rowTitle => TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: textStrong,
  );

  /// 排行行：金额。
  TextStyle get rowAmount => TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: textStrong,
    letterSpacing: 0.1,
  );

  /// 排行行：占比 / 笔数等元信息。
  TextStyle get rowMeta => TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: textFaint,
  );

  /// 图例文字。
  TextStyle get legendLabel => TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: textMuted,
  );

  /// 图例占比。
  TextStyle get legendValue => TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: textStrong,
  );

  /// 空状态标题 / 说明。
  TextStyle get emptyTitle => TextStyle(
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: textMuted,
  );

  TextStyle get emptyBody => TextStyle(
    fontSize: 12,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: textFaint,
  );

  // ---------------------------------------------------------------- 动效

  /// 卡片入场 / 状态切换时长。
  static const durEnter = Duration(milliseconds: 420);

  /// 交互反馈（点击高亮、分段滑动）时长。
  static const durTap = Duration(milliseconds: 220);

  /// 图表数值变化时长。
  static const durChart = Duration(milliseconds: 520);

  /// 入场与滑动统一用这条缓动：起步快、收尾稳，不回弹。
  static const curveEnter = Curves.easeOutCubic;
}

/// 图表专用色：这些值没有对应的全局语义色（网格线比全局分割线更淡、
/// 分类调色板只有统计页在用），所以在这里按亮度各存一套。
@immutable
class _StatsChartColors {
  const _StatsChartColors({
    required this.heroGradient,
    required this.textMuted,
    required this.textFaint,
    required this.gridLine,
    required this.divider,
    required this.fillMuted,
    required this.skeletonHighlight,
    required this.tooltip,
    required this.onTooltip,
    required this.categoryPalette,
    required this.categoryRest,
    required this.trendLineGradient,
    required this.trendAreaGradient,
    required this.barActiveGradient,
    required this.barIdle,
    required this.barTrack,
  });

  final LinearGradient heroGradient;
  final Color textMuted;
  final Color textFaint;
  final Color gridLine;
  final Color divider;
  final Color fillMuted;
  final Color skeletonHighlight;
  final Color tooltip;
  final Color onTooltip;
  final List<Color> categoryPalette;
  final Color categoryRest;
  final LinearGradient trendLineGradient;
  final LinearGradient trendAreaGradient;
  final LinearGradient barActiveGradient;
  final Color barIdle;
  final Color barTrack;
}

const _chartLight = _StatsChartColors(
  heroGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6BA3F7), Color(0xFF4A7FE8), Color(0xFF3B63D6)],
    stops: [0.0, 0.55, 1.0],
  ),
  textMuted: Color(0xFF6B7684),
  textFaint: Color(0xFF98A2B3),
  gridLine: Color(0xFFEEF1F5),
  divider: Color(0xFFF0F2F5),
  fillMuted: Color(0xFFF4F6F9),
  skeletonHighlight: Color(0xFFFAFBFD),
  tooltip: Color(0xF01F2A37),
  onTooltip: Colors.white,
  categoryPalette: [
    Color(0xFF5B8DEF),
    Color(0xFFF2A03D),
    Color(0xFF38BDA0),
    Color(0xFFEF6F6C),
    Color(0xFF9B7EDE),
    Color(0xFF4FB3E8),
  ],
  categoryRest: Color(0xFFB4BDCC),
  trendLineGradient: LinearGradient(
    colors: [Color(0xFF7DB0F9), Color(0xFF4A7FE8)],
  ),
  trendAreaGradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x385B8DEF), Color(0x005B8DEF)],
  ),
  barActiveGradient: LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xFF5B8DEF), Color(0xFF8FB8FA)],
  ),
  barIdle: Color(0xFFD3E1F8),
  barTrack: Color(0xFFF4F7FC),
);

/// 深色图表色。两条调整原则：
/// - 中性色（网格线、轨道、填充）不能直接取浅色的反相，要沉到接近页底，
///   否则密集横线在深底上比数据本身更抢眼。
/// - 分类调色板整体提亮降饱和：浅色那套压在深底上像发光的霓虹。
///
/// - Hero 渐变略压暗：深色页面里高亮卡会刺眼。
const _chartDark = _StatsChartColors(
  heroGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4C82DC), Color(0xFF3A65C4), Color(0xFF2C4CA6)],
    stops: [0.0, 0.55, 1.0],
  ),
  textMuted: Color(0xFF9BA7B2),
  textFaint: Color(0xFF6F7B85),
  gridLine: Color(0xFF272F2D),
  divider: Color(0xFF232B29),
  fillMuted: Color(0xFF222A28),
  skeletonHighlight: Color(0xFF2C3532),
  tooltip: Color(0xF0303A38),
  onTooltip: Color(0xFFF2F6F4),
  categoryPalette: [
    Color(0xFF7FAAF5),
    Color(0xFFF0B267),
    Color(0xFF5FCBB4),
    Color(0xFFF08D8A),
    Color(0xFFAF96E6),
    Color(0xFF74C6EE),
  ],
  categoryRest: Color(0xFF6E7884),
  trendLineGradient: LinearGradient(
    colors: [Color(0xFF8FBBFA), Color(0xFF5A8FE8)],
  ),
  trendAreaGradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x4D6FA5F5), Color(0x006FA5F5)],
  ),
  barActiveGradient: LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xFF4E82DE), Color(0xFF7FAAF5)],
  ),
  barIdle: Color(0xFF32425C),
  barTrack: Color(0xFF1E2624),
);

///坐标轴用的紧凑金额：`12800000`分 → `12.8万`。
///
/// 轴刻度只有约40px 宽，塞完整金额必然重叠或被截断，
/// 所以这里只保留量级+ 一位小数，`¥` 也省掉（轴标题已说明单位）。
String formatAxisMoney(int cents) {
  final yuan = cents / 100;
  final abs = yuan.abs();
  if (abs >= 100000000) return '${_trim(yuan / 100000000)}亿';
  if (abs >= 10000) return '${_trim(yuan / 10000)}万';
  if (abs >= 1000) return '${_trim(yuan / 1000)}千';
  return yuan.round().toString();
}

/// 一位小数，且整数时不留`.0`：`1.0` → `1`，`1.25` → `1.3`。
String _trim(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
