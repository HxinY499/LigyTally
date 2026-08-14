import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/preferences/accent_color.dart';
import 'package:ligy_tally/core/preferences/corner_style.dart';
import 'package:ligy_tally/core/theme/app_radius.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/settings/presentation/appearance_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外观二级页测试。
///
/// 重点不是「页面能打开」，而是**顶部那张共享样张真的跟着底下的档位变**——
/// 把外观从设置首页收进二级页，换来的就是这一件事；样张一旦读了静态值，
/// 这次拆分就只剩「多点一次」的坏处。
void main() {
  /// 把页面挂在一个跟随偏好重建主题的宿主里，模拟真实的 MaterialApp 接线。
  Widget host() => ProviderScope(
    child: Consumer(
      builder: (context, ref, _) {
        final accent = ref.watch(appAccentProvider);
        final corner = ref.watch(appCornerStyleProvider);
        return MaterialApp(
          theme: buildMaterialTheme(Brightness.light, accent, corner),
          builder: (context, child) => FTheme(
            data: foruiThemeFor(Brightness.light, accent, corner),
            child: FToaster(child: child!),
          ),
          home: const AppearanceScreen(),
        );
      },
    ),
  );

  /// 整页一次铺开再 pump。
  ///
  /// 外观页是 SliverList，默认 800 高的测试视口里「记账页」「桌面」两组
  /// 落在折叠线以下压根不会被构建——找不到不代表页面写错了。
  Future<void> pumpPage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
  }

  /// 样张里那张 Hero 卡的圆角。
  double heroRadius(WidgetTester tester) {
    final box = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('1,280.00'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final decoration = box.decoration! as BoxDecoration;
    return (decoration.borderRadius! as BorderRadius).topLeft.x;
  }

  testWidgets('五组外观设置都在这一屏上，不再散落在设置首页', (tester) async {
    await pumpPage(tester);

    expect(find.text('深浅模式'), findsOneWidget);
    expect(find.text('主题色'), findsOneWidget);
    expect(find.text('账单图片'), findsOneWidget);
    expect(find.text('分类选择样式'), findsOneWidget);
    expect(find.text('应用图标'), findsOneWidget);
    // 圆角是直接摊开的档位排，不再是一行 + 一个浮层。
    for (final style in AppCornerStyle.values) {
      expect(find.text(style.label), findsOneWidget);
    }
  });

  testWidgets('点圆角档位，顶部共享样张当场跟着变形', (tester) async {
    await pumpPage(tester);

    expect(heroRadius(tester), AppRadius.cardBase);

    await tester.tap(find.text(AppCornerStyle.sharp.label));
    await tester.pumpAndSettle();
    expect(heroRadius(tester), 0);

    await tester.tap(find.text(AppCornerStyle.extraRound.label));
    await tester.pumpAndSettle();
    expect(
      heroRadius(tester),
      AppRadius.cardBase * AppCornerStyle.extraRound.scale,
    );
  });

  testWidgets('背景模糊只在背板模式下出现，贴纸模式下整行收起', (tester) async {
    await pumpPage(tester);

    // 默认是背板模式。
    expect(find.text('背景模糊'), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.sticker));
    await tester.pumpAndSettle();
    expect(find.text('背景模糊'), findsNothing);
  });
}
