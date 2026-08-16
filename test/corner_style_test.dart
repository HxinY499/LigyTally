import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/theme/app_radius.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('圆角偏好', () {
    test('默认标准档，选定后写盘并能读回', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(appCornerStyleProvider), AppCornerStyle.standard);
      await container
          .read(appearanceProvider.notifier)
          .setCorner(AppCornerStyle.sharp);
      expect(container.read(appCornerStyleProvider), AppCornerStyle.sharp);

      // 换一个容器模拟冷启动：偏好要从盘里回来，而不是回落到默认值。
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(appearanceProvider.notifier).ready;
      expect(restarted.read(appCornerStyleProvider), AppCornerStyle.sharp);
    });

    test('存了个不认识的档位名时回落到标准档，而不是抛异常', () async {
      SharedPreferences.setMockInitialValues({
        appearancePrefsKey: 'LT1~system~blue~bubbly',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(appearanceProvider.notifier).ready;
      expect(container.read(appCornerStyleProvider), AppCornerStyle.standard);
    });

    test('合并之前的旧 key 会被迁移进整套配置，老用户的档位不丢', () async {
      // 十几项外观合并成一个 key 之前，每项各占一个 key。
      SharedPreferences.setMockInitialValues({
        'app_corner_style': 'extraRound',
        'app_theme_mode': 'dark',
        'money_grouped': false,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(appearanceProvider.notifier).ready;
      final config = container.read(appearanceProvider);
      expect(config.corner, AppCornerStyle.extraRound);
      expect(config.themeMode, AppThemeMode.dark);
      expect(config.moneyGrouped, isFalse);

      // 迁移完旧 key 必须清掉：同一个偏好在盘上留两份，下一个改这块的人
      // 必然要问「到底哪份是准的」。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_corner_style'), isNull);
      expect(prefs.getString(appearancePrefsKey), isNotNull);
    });
  });

  group('圆角阶梯', () {
    test('四档始终保持「浮层 > 卡片 > 卡内块 > 图标底座」的递进', () {
      for (final style in AppCornerStyle.values) {
        final radius = AppRadius(scale: style.scale);
        expect(
          radius.sheet >= radius.card,
          isTrue,
          reason: '${style.name} 档下浮层圆角小于卡片',
        );
        expect(radius.card >= radius.block, isTrue, reason: '${style.name} 档');
        expect(radius.block >= radius.chip, isTrue, reason: '${style.name} 档');
      }
    });

    test('直角档把四档全压到 0', () {
      const radius = AppRadius(scale: 0);
      expect(radius.sheet, 0);
      expect(radius.card, 0);
      expect(radius.block, 0);
      expect(radius.chip, 0);
    });
  });

  group('圆角接入主题', () {
    test('Material 主题挂上了对应档位的 AppRadius', () {
      for (final style in AppCornerStyle.values) {
        final theme = buildMaterialTheme(
          Brightness.light,
          AppearanceConfig(corner: style),
        );
        expect(theme.extension<AppRadius>()?.scale, style.scale);
      }
    });

    // forui 的各组件样式是在 FThemeData **构造时**由 style 派生的。
    // 若哪天有人把圆角改成 `theme.copyWith(style: ...)`，卡片/按钮/输入框
    // 会静默沿用旧圆角，只有自己画的那些容器跟着变——这条就是防这个的。
    test('forui 组件样式跟着档位一起变，不只是 style 字段变了', () {
      final sharp = foruiThemeFor(
        Brightness.light,
        const AppearanceConfig(corner: AppCornerStyle.sharp),
      );
      final round = foruiThemeFor(
        Brightness.light,
        const AppearanceConfig(corner: AppCornerStyle.extraRound),
      );

      expect(sharp.style.borderRadius.md, BorderRadius.zero);
      expect(round.style.borderRadius.md.topLeft.x, greaterThan(10));

      // 卡片样式是派生出来的，必须跟着走。
      expect(
        sharp.cardStyle.decoration.borderRadius,
        isNot(round.cardStyle.decoration.borderRadius),
      );
    });

    test('胶囊不受档位影响：直角档下 forui 开关仍是圆头', () {
      final sharp = foruiThemeFor(
        Brightness.light,
        const AppearanceConfig(corner: AppCornerStyle.sharp),
      );
      expect(sharp.style.borderRadius.pill.topLeft.x, greaterThan(50));
    });
  });
}
