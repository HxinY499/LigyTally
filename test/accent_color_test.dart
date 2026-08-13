import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/preferences/accent_color.dart';
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

void main() {
  group('强调色偏好', () {
    test('默认蓝色，选定后写盘并能读回', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(appAccentProvider), AppAccent.blue);
      await container
          .read(appAccentProvider.notifier)
          .setAccent(AppAccent.purple);
      expect(container.read(appAccentProvider), AppAccent.purple);

      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      restarted.read(appAccentProvider);
      await Future<void>.delayed(Duration.zero);
      expect(restarted.read(appAccentProvider), AppAccent.purple);
    });

    test('未知名字回落到蓝', () {
      expect(AppAccent.fromName(null), AppAccent.blue);
      expect(AppAccent.fromName('not-a-color'), AppAccent.blue);
    });
  });

  group('强调色色板', () {
    test('默认蓝就是现有的 light / dark 常量，引用不变', () {
      expect(
        identical(
          AppColors.resolve(Brightness.light, AppAccent.blue),
          AppColors.light,
        ),
        isTrue,
      );
      expect(
        identical(
          AppColors.resolve(Brightness.dark, AppAccent.blue),
          AppColors.dark,
        ),
        isTrue,
      );
      expect(AppAccent.blue.light, AppColors.light.primary);
      expect(AppAccent.blue.dark, AppColors.dark.primary);
    });

    test('换强调色只动主色家族，支出收入暖黄不动', () {
      final tinted = AppColors.resolve(Brightness.light, AppAccent.purple);
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
          theme: buildMaterialTheme(Brightness.light, AppAccent.teal),
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
      final a = foruiThemeFor(Brightness.light, AppAccent.pink);
      final b = foruiThemeFor(Brightness.light, AppAccent.pink);
      final c = foruiThemeFor(Brightness.light, AppAccent.blue);
      expect(identical(a, b), isTrue);
      expect(identical(a, c), isFalse);
      expect(a.colors.primary, AppAccent.pink.light);
    });
  });
}
