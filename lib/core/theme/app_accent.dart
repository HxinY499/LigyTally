import 'package:flutter/material.dart';

import 'color_shift.dart';

/// 预设强调色：一排点开即用的快选。
///
/// 手挑而不是从某支基色算出来的：`light` / `dark` 两支是分别为「压在白底上」
/// 和「压在深底上」挑的，深色那支必须更亮，否则会糊进深页面。
enum AppAccent {
  blue('蓝', Color(0xFF5190F2), Color(0xFF6FA5F5)),
  teal('青', Color(0xFF2A9B94), Color(0xFF4DB8B0)),
  indigo('靛', Color(0xFF5C6AE8), Color(0xFF8894F5)),
  purple('紫', Color(0xFF8B5FDB), Color(0xFFA98AE8)),
  pink('粉', Color(0xFFD4537E), Color(0xFFE87A9C)),
  orange('橙', Color(0xFFE07A2F), Color(0xFFEE9A55));

  const AppAccent(this.label, this.light, this.dark);

  final String label;

  /// 浅色皮肤下的主色。
  final Color light;

  /// 深色皮肤下的主色：比 [light] 更亮，否则会糊进深底。
  final Color dark;

  Color primaryOf(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static AppAccent fromName(String? name) {
    for (final value in AppAccent.values) {
      if (value.name == name) return value;
    }
    return AppAccent.blue;
  }
}

/// 自选色的深浅：六个预设主色的**平均相对亮度**（浅 0.238 / 深 0.361）。
///
/// 深浅不交给用户调，只开放色相和饱和度。主色要同时压得住白字（浅色皮肤下的
/// FAB、强调按钮）又要在深底上看得见，明度一旦开放，一支太浅的黄或太深的靛
/// 就能让按钮文字直接消失。钉在预设的中间档，自选色的可读性与预设同级。
const _customLightLuminance = 0.238;
const _customDarkLuminance = 0.361;

/// 自选色的饱和度下限。
///
/// 不许一路拖到灰：主色的职责是把选中态从未选中态里分出来，饱和度归零之后
/// 底栏选中态就是一支灰压在 `inactive` 那支灰旁边，等于没有选中态。
const kAccentMinSaturation = 0.25;

/// 自选强调色的实际主色：色相 / 饱和度照用户选的，深浅按皮肤钉死。
Color customAccentPrimary({
  required double hue,
  required double saturation,
  required Brightness brightness,
}) => withRelativeLuminance(
  HSLColor.fromAHSL(1, hue % 360, saturation.clamp(0.0, 1.0), 0.5).toColor(),
  brightness == Brightness.dark ? _customDarkLuminance : _customLightLuminance,
);

/// 用户选定的强调色：六个 [AppAccent] 预设之一，或自选色相 + 饱和度。
///
/// 预设仍然留着，不是因为自选做不到同样的颜色，而是「快选」和「细调」是两种
/// 需求：多数人只想一眼挑一个不难看的，不想调两条滑杆。
@immutable
class AccentChoice {
  const AccentChoice.preset(AppAccent preset)
    : _preset = preset,
      _customHue = 0,
      _customSaturation = 0;

  const AccentChoice.custom({required double hue, required double saturation})
    : _preset = null,
      _customHue = hue,
      _customSaturation = saturation;

  /// 冷启动、以及读盘拿到脏数据时的默认值。
  static const initial = AccentChoice.preset(AppAccent.blue);

  final AppAccent? _preset;

  /// 自选时用户拖到的位置；选中预设时是占位的 0，读它没有意义，
  /// 对外一律走 [hue] / [saturation]。
  final double _customHue;
  final double _customSaturation;

  /// 选中的预设；自选时为 null。
  AppAccent? get preset => _preset;

  bool get isCustom => _preset == null;

  /// 色相（0–360）。
  ///
  /// 预设也给值——取它 [AppAccent.light] 那支的色相。这样「点个预设再微调」
  /// 不需要特例：滑杆永远以当前生效的颜色为起点。
  double get hue =>
      _preset == null ? _customHue : HSLColor.fromColor(_preset.light).hue;

  /// 饱和度（0–1）。理由同 [hue]。
  double get saturation => _preset == null
      ? _customSaturation
      : HSLColor.fromColor(_preset.light).saturation;

  Color primaryOf(Brightness brightness) =>
      _preset?.primaryOf(brightness) ??
      customAccentPrimary(
        hue: _customHue,
        saturation: _customSaturation,
        brightness: brightness,
      );

  /// 持久化字符串。
  ///
  /// 预设仍然写枚举名，老版本装机存下的 `purple` 照旧读得回来；自选写
  /// `custom:<色相>:<饱和度>`，前缀不与任何枚举名冲突。
  String encode() =>
      _preset?.name ??
      'custom:${_customHue.toStringAsFixed(1)}'
          ':${_customSaturation.toStringAsFixed(3)}';

  /// [encode] 的逆。任何解不出来的输入都回落到 [initial]，
  /// 而不是抛异常——偏好文件是外部输入，脏数据不该让 app 起不来。
  static AccentChoice decode(String? raw) {
    if (raw == null) return initial;
    if (!raw.startsWith('custom:')) {
      return AccentChoice.preset(AppAccent.fromName(raw));
    }
    final parts = raw.split(':');
    if (parts.length != 3) return initial;
    final hue = double.tryParse(parts[1]);
    final saturation = double.tryParse(parts[2]);
    if (hue == null || saturation == null) return initial;
    return AccentChoice.custom(
      hue: hue.clamp(0.0, 360.0).toDouble(),
      saturation: saturation.clamp(kAccentMinSaturation, 1.0).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AccentChoice &&
      other._preset == _preset &&
      other._customHue == _customHue &&
      other._customSaturation == _customSaturation;

  @override
  int get hashCode => Object.hash(_preset, _customHue, _customSaturation);

  @override
  String toString() => 'AccentChoice(${encode()})';
}
