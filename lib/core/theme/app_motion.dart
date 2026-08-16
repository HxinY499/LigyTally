import 'package:flutter/material.dart';

/// 全应用动效强度，可由用户在外观设置里切档。
///
/// ## 为什么是「时长倍率」而不是一堆开关
///
/// 全应用有二十几处动画，各自的时长都是按自己的语义挑的（底栏脉冲 380、
/// 样张 morph 200、背板淡入 460）。给每处加一个「要不要动」的分支，
/// 等于把一个设置摊成二十个 if，而且以后新加的动画一定会忘记接。
/// 乘一个倍率则不改任何一处的相对节奏：减弱档整体快一倍，关闭档全部归零。
///
/// ## 关闭档为什么不只是「更快」
///
/// 倍率 0 让每个 `Duration` 变成 [Duration.zero]，
/// `AnimatedContainer` / `AnimationController` 都会直接落到终点，
/// 不需要调用点判断「现在是不是关了」。这也是把它做成倍率的主要收益。
///
/// 页面转场不走这条路：路由的时长写在 `MaterialPageRoute` 里，主题改不到。
/// 那一层由 [MotionLevel.pageTransitions] 换掉转场**观感**（减弱=只淡入、
/// 关闭=直接出现），时长仍是 Flutter 的默认值。
@immutable
class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({this.scale = 1});

  /// 从最近的 [Theme] 取动效倍率。缺扩展时按完整动效渲染。
  static AppMotion of(BuildContext context) =>
      Theme.of(context).extension<AppMotion>() ?? const AppMotion();

  final double scale;

  bool get isOff => scale == 0;

  /// 按当前档位换算一个时长。调用点写 `context.motion.of(_kMorph)`。
  Duration call(Duration base) {
    if (scale == 1) return base;
    if (scale == 0) return Duration.zero;
    return base * scale;
  }

  /// 关闭档下把曲线也拍平：零时长时曲线不影响结果，但有些组件
  /// （`TweenSequence`）会在 0 时长下仍按曲线求值一次，给个线性更稳。
  Curve curve(Curve base) => scale == 0 ? Curves.linear : base;

  @override
  AppMotion copyWith({double? scale}) => AppMotion(scale: scale ?? this.scale);

  /// 档位切换不插值：过渡途中拿到 0.5 倍时长毫无意义，
  /// 而且这个扩展的消费点是 `Duration`，插出来的中间值会让同一屏上
  /// 几个动画各用一个时长。
  @override
  AppMotion lerp(AppMotion? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is AppMotion && other.scale == scale);

  @override
  int get hashCode => scale.hashCode;
}

/// 页面转场：直接出现，不做任何位移或淡入。
///
/// 路由本身仍占用 Flutter 默认的转场时长（改不到），但这段时间里
/// 新页面已经完全不透明地摆在那里，观感上就是「点了就到」。
class _NoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// 用户可选的动效档位。
enum MotionLevel {
  full('完整', 1),

  /// 时长砍到 0.55 倍：足够快到不用等，又还看得出方向和因果。
  /// 再快（0.3 以下）人眼分辨不出「动过」，等于变相关闭。
  reduced('减弱', 0.55),

  off('关闭', 0);

  const MotionLevel(this.label, this.scale);

  final String label;
  final double scale;

  static const fallback = MotionLevel.full;

  AppMotion get tokens => AppMotion(scale: scale);

  /// 页面转场观感。完整档返回 null 表示沿用平台默认转场。
  PageTransitionsTheme? get pageTransitions => switch (this) {
    MotionLevel.full => null,
    MotionLevel.reduced => const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    MotionLevel.off => const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoPageTransitionsBuilder(),
        TargetPlatform.iOS: _NoPageTransitionsBuilder(),
      },
    ),
  };

  static MotionLevel decode(String? name) {
    for (final level in values) {
      if (level.name == name) return level;
    }
    return fallback;
  }
}

extension AppMotionContext on BuildContext {
  AppMotion get motion => AppMotion.of(this);
}
