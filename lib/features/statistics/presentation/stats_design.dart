import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/color_shift.dart';
import '../../../core/theme/hero_skin.dart';

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
/// ## 为什么颜色和圆角是实例成员、间距是静态成员
///
/// 深浅两套皮肤只影响颜色和带颜色的字阶，间距 / 时长在两套皮肤下完全一致，
/// 留作 `static const`，调用点（`StatsTokens.gutter`、
/// `const EdgeInsets.all(StatsTokens.gapCard)`）可以继续写在 const 表达式里。
/// 颜色和圆角则要先 `StatsTokens.of(context)` 解析——前者随亮度变，
/// 后者随用户在设置里选的圆角档位变。
class StatsTokens {
  const StatsTokens._(this._colors, this._chart, this._radius);

  /// 解析当前主题下的统计令牌。
  ///
  /// 颜色与圆角一律从 [AppColors] / [AppRadius] 转发，而不是自己再存一份——
  /// 主题过渡动画里两者都是插值出来的中间态，自己存一份会导致统计页在过渡
  /// 途中和其它页面差半拍。
  static StatsTokens of(BuildContext context) {
    final colors = AppColors.of(context);
    return StatsTokens._(
      colors,
      colors.isDark ? _chartDark : _chartLight,
      AppRadius.of(context),
    );
  }

  final AppColors _colors;
  final _StatsChartColors _chart;
  final AppRadius _radius;

  // ---------------------------------------------------------------- 圆角

  /// 图表卡圆角。与记账页日卡同一档：两屏的卡片是同一个视觉元素。
  double get radiusCard => _radius.card;

  /// 卡片内小块（分段轨道、排行行、图表 tooltip）圆角。
  double get radiusInner => _radius.block;

  /// 卡内图标底座这类小方块：比 [radiusInner] 再收一档，
  /// 否则 34px 见方的底座会被圆角吃成一颗圆点。
  double get radiusChip => _radius.chip;

  /// 胶囊圆角：徽章、环比标签。不跟着圆角档位走，见 [AppRadius] 的类文档。
  static const radiusPill = AppRadius.pill;

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

  /// 概览 Hero 卡阴影。彩色档是带主色调的彩色阴影（比中性灰更有「发光感」），
  /// 描边档换回中性灰——这个选择在 [HeroSkin] 里已经做完了。
  List<BoxShadow> get shadowHero => hero.shadow;

  // ---------------------------------------------------------------- 颜色

  /// 概览 Hero 卡的整套卡面 + 前景色。转发到 [AppColors.hero]——记账页月度
  /// 摘要卡用的是同一套卡面，不在这里另存一份。
  ///
  /// 用户能把这套卡面换成纯色或描边（见 [HeroCardStyle]），所以卡上的每一个
  /// 颜色都必须从这里取，不能再写死白色。
  HeroSkin get hero => _colors.hero;

  /// 概览 Hero 卡渐变。
  ///
  /// 只在「确实需要一条渐变」的地方用（外观页样张）；卡片本身请走 [hero]，
  /// 它会在纯色 / 描边档给出正确的实底和描边。
  LinearGradient get heroGradient => _colors.heroGradient;

  /// Hero 卡上的三级前景色 + 分割线。
  ///
  /// 彩色档下是白色降透明度（灰色压在彩色卡面上会发浊），描边档下换成
  /// 全局的墨色三级灰阶。
  Color get onHeroPrimary => hero.foreground;
  Color get onHeroSecondary => hero.foregroundSoft;
  Color get onHeroTertiary => hero.foregroundFaint;
  Color get onHeroDivider => hero.divider;

  /// Hero 卡内那些「半透明白小块」的底色：环比徽章底、左右箭头底、骨架条。
  ///
  /// 描边档下卡面变白，半透明白等于消失，所以这里也要跟着换成中性填充。
  Color get onHeroFill =>
      hero.isTinted ? const Color(0x24FFFFFF) : _colors.fill;

  Color get onHeroBar => hero.isTinted ? const Color(0x33FFFFFF) : _colors.fill;

  /// 环比徽章的涨 / 跌色。
  ///
  /// 彩色卡面上不能用纯饱和红绿（在蓝底上刺眼且降低可读性），所以彩色档用
  /// 两个偏亮的低饱和色；描边档卡面是白的，反过来必须用饱和色才看得见。
  ///
  /// 涨跌固定红涨绿跌，**不跟随收支配色设置**：这里表达的是「支出变多了，
  /// 这是个坏消息」，和「支出这个数字该是什么颜色」是两回事。
  Color get onHeroDeltaUp =>
      hero.isTinted ? const Color(0xFFFFD5CE) : _colors.danger;

  Color get onHeroDeltaDown =>
      hero.isTinted ? const Color(0xFFC8F0D4) : _colors.success;

  /// 卡片面色 / 页面底色。
  ///
  /// [canvas] 取 `canvasBase`（实色那支）：统计页拿它的场合都是「给某个小块
  /// 一个和页底同色的实底」，不是在画页底本身。
  Color get surface => _colors.surface;
  Color get canvas => _colors.canvasBase;

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
      for (final color in _chart.categoryPalette) rotateHue(color, rotation),
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
    return rotateHue(palette[index], _hueRotation);
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
  Color get barIdle => rotateHue(_chart.barIdle, _hueRotation);

  /// 当前主色相对默认主色的色相偏移量（度）。转发到 [AppColors]。
  double get _hueRotation => _colors.accentHueRotation;

  LinearGradient _rotateGradient(LinearGradient gradient) {
    final rotation = _hueRotation;
    if (rotation == 0) return gradient;
    return LinearGradient(
      begin: gradient.begin,
      end: gradient.end,
      colors: [for (final c in gradient.colors) rotateHue(c, rotation)],
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
  TextStyle get heroAmount => TextStyle(
    fontSize: 38,
    height: 1.08,
    fontWeight: FontWeight.w800,
    color: onHeroPrimary,
    letterSpacing: 0.4,
  );

  /// Hero 卡次级数字（收入 / 净收支 / 日均）。
  TextStyle get heroMini => TextStyle(
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: onHeroPrimary,
    letterSpacing: 0.2,
  );

  /// Hero 卡标签。
  TextStyle get heroLabel => TextStyle(
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

  /// 交互反馈（点击高亮、分段滑动）时长。
  static const durTap = Duration(milliseconds: 220);

  /// 图表数值变化时长。
  static const durChart = Duration(milliseconds: 520);

  /// 图表与滑动统一用这条缓动：起步快、收尾稳，不回弹。
  static const curveEnter = Curves.easeOutCubic;
}

/// 图表专用色：这些值没有对应的全局语义色（网格线比全局分割线更淡、
/// 分类调色板只有统计页在用），所以在这里按亮度各存一套。
@immutable
class _StatsChartColors {
  const _StatsChartColors({
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
const _chartDark = _StatsChartColors(
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
