import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/theme/app_accent.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// 只关心强调色的那些断言，其余外观档位一律默认。
AppearanceConfig _withAccent(AccentChoice accent) =>
    AppearanceConfig(accent: accent);

void main() {
  group('强调色偏好', () {
    test('默认蓝色，选定后写盘并能读回', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(appAccentProvider), AccentChoice.initial);
      await container
          .read(appearanceProvider.notifier)
          .setAccent(const AccentChoice.preset(AppAccent.purple));
      expect(
        container.read(appAccentProvider),
        const AccentChoice.preset(AppAccent.purple),
      );

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(appearanceProvider.notifier).ready;
      expect(
        restarted.read(appAccentProvider),
        const AccentChoice.preset(AppAccent.purple),
      );
    });

    test('自选色写盘并能读回', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const picked = AccentChoice.custom(hue: 96.4, saturation: 0.512);

      await container.read(appearanceProvider.notifier).setAccent(picked);

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(appearanceProvider.notifier).ready;
      expect(restarted.read(appAccentProvider), picked);
    });

    test('拖动过程不落盘，松手才写', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appearanceProvider.notifier);
      await notifier.ready;

      // 一次拖动会产生上百个中间值，全落盘等于拿磁盘当画布。
      notifier.previewAccent(
        const AccentChoice.custom(hue: 10, saturation: 0.4),
      );
      expect(
        container.read(appAccentProvider),
        const AccentChoice.custom(hue: 10, saturation: 0.4),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        AppearanceConfig.decode(prefs.getString(appearancePrefsKey)).accent,
        AccentChoice.initial,
        reason: '拖动过程写进了盘',
      );

      // 松手落的是最终值。这里 state 已经等于目标值了，setAccent 不能因此
      // 提前返回——那正是「拖完没保存」的经典写法。
      await notifier.setAccent(
        const AccentChoice.custom(hue: 10, saturation: 0.4),
      );
      final saved = await SharedPreferences.getInstance();
      expect(
        AppearanceConfig.decode(saved.getString(appearancePrefsKey)).accent,
        const AccentChoice.custom(hue: 10, saturation: 0.4),
      );
    });

    test('未知名字回落到蓝', () {
      expect(AppAccent.fromName(null), AppAccent.blue);
      expect(AppAccent.fromName('not-a-color'), AppAccent.blue);
    });

    test('旧版本存下的预设名照旧读得回来', () {
      // 迁移到 AccentChoice 之前，偏好里只存枚举名。
      expect(
        AccentChoice.decode('orange'),
        const AccentChoice.preset(AppAccent.orange),
      );
    });

    test('脏数据回落到默认值，不抛异常', () {
      // 偏好文件是外部输入，解不出来必须回落而不是让 app 起不来。
      for (final raw in [
        null,
        '',
        'not-a-color',
        'custom:',
        'custom:1',
        'custom:abc:0.5',
        'custom:10:x',
      ]) {
        expect(AccentChoice.decode(raw), AccentChoice.initial, reason: '$raw');
      }
    });

    test('越界的自选值被夹回可用区间', () {
      final tooGray = AccentChoice.decode('custom:200:0.0');
      expect(tooGray.saturation, kAccentMinSaturation);
      final wrapped = AccentChoice.decode('custom:900:0.5');
      expect(wrapped.hue, lessThanOrEqualTo(360));
    });
  });

  group('自选强调色', () {
    test('深浅落在预设的区间里，不跟着用户走', () {
      // 自选只开色相和饱和度：明度一旦开放，一支太浅的黄能让 FAB 上的白字
      // 直接消失。这里锁住「任何色相 / 任何浓淡下，深浅都在预设那一档」。
      for (final brightness in Brightness.values) {
        final presetRange = AppAccent.values
            .map((preset) => _luminance(preset.primaryOf(brightness)))
            .toList();
        final low = presetRange.reduce((a, b) => a < b ? a : b);
        final high = presetRange.reduce((a, b) => a > b ? a : b);
        for (var hue = 0.0; hue < 360; hue += 15) {
          for (final saturation in [kAccentMinSaturation, 0.6, 1.0]) {
            final primary = AccentChoice.custom(
              hue: hue,
              saturation: saturation,
            ).primaryOf(brightness);
            expect(
              _luminance(primary),
              inInclusiveRange(low, high),
              reason: '色相 $hue / 浓淡 $saturation / $brightness 越出预设的深浅区间',
            );
          }
        }
      }
    });

    test('色相与饱和度照用户选的走', () {
      const choice = AccentChoice.custom(hue: 96, saturation: 0.55);
      final hsl = HSLColor.fromColor(choice.primaryOf(Brightness.light));
      expect(hsl.hue, closeTo(96, 1));
      expect(hsl.saturation, closeTo(0.55, 0.02));
    });

    test('预设也能报出滑杆位置，点完预设可以接着微调', () {
      const teal = AccentChoice.preset(AppAccent.teal);
      final hsl = HSLColor.fromColor(AppAccent.teal.light);
      expect(teal.hue, hsl.hue);
      expect(teal.saturation, hsl.saturation);
    });

    test('Hero 卡渐变跟着饱和度走，浓淡滑杆不能对最大那块彩色面没用', () {
      final vivid = AppColors.resolve(
        Brightness.light,
        _withAccent(const AccentChoice.custom(hue: 217, saturation: 1)),
      ).heroGradient;
      final muted = AppColors.resolve(
        Brightness.light,
        _withAccent(
          const AccentChoice.custom(
            hue: 217,
            saturation: kAccentMinSaturation,
          ),
        ),
      ).heroGradient;
      for (var i = 0; i < vivid.colors.length; i++) {
        expect(
          HSLColor.fromColor(muted.colors[i]).saturation,
          lessThan(HSLColor.fromColor(vivid.colors[i]).saturation),
          reason: '第 $i 个色停没跟着浓淡变',
        );
      }
      // 但深浅不动：白字压在上面的对比度与选了什么色无关。
      for (var i = 0; i < vivid.colors.length; i++) {
        expect(
          _luminance(muted.colors[i]),
          closeTo(_luminance(vivid.colors[i]), 0.01),
        );
      }
    });
  });

  group('强调色色板', () {
    test('默认蓝就是现有的 light / dark 常量，引用不变', () {
      expect(
        identical(
          AppColors.resolve(Brightness.light, AppearanceConfig.initial),
          AppColors.light,
        ),
        isTrue,
      );
      expect(
        identical(
          AppColors.resolve(Brightness.dark, AppearanceConfig.initial),
          AppColors.dark,
        ),
        isTrue,
      );
      expect(AppAccent.blue.light, AppColors.light.primary);
      expect(AppAccent.blue.dark, AppColors.dark.primary);
    });

    test('换强调色只动主色家族，支出收入暖黄不动', () {
      final tinted = AppColors.resolve(
        Brightness.light,
        _withAccent(const AccentChoice.preset(AppAccent.purple)),
      );
      expect(tinted.primary, AppAccent.purple.light);
      expect(tinted.primary, isNot(AppColors.light.primary));
      expect(tinted.expense, AppColors.light.expense);
      expect(tinted.income, AppColors.light.income);
      expect(tinted.accent, AppColors.light.accent);
      expect(tinted.canvas, AppColors.light.canvas);
    });

    test('每套强调色在深色下都被提亮', () {
      for (final accent in AppAccent.values) {
        expect(
          _luminance(accent.dark),
          greaterThan(_luminance(accent.light)),
          reason: '${accent.label} 的深色主色没有提亮',
        );
      }
    });

    testWidgets('Material 主题挂上对应强调色', (tester) async {
      late AppColors resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMaterialTheme(
            Brightness.light,
            _withAccent(const AccentChoice.preset(AppAccent.teal)),
          ),
          home: Builder(
            builder: (context) {
              resolved = context.colors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved.primary, AppAccent.teal.light);
    });

    test('forui 主题按强调色缓存，同一把钥匙返回同一实例', () {
      final pink = _withAccent(const AccentChoice.preset(AppAccent.pink));
      final a = foruiThemeFor(Brightness.light, pink);
      final b = foruiThemeFor(Brightness.light, pink);
      final c = foruiThemeFor(Brightness.light, AppearanceConfig.initial);
      expect(identical(a, b), isTrue);
      expect(identical(a, c), isFalse);
      expect(a.colors.primary, AppAccent.pink.light);
    });

    test('自选色的主题缓存只留最新一份，拖滑杆不会把 map 灌满', () {
      final first = _withAccent(
        const AccentChoice.custom(hue: 12, saturation: 0.5),
      );
      final second = _withAccent(
        const AccentChoice.custom(hue: 13, saturation: 0.5),
      );
      final a = foruiThemeFor(Brightness.light, first);
      expect(identical(foruiThemeFor(Brightness.light, first), a), isTrue);

      // 换一个落点之后，上一份必须已经被挤掉——留着就等于一次拖动往缓存里
      // 灌几百份主题。
      foruiThemeFor(Brightness.light, second);
      expect(identical(foruiThemeFor(Brightness.light, first), a), isFalse);
    });
  });
}
