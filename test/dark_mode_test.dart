import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/theme/app_accent.dart';
import 'package:ligy_tally/core/theme/app_density.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/shared/widgets/summary_band.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'surface_probe.dart';

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
          .read(appearanceProvider.notifier)
          .setThemeMode(AppThemeMode.dark);
      expect(container.read(appThemeModeProvider), AppThemeMode.dark);

      // 换一个容器模拟冷启动：偏好要从盘里回来，而不是回落到默认值。
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(appearanceProvider.notifier).ready;
      expect(restarted.read(appThemeModeProvider), AppThemeMode.dark);
    });

    test('注入种子时不再异步读盘，第一帧就是终态', () async {
      // 合并成一个对象换来的正是这条：`main.dart` 先 await 一次读盘，
      // 锁定深色 + 紧凑的用户不会看到版式分几帧重排。
      SharedPreferences.setMockInitialValues({});
      const seed = AppearanceConfig(
        themeMode: AppThemeMode.dark,
        density: AppDensityLevel.compact,
      );
      final container = ProviderContainer(
        overrides: [
          appearanceProvider.overrideWith(
            () => AppearanceController.seeded(seed),
          ),
        ],
      );
      addTearDown(container.dispose);

      // 一个微任务都不等，直接读。
      expect(container.read(appThemeModeProvider), AppThemeMode.dark);
      expect(container.read(appDensityProvider), AppDensityLevel.compact);
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
        greaterThan(_luminance(AppColors.light.canvasBase)),
      );
      expect(
        _luminance(AppColors.dark.surface),
        greaterThan(_luminance(AppColors.dark.canvasBase)),
      );
      // 深色整体必须真的暗下去，而不是「灰一点的浅色」。
      expect(
        _luminance(AppColors.dark.canvasBase),
        lessThan(_luminance(AppColors.light.canvasBase) / 4),
      );
    });

    test('纯黑档把页底压到纯黑，但卡片仍比页底亮', () {
      final black = AppColors.dark.withTrueBlack();
      expect(black.canvasBase, const Color(0xFF000000));
      // 卡片跟着压到纯黑的话整页会糊成一片，反而看不出有卡片——
      // 深色下卡片是靠自己更亮才浮起来的（阴影几乎不可见）。
      expect(
        _luminance(black.surface),
        greaterThan(_luminance(black.canvasBase)),
      );
      // 只动中性轴：主色和收支色一个都不该被碰。
      expect(black.primary, AppColors.dark.primary);
      expect(black.expense, AppColors.dark.expense);
    });

    test('收支换向只对调两组钱色，危险 / 成功色钉死', () {
      final reversed = AppColors.light.withReversedSigns();
      expect(reversed.expense, AppColors.light.income);
      expect(reversed.income, AppColors.light.expense);
      // 这一条就是把 danger / success 从 expense / income 里拆出来的
      // 全部理由：翻向之后「删除」的确认按钮不能变成绿的。
      expect(reversed.danger, AppColors.light.danger);
      expect(reversed.success, AppColors.light.success);
    });

    test('正文压在卡片上达到 WCAG AA', () {
      for (final colors in [AppColors.light, AppColors.dark]) {
        expect(
          _contrast(colors.ink, colors.surface),
          greaterThan(4.5),
          reason: '${colors.brightness} 的正文对比度不足',
        );
        expect(
          _contrast(colors.ink, colors.canvasBase),
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
        AppColors.dark.canvasBase,
      );
      expect(
        foruiThemeFor(Brightness.light).colors.background,
        AppColors.light.canvasBase,
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

  testWidgets('摘要卡的白字不跟皮肤翻，卡面就是色板那条 Hero 渐变', (tester) async {
    // 两件事各锁一半：
    //
    // 一是字色。卡面在两套皮肤下都是同一支色相的主题色渐变，字色一旦跟着
    // colors.ink 走，浅色下就是深墨字压深卡面，等于看不见——这是这类
    // 「彩色卡 + 固定前景色」最容易踩的坑。
    //
    // 二是卡面。它必须逐位等于 [AppColors.heroGradient]，也就是统计页概览卡
    // 那条；就地写一份色停的话，两屏的 Hero 卡会各自漂移。六套预设加一支自选色
    // 逐一验，只验默认蓝会漏掉「重染只在默认色下正确」这种写法。
    SharedPreferences.setMockInitialValues({});
    final choices = [
      for (final preset in AppAccent.values) AccentChoice.preset(preset),
      const AccentChoice.custom(hue: 96, saturation: 0.55),
    ];
    for (final accent in choices) {
      final config = AppearanceConfig(accent: accent);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: buildMaterialTheme(brightness, config),
              home: const Scaffold(
                body: SummaryBand(
                  summary: LedgerSummary(
                    incomeCents: 10000,
                    expenseCents: 3575,
                    entryCount: 2,
                    activeDayCount: 2,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 大数字为了逐位动画被拆成一格一个 Text，所以逐格验色，而不是去读
        // 一个 RichText 的顶层 style。`¥` 那一格刻意更淡，不参与这条断言。
        final digits = tester
            .widgetList<Text>(
              find.descendant(
                of: find.bySemanticsLabel('¥35.75'),
                matching: find.byType(Text),
              ),
            )
            .where((text) => text.data != '¥')
            .toList();
        expect(digits, isNotEmpty, reason: '$accent / $brightness 下找不到大数字');
        for (final digit in digits) {
          expect(
            digit.style!.color,
            Colors.white,
            reason: '$accent / $brightness 下大数字「${digit.data}」不是白字',
          );
        }

        final face = tester
            .widgetList<Container>(find.byType(Container))
            .map((container) => container.decoration)
            .firstWhere((decoration) => surfaceGradient(decoration) != null);
        expect(
          surfaceGradient(face),
          AppColors.resolve(brightness, config).heroGradient,
          reason: '$accent / $brightness 下摘要卡没走共用的 Hero 渐变',
        );
      }
    }
  });
}
