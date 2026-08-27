import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 全应用排版令牌：**金额字阶**与**字距规则**。
///
/// ## 为什么金额要单列一套字阶，而不是复用文本字阶
///
/// 金额是**数据**，不是文字。它对排版的要求和正文正好错开：
/// - 要等宽数字（位数变化时不左右抖），正文不需要；
/// - 要负字距（下面这条规则），正文在 15px 以下几乎不需要；
/// - 字重恒定在 w700/w800（金额是一屏的视觉锚点），正文按层级在 w400~w700 之间走。
///
/// 混在一套字阶里的结果，就是这个项目在引入本文件之前的样子：40px 的 Hero
/// 主数字挂着 `letterSpacing: 0.4`，而同一份代码里的页头标题写着
/// 「字号越大字距越要收紧」。两套需求共用一组命名时，总有一套会被写反。
///
/// ## 字距规则
///
/// [tracking] 是本文件存在的**主要理由**：字距不该由调用点逐个猜，它是字号的
/// 函数。中文黑体与 Roboto 都没有 optical size 轴（字形不随字号自动调整字腔），
/// 字号一大，字符间的空隙看起来就会等比放大，于是大字显松散。补偿办法是按
/// 字号收紧字距，且收紧量本身也随字号增长。
///
/// 曲线锚在页头已经人工调准的两个点上（20px → -0.2，28px → -0.6），所以页头
/// 换用本规则时观感不变，见 `app_page_header.dart`。
///
/// ## 不在这里的东西
///
/// **等宽数字特性（`tabularFigures`）不在本文件里设置。** 它是用户可关的一档
/// 外观设置，由 `buildMaterialTheme` 挂在 `textTheme` 上，靠 `TextStyle.merge`
/// 「自己没给就沿用祖先的」一路继承下来。这里显式写一遍会把那档设置钉死，
/// 用户关掉之后金额仍是等宽的。
///
/// **正文字阶不在这里。** 全应用目前在用 10/11/12/13/14/15/17/20/28 九档字号，
/// 其中若干档（12 与 13、14 与 15）在实机上分辨不出差别，值得收敛——但那要
/// 逐屏核对文本溢出，与本文件的职责（金额与字距）是两件事。
class AppText {
  const AppText._();

  // ------------------------------------------------------------------ 字距

  /// 字号对应的字距（px）。
  ///
  /// 12px 及以下返回 0：小字的字腔本来就紧，再收会粘连；正文档位保持 0 也让
  /// 绝大多数调用点不必关心这条规则。
  ///
  /// 12px 以上按「每增 1px 多收 0.0013em」线性收紧，并在 -0.03em 处封顶——
  /// 不封顶的话 60px 以上会收成负字距过度的「挤字」，而封顶点之上人眼已经
  /// 分辨不出继续收紧的收益。
  ///
  /// 换算成实际值：15px → -0.06、20px → -0.21、27px → -0.53、40px → -1.20。
  static double tracking(double fontSize) {
    if (fontSize <= _trackingFloor) return 0;
    final ratio = math.min(
      (fontSize - _trackingFloor) * _trackingSlope,
      _trackingMaxEm,
    );
    return -ratio * fontSize;
  }

  /// 这个字号以下不收紧字距。
  static const _trackingFloor = 12.0;

  /// 每超出 [_trackingFloor] 1px，多收紧多少 em。
  static const _trackingSlope = 0.0013;

  /// 收紧量上限（em）。
  static const _trackingMaxEm = 0.030;

  // -------------------------------------------------------------- 金额字阶

  /// 列表行里的金额：明细页账单行、统计页排行行、日历页当天账单。
  static const moneySm = 15.0;

  /// 卡内次级金额：Hero 卡底部的「本月收入 / 净收支」、环形图中心。
  static const moneyMd = 20.0;

  /// 次级主数字：分类明细弹层的合计、外观页样张、占用空间。
  static const moneyLg = 27.0;

  /// Hero 卡主数字。全应用最大的一个数，也是第一印象的落点。
  static const moneyXl = 40.0;

  /// 一档金额样式。
  ///
  /// [size] 走上面四档常量。[weight] 默认 w700，[moneyXl] 这类主数字传 w800。
  ///
  /// `height` 必须显式给：金额常放在 [FittedBox] 或固定高度的格子里，
  /// 让字体自带的行高参与布局会导致同一行的两个金额基线错开。
  static TextStyle money(
    double size, {
    required Color color,
    FontWeight weight = FontWeight.w700,
    double height = 1.15,
  }) => TextStyle(
    fontSize: size,
    height: height,
    fontWeight: weight,
    color: color,
    letterSpacing: tracking(size),
  );
}
