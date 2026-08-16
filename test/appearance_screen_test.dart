import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/theme/app_accent.dart';
import 'package:ligy_tally/core/theme/app_density.dart';
import 'package:ligy_tally/core/theme/app_radius.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/theme/hero_skin.dart';
import 'package:ligy_tally/features/settings/presentation/appearance_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 外观二级页测试。
///
/// 重点不是「页面能打开」，而是两件事：
/// 1. 顶部那张共享样张真的跟着底下的档位变——把外观从设置首页收进二级页，
///    换来的就是这一件事；样张一旦读了静态值，这次拆分就只剩「多点一次」的坏处。
/// 2. 风格预设是「一按换一整套」，且改任何一项之后它会诚实地取消选中。
void main() {
  /// 把页面挂在一个跟随偏好重建主题的宿主里，模拟真实的 MaterialApp 接线。
  Widget host() => ProviderScope(
    child: Consumer(
      builder: (context, ref, _) {
        final config = ref.watch(appearanceProvider);
        return MaterialApp(
          theme: buildMaterialTheme(Brightness.light, config),
          builder: (context, child) => FTheme(
            data: foruiThemeFor(Brightness.light, config),
            child: FToaster(child: child!),
          ),
          home: const AppearanceScreen(),
        );
      },
    ),
  );

  /// 整页一次铺开再 pump。
  ///
  /// 外观页是 SliverList，默认 800 高的测试视口里靠后的几组落在折叠线以下
  /// 压根不会被构建——找不到不代表页面写错了。
  Future<void> pumpPage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  AppearanceConfig configOf(WidgetTester tester) =>
      containerOf(tester).read(appearanceProvider);

  /// 样张里那张 Hero 卡的装饰。
  BoxDecoration heroDecoration(WidgetTester tester) {
    final box = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('1,280.00'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    return box.decoration! as BoxDecoration;
  }

  double heroRadius(WidgetTester tester) =>
      (heroDecoration(tester).borderRadius! as BorderRadius).topLeft.x;

  testWidgets('各组外观设置都在这一屏上，不再散落在设置首页', (tester) async {
    await pumpPage(tester);

    expect(find.text('深浅模式'), findsOneWidget);
    expect(find.text('主题色'), findsOneWidget);
    expect(find.text('收支配色'), findsOneWidget);
    expect(find.text('显示密度'), findsOneWidget);
    // 千分位从设置首页收了进来：它和「数字等宽」是同一件事的两半。
    expect(find.text('金额千分位'), findsOneWidget);
    expect(find.text('数字等宽'), findsOneWidget);
    expect(find.text('摘要卡样式'), findsOneWidget);
    expect(find.text('底栏样式'), findsOneWidget);
    expect(find.text('动效强度'), findsOneWidget);
    expect(find.text('选择壁纸'), findsOneWidget);
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

  testWidgets('纯黑档只在深色生效时出现，浅色下整行收起', (tester) async {
    // 宿主钉在浅色，纯黑档在这里一个像素都改不了。置灰摆着让人猜它归谁管，
    // 不如跟着深色一起收起来（与背景模糊同一条规则）。
    await pumpPage(tester);
    expect(find.text('纯黑深色'), findsNothing);
  });

  testWidgets('样张通栏写的是「按钮」，不是「确定」', (tester) async {
    await pumpPage(tester);
    expect(find.text('按钮'), findsOneWidget);
    expect(find.text('确定'), findsNothing);
  });

  testWidgets('换主题色，顶部共享样张的 Hero 渐变跟着变', (tester) async {
    await pumpPage(tester);
    final before = (heroDecoration(tester).gradient! as LinearGradient).colors;

    containerOf(tester)
        .read(appearanceProvider.notifier)
        .setAccent(const AccentChoice.preset(AppAccent.purple));
    await tester.pumpAndSettle();

    final after = (heroDecoration(tester).gradient! as LinearGradient).colors;
    expect(after, isNot(before));
  });

  testWidgets('摘要卡换成描边档，样张的卡面和字色一起翻过来', (tester) async {
    // 这条锁的是「卡面和前景成套发放」：只换背景不换字色，描边档下
    // 卡上的数字会直接消失在白面里。
    await pumpPage(tester);
    expect(heroDecoration(tester).gradient, isNotNull);

    containerOf(tester)
        .read(appearanceProvider.notifier)
        .setHeroStyle(HeroCardStyle.outline);
    await tester.pumpAndSettle();

    final decoration = heroDecoration(tester);
    expect(decoration.gradient, isNull);
    expect(decoration.border, isNotNull);
    expect(
      tester.widget<Text>(find.text('1,280.00')).style!.color,
      isNot(Colors.white),
      reason: '描边档下大数字还是白的，压在白卡面上等于看不见',
    );
  });

  testWidgets('按一下风格预设，同时换掉深浅、主题色、圆角、密度和底栏', (tester) async {
    await pumpPage(tester);
    // 「纯黑」这套预设改动最多，拿它验「一按换一整套」。
    final preset = kAppearancePresets.firstWhere(
      (item) => item.label == '纯黑',
    );

    await tester.tap(find.text(preset.label));
    await tester.pumpAndSettle();

    final config = configOf(tester);
    expect(config.themeMode, preset.themeMode);
    expect(config.accent, preset.accent);
    expect(config.corner, preset.corner);
    expect(config.density, preset.density);
    expect(config.trueBlack, isTrue);
    expect(config.navBarStyle, preset.navBarStyle);
    expect(matchedPreset(config), preset);
  });

  testWidgets('窄屏 + 宽松密度下整页不溢出', (tester) async {
    // 320 宽是最窄的在售机型，宽松密度又把每一行的字号和行高一起放大——
    // 这一屏在这次改动里从四组涨到八组，其中好几行右侧带滑杆或胶囊，
    // 是最容易挤爆的地方。
    await pumpPage(tester);
    await tester.binding.setSurfaceSize(const Size(320, 2600));
    containerOf(tester)
        .read(appearanceProvider.notifier)
        .setDensity(AppDensityLevel.relaxed);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '外观页在窄屏宽松档下溢出了');
    expect(find.text('显示密度'), findsOneWidget);
    expect(find.text('摘要卡样式'), findsOneWidget);
  });

  testWidgets('预设不碰收支配色和千分位，改一项则整排取消选中', (tester) async {
    await pumpPage(tester);
    final notifier = containerOf(tester).read(appearanceProvider.notifier);

    await notifier.setMoneyGrouped(false);
    await notifier.applyPreset(
      kAppearancePresets.firstWhere((item) => item.label == '墨夜'),
    );
    await tester.pumpAndSettle();
    // 千分位是用户自己的格式偏好，换皮肤不该顺手改掉。
    expect(configOf(tester).moneyGrouped, isFalse);
    expect(matchedPreset(configOf(tester)), isNotNull);

    // 但改一项风格字段之后，就该诚实地变成「自定义」。
    await notifier.setDensity(AppDensityLevel.relaxed);
    await tester.pumpAndSettle();
    expect(matchedPreset(configOf(tester)), isNull);
  });
}
