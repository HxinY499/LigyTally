import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/theme/app_accent.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/settings/presentation/accent_color_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题色浮层测试。
///
/// 浮层本身不再带预览（外观页顶部那张共享样张负责这件事），
/// 这里只守：浮层打得开、色点能切、滑杆拖动中不落盘、松手才写偏好。
void main() {
  /// 把浮层挂在一个跟随 accent 重建主题的宿主里，模拟真实的 MaterialApp 接线。
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showAccentColorSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  AccentChoice choiceOf(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  ).read(appearanceProvider).accent;

  testWidgets('浮层里是六个色点和两条滑杆，没有预览带', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('主题色'), findsOneWidget);
    for (final accent in AppAccent.values) {
      expect(find.text(accent.label), findsOneWidget);
    }
    expect(find.text('色相'), findsOneWidget);
    expect(find.text('浓淡'), findsOneWidget);
    // 预览已经收到外观页顶部，浮层里不该再出现那一套样张。
    expect(find.text('本期支出'), findsNothing);
    expect(find.text('1,286.40'), findsNothing);
    expect(find.byIcon(FLucideIcons.plus), findsNothing);
  });

  testWidgets('点色点会改选中值', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(choiceOf(tester).preset, AppAccent.blue);
    await tester.tap(find.text(AppAccent.purple.label));
    await tester.pumpAndSettle();
    expect(choiceOf(tester).preset, AppAccent.purple);
  });

  /// 某条滑杆轨道上的横向坐标。[fraction] 0 是最左、1 是最右。
  ///
  /// 按标签所在那一行的矩形算，而不是去找轨道自己的 RenderBox：轨道被
  /// LayoutBuilder 包着，测试里拿它的位置比拿这一行脆得多。
  Offset stripPoint(WidgetTester tester, String label, double fraction) {
    final row = find
        .ancestor(of: find.text(label), matching: find.byType(Row))
        .first;
    final rect = tester.getRect(row);
    // 左边让开标签（34）+ 间距（6），右边留一点余量避免正好压在边界上。
    final left = rect.left + 42;
    return Offset(left + (rect.right - left - 4) * fraction, rect.center.dy);
  }

  testWidgets('拖色相条切到自选色，且松手才落盘', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(choiceOf(tester).isCustom, isFalse);

    final gesture = await tester.startGesture(stripPoint(tester, '色相', 0.05));
    await tester.pump();
    await gesture.moveTo(stripPoint(tester, '色相', 0.9));
    await tester.pump();

    // 拖动中：内存里已经是自选色，但偏好还没写。
    expect(choiceOf(tester).isCustom, isTrue);
    final dragging = await SharedPreferences.getInstance();
    expect(
      AppearanceConfig.decode(dragging.getString(appearancePrefsKey)).accent
          .isCustom,
      isFalse,
      reason: '拖动过程写进了盘',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    final released = await SharedPreferences.getInstance();
    expect(
      AppearanceConfig.decode(released.getString(appearancePrefsKey)).accent
          .isCustom,
      isTrue,
    );
  });

  testWidgets('色相条从左到右色相递增，浓淡条从左到右越来越浓', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(stripPoint(tester, '色相', 0.1));
    await tester.pumpAndSettle();
    final low = choiceOf(tester).hue;
    await tester.tapAt(stripPoint(tester, '色相', 0.9));
    await tester.pumpAndSettle();
    expect(choiceOf(tester).hue, greaterThan(low));

    await tester.tapAt(stripPoint(tester, '浓淡', 0.05));
    await tester.pumpAndSettle();
    final pale = choiceOf(tester).saturation;
    expect(pale, greaterThanOrEqualTo(kAccentMinSaturation));
    await tester.tapAt(stripPoint(tester, '浓淡', 0.95));
    await tester.pumpAndSettle();
    expect(choiceOf(tester).saturation, greaterThan(pale));
  });

  testWidgets('点完预设可以接着微调：滑杆从那支预设的位置起步', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppAccent.orange.label));
    await tester.pumpAndSettle();
    final presetHue = HSLColor.fromColor(AppAccent.orange.light).hue;
    expect(choiceOf(tester).hue, presetHue);

    // 只碰浓淡条，色相要留在橙上，而不是被重置成 0（红）。
    await tester.tapAt(stripPoint(tester, '浓淡', 0.5));
    await tester.pumpAndSettle();
    expect(choiceOf(tester).isCustom, isTrue);
    expect(choiceOf(tester).hue, closeTo(presetHue, 0.01));
  });

  testWidgets('窄屏下六个色点加两条滑杆都不溢出', (tester) async {
    // 六个 44 的色点排成一行，320 宽是最窄的在售机型，也是唯一会挤爆的宽度。
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '浮层不该溢出');
    for (final accent in AppAccent.values) {
      expect(find.text(accent.label), findsOneWidget);
    }
    expect(find.text('色相'), findsOneWidget);
    expect(find.text('浓淡'), findsOneWidget);
  });
}
