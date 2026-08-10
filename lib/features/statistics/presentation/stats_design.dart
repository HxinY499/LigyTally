import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 统计页设计令牌：配色、圆角、阴影、字阶、动效时长。
///
/// 统计页是全应用「图表密度最高」的一屏，颜色和字号一旦各处硬编码，
/// 很快就会失控（同一种灰出现四个色值、同一级标题三种字号）。
/// 所以本文件是统计页唯一的样式源：页面与图表组件只引用这里的常量，
/// 不再就地写 `Color(0xFF...)` 或 `fontSize: 13`。
///
/// 基色仍然复用 [AppColors]（品牌蓝 / 支出红 / 收入绿），
/// 这里只做「统计场景专用」的扩展：图表配色梯度、卡片阴影、数字字阶。
class StatsTokens {
  const StatsTokens._();

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

  /// 卡片阴影。转发到 [AppShadows.card]——阴影是全应用统一的视觉语言，
  /// 记账页日卡与统计页图表卡必须浮起在同一高度，所以不在这里另开一份。
  static const shadowCard = AppShadows.card;

  /// 概览 Hero 卡阴影：带主色调的彩色阴影，比中性灰更有「发光感」。
  static const shadowHero = AppShadows.heroPrimary;

  // ---------------------------------------------------------------- 颜色

  /// Hero 卡渐变：品牌蓝往深靛蓝收，右下角最深。
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6BA3F7), Color(0xFF4A7FE8), Color(0xFF3B63D6)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Hero 卡上的次级文字（标签、说明）：白色降透明度，
  /// 比直接给一个灰色更干净——灰色压在蓝底上会发浊。
  static const onHeroPrimary = Colors.white;
  static const onHeroSecondary = Color(0xCCFFFFFF);
  static const onHeroTertiary = Color(0x99FFFFFF);
  static const onHeroDivider = Color(0x33FFFFFF);

  /// 卡片面色/ 页面底色。
  static const surface = AppColors.surface;
  static const canvas = AppColors.canvas;

  /// 文字三级灰阶。统计页只用这三档，不再引入第四种灰。
  static const textStrong = AppColors.ink;
  static const textMuted = Color(0xFF6B7684);
  static const textFaint = Color(0xFF98A2B3);

  /// 图表网格线/ 分割线：比 [AppColors.line] 更淡，
  /// 避免密集横线把图表压成「格子纸」。
  static const gridLine = Color(0xFFEEF1F5);
  static const divider = Color(0xFFF0F2F5);

  /// 中性填充：分段轨道底、进度条槽、骨架屏。
  static const fillMuted = Color(0xFFF4F6F9);

  /// tooltip 深底。
  static const tooltip = Color(0xF01F2A37);

  /// 支出 / 收入语义色（沿用全局，转出别名便于图表内直接引用）。
  static const expense = AppColors.expense;
  static const income = AppColors.income;
  static const primary = AppColors.primary;

  // ---------------------------------------------------------------- 图表配色

  /// 分类环形图配色。
  ///
  /// 选色原则：色相尽量拉开（蓝 → 橙 → 青 → 珊瑚 → 紫 → 天蓝），
  /// 明度与饱和度保持在同一档，避免某一片「跳出来」抢视觉。
  /// 前两位是最高频的两个分类，用对比最强的蓝 / 橙。
  static const categoryPalette = [
    Color(0xFF5B8DEF),
    Color(0xFFF2A03D),
    Color(0xFF38BDA0),
    Color(0xFFEF6F6C),
    Color(0xFF9B7EDE),
    Color(0xFF4FB3E8),
  ];

  /// 「其他」聚合项固定用低饱和灰蓝，视觉上自然退到后面。
  static const categoryRest = Color(0xFFB4BDCC);

  /// 取第 [index] 个分类色；超出调色板长度时回落到 [categoryRest]，
  /// 而不是循环取色——循环会让第 7 项和第 1 项同色，图例失去区分度。
  static Color categoryColor(int index) =>
      index < categoryPalette.length ? categoryPalette[index] : categoryRest;

  /// 趋势折线：主色渐变（左浅右深），比单色更有纵深。
  static const trendLineGradient = LinearGradient(
    colors: [Color(0xFF7DB0F9), Color(0xFF4A7FE8)],
  );

  /// 趋势折线下方面积填充：主色到透明。
  static const trendAreaGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x385B8DEF), Color(0x005B8DEF)],
  );

  /// 柱状图当期高亮柱渐变。
  static const barActiveGradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xFF5B8DEF), Color(0xFF8FB8FA)],
  );

  /// 柱状图历史柱：低饱和蓝，和高亮柱形成明确主次。
  static const barIdle = Color(0xFFD3E1F8);

  /// 柱状图背景轨道：给每根柱一个浅槽，柱子矮时也不会「悬空」。
  static const barTrack = Color(0xFFF4F7FC);

  // ---------------------------------------------------------------- 字阶

  /// 页面内区块标题（卡片标题）。
  static const titleSection = TextStyle(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: textStrong,
    letterSpacing: 0.1,
  );

  /// 卡片标题下的补充说明。
  static const captionSection = TextStyle(
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
  static const donutCenterAmount = TextStyle(
    fontSize: 17,
    height: 1.15,
    fontWeight: FontWeight.w800,
    color: textStrong,
    letterSpacing: 0.2,
  );

  /// 图表坐标轴刻度。
  static const axisLabel = TextStyle(
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w500,
    color: textFaint,
  );

  /// 坐标轴当期刻度（高亮）。
  static const axisLabelActive = TextStyle(
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: primary,
  );

  /// 图表 tooltip 文案。
  static const tooltipText = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  /// 排行行：分类名。
  static const rowTitle = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: textStrong,
  );

  /// 排行行：金额。
  static const rowAmount = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: textStrong,
    letterSpacing: 0.1,
  );

  /// 排行行：占比 / 笔数等元信息。
  static const rowMeta = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: textFaint,
  );

  /// 图例文字。
  static const legendLabel = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: textMuted,
  );

  /// 图例占比。
  static const legendValue = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: textStrong,
  );

  /// 空状态标题 / 说明。
  static const emptyTitle = TextStyle(
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: textMuted,
  );

  static const emptyBody = TextStyle(
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
