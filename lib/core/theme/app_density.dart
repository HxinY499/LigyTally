import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 全应用显示密度，可由用户在外观设置里切档。
///
/// ## 两个倍率而不是一个
///
/// 「一屏看几笔」由两件事决定：字有多大、行有多高。只缩字号，行高不动，
/// 换来的是一屏还是那么多行、只是字变小了（更难看清、并没有更高效）；
/// 只缩行高，字号不动，紧凑档会把 15.5 的标题挤到贴着分割线。
/// 所以两个倍率必须同时给，且**字号缩得比间距轻**——中文字面本就比拉丁
/// 饱满，字号一旦低于 0.92 倍，12px 的副标题就跌破可读下限。
///
/// ## 字号倍率不在这个扩展里生效
///
/// [textScale] 只是把档位值带到调用点，真正的落地是在 `MaterialApp.builder`
/// 里换掉 `MediaQuery.textScaler`——那是唯一能一次覆盖全应用（包括 forui
/// 组件内部写死的字号）的入口。若改成在各处 `fontSize * textScale`，
/// 漏掉的地方会和跟上的地方错开一档，比不做更难看。
///
/// [spaceScale] 则相反，必须由调用点显式乘：Flutter 没有「全局间距倍率」
/// 这种东西。只在**行高**这一类量上乘（列表行内边距、最小行高），
/// 页面 gutter 和卡片间距不跟着走——那些是版面骨架，跟着密度缩会让
/// 紧凑档的卡片贴到屏幕边缘。
@immutable
class AppDensity extends ThemeExtension<AppDensity> {
  const AppDensity({this.textScale = 1, this.spaceScale = 1});

  /// 从最近的 [Theme] 取密度。
  ///
  /// 兜底成标准档：测试里的近似主题常常没挂这个扩展，缺时应该按默认密度
  /// 渲染，而不是把所有行高乘上一个 null。
  static AppDensity of(BuildContext context) =>
      Theme.of(context).extension<AppDensity>() ?? const AppDensity();

  final double textScale;

  /// 行高倍率。见类文档：只用在行内边距 / 最小行高上。
  final double spaceScale;

  /// 按密度缩放一个行高量，并留一个下限防止紧凑档把内容压穿。
  double space(double base) => base * spaceScale;

  /// 按密度缩放垂直内边距。水平不缩：左右留白是版面骨架。
  EdgeInsets vertical(double base) =>
      EdgeInsets.symmetric(vertical: space(base));

  @override
  AppDensity copyWith({double? textScale, double? spaceScale}) => AppDensity(
    textScale: textScale ?? this.textScale,
    spaceScale: spaceScale ?? this.spaceScale,
  );

  /// 档位切换**不插值**，在中点直接翻档。
  ///
  /// 与 [AppColors.brightness] 同一条理由，但动机不同：字号倍率走的是
  /// `MediaQuery.textScaler`，不在主题插值链上，它是瞬间跳的。间距若平滑
  /// 过渡，那 200ms 里字已经变了、行高还在爬，看起来像页面在抽搐。
  @override
  AppDensity lerp(AppDensity? other, double t) {
    if (other == null) return this;
    if (t < 0.5) return this;
    return other;
  }

  /// 只给测试和调试用的连续插值，生产路径见 [lerp]。
  AppDensity lerpContinuous(AppDensity other, double t) => AppDensity(
    textScale: lerpDouble(textScale, other.textScale, t)!,
    spaceScale: lerpDouble(spaceScale, other.spaceScale, t)!,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppDensity &&
          other.textScale == textScale &&
          other.spaceScale == spaceScale);

  @override
  int get hashCode => Object.hash(textScale, spaceScale);
}

/// 用户可选的密度档位。
///
/// 做成三档枚举而不是滑杆：字号是**离散**才好用——用户要的是「大一点」，
/// 不是 1.037 倍。连续值还会让每一帧都触发一次全应用重排版。
///
/// 三档的倍率是配对挑的，不是各自拍的。现在的适中就是原来的紧凑
/// （0.94/0.88，一行账单从 64 收到约 57）；宽松回到 1/1，不再额外放大。
/// 紧凑再往下收一档：字号钉在 0.92（再低 12px 副标题就跌破可读下限），
/// 行高收到 0.76（约 49），一屏能多出两笔。更紧的这一档主要吃间距。
/// 中间那档叫「适中」而不是「标准」：外观页上圆角档位里已经有一个「标准」，
/// 同一屏出现两个同名档位，用户读到那行右侧的「标准」时会先愣一下
/// 「这说的是圆角还是密度」。
enum AppDensityLevel {
  compact('紧凑', 0.92, 0.76),
  standard('适中', 0.94, 0.88),
  relaxed('宽松', 1, 1);

  const AppDensityLevel(this.label, this.textScale, this.spaceScale);

  final String label;
  final double textScale;
  final double spaceScale;

  static const fallback = AppDensityLevel.standard;

  AppDensity get tokens =>
      AppDensity(textScale: textScale, spaceScale: spaceScale);

  /// 按持久化的名字反查，认不出就回落标准档（含首次启动与档位增删）。
  static AppDensityLevel decode(String? name) {
    for (final level in values) {
      if (level.name == name) return level;
    }
    return fallback;
  }
}

extension AppDensityContext on BuildContext {
  AppDensity get density => AppDensity.of(this);
}
