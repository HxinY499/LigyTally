import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/preferences/theme_mode.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/shared/widgets/summary_band.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WCAG 2.1 相对亮度。
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final light = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  group('外观偏好', () {
    test('默认跟随系统，选定后写盘并能读回', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(appThemeModeProvider), AppThemeMode.system);
      await container
          .read(appThemeModeProvider.notifier)
          .setMode(AppThemeMode.dark);
      expect(container.read(appThemeModeProvider), AppThemeMode.dark);

      // 换一个容器模拟冷启动：偏好要从盘里回来，而不是回落到默认值。
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      restarted.read(appThemeModeProvider);
      await Future<void>.delayed(Duration.zero);
      expect(restarted.read(appThemeModeProvider), AppThemeMode.dark);
    });

    test('三档分别映射到 Material 的 ThemeMode', () {
      expect(AppThemeMode.system.materialMode, ThemeMode.system);
      expect(AppThemeMode.light.materialMode, ThemeMode.light);
      expect(AppThemeMode.dark.materialMode, ThemeMode.dark);
    });
  });

  group('深色色板卫生', () {
    test('卡片与页底的明暗关系在两套皮肤下是反的', () {
      // 浅色靠阴影浮起卡片，所以卡片比页底**更亮**；深色下阴影几乎不可见，
      // 卡片只能靠自身更亮来分层——这两条关系搞反的话，深色页面会糊成一片。
      expect(
        _luminance(AppColors.light.surface),
        greaterThan(_luminance(AppColors.light.canvas)),
      );
      expect(
        _luminance(AppColors.dark.surface),
        greaterThan(_luminance(AppColors.dark.canvas)),
      );
      // 深色整体必须真的暗下去，而不是「灰一点的浅色」。
      expect(
        _luminance(AppColors.dark.canvas),
        lessThan(_luminance(AppColors.light.canvas) / 4),
      );
    });

    test('正文压在卡片上达到 WCAG AA', () {
      for (final colors in [AppColors.light, AppColors.dark]) {
        expect(
          _contrast(colors.ink, colors.surface),
          greaterThan(4.5),
          reason: '${colors.brightness} 的正文对比度不足',
        );
        expect(
          _contrast(colors.ink, colors.canvas),
          greaterThan(4.5),
          reason: '${colors.brightness} 的正文压页底对比度不足',
        );
      }
    });

    test('语义色在深色下被提亮，否则会糊进深底', () {
      for (final field in [
        (AppColors.light.primary, AppColors.dark.primary),
        (AppColors.light.expense, AppColors.dark.expense),
        (AppColors.light.income, AppColors.dark.income),
      ]) {
        expect(_luminance(field.$2), greaterThan(_luminance(field.$1)));
      }
    });

    test('点击反馈在深色下加重，且水波始终比按下底色更淡', () {
      // 深底上 6% 的叠加层等于没有反馈。
      expect(AppColors.dark.pressed.a, greaterThan(AppColors.light.pressed.a));
      for (final colors in [AppColors.light, AppColors.dark]) {
        expect(colors.ripple.a, lessThan(colors.pressed.a));
      }
    });
  });

  group('主题接线', () {
    testWidgets('两套主题都挂上了色板扩展，取不到会静默退回浅色', (tester) async {
      for (final brightness in Brightness.values) {
        late AppColors resolved;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildMaterialTheme(brightness),
            home: Builder(
              builder: (context) {
                resolved = context.colors;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(resolved.brightness, brightness);
        expect(
          resolved,
          brightness == Brightness.dark ? AppColors.dark : AppColors.light,
        );
      }
    });

    testWidgets('forui 主题跟着亮度走，不会拿浅色主题去铺深色页面', (tester) async {
      expect(
        foruiThemeFor(Brightness.dark).colors.background,
        AppColors.dark.canvas,
      );
      expect(
        foruiThemeFor(Brightness.light).colors.background,
        AppColors.light.canvas,
      );
      // 缓存返回同一个实例，不是每次重新构造。
      expect(
        identical(
          foruiThemeFor(Brightness.dark),
          foruiThemeFor(Brightness.dark),
        ),
        isTrue,
      );
    });
  });

  testWidgets('暖黄摘要卡的字色不跟着皮肤翻', (tester) async {
    // 这张卡的卡面在两套皮肤下都是固定暖黄渐变。字色一旦跟着 colors.ink 走，
    // 深色下就是近白字压浅黄底，等于看不见——这是迁移时最容易踩的坑。
    SharedPreferences.setMockInitialValues({});
    late Color amountColor;
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildMaterialTheme(brightness),
            home: const Scaffold(
              body: SummaryBand(
                summary: LedgerSummary(
                  incomeCents: 10000,
                  expenseCents: 3575,
                  entryCount: 2,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final amount = tester.widget<Text>(find.text('35.75'));
      final color = amount.style!.color!;
      if (brightness == Brightness.values.first) {
        amountColor = color;
      } else {
        expect(color, amountColor);
      }
      // 深墨字压暖黄底，两套皮肤下都必须达到 AA。
      expect(_contrast(color, const Color(0xFFF8D98A)), greaterThan(4.5));
    }
  });
}
