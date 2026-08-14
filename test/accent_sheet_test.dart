import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/preferences/accent_color.dart';
import 'package:ligy_tally/core/theme/app_accent.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/settings/presentation/accent_color_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题色浮层测试。
///
/// 重点不是「浮层能打开」，而是**预览带真的跟着选择变**——预览存在的全部理由
/// 就是让人不必退出去比对，它一旦读了静态色值就等于没有。
void main() {
  /// 把浮层挂在一个跟随 accent 重建主题的宿主里，模拟真实的 MaterialApp 接线。
  Widget host() => ProviderScope(
    child: Consumer(
      builder: (context, ref, _) {
        final accent = ref.watch(appAccentProvider);
        return MaterialApp(
          theme: buildMaterialTheme(Brightness.light, accent),
          builder: (context, child) => FTheme(
            data: foruiThemeFor(Brightness.light, accent),
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

  /// 预览里 Hero 卡的渐变色停。
  List<Color> heroStops(WidgetTester tester) {
    final box = tester.widget<Container>(
      find
          .ancestor(of: find.text('1,286.40'), matching: find.byType(Container))
          .first,
    );
    final decoration = box.decoration! as BoxDecoration;
    return (decoration.gradient! as LinearGradient).colors;
  }

  testWidgets('预览带渲染 Hero 卡、底栏三个 tab 和 FAB', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('本期支出'), findsOneWidget);
    expect(find.text('1,286.40'), findsOneWidget);
    for (final label in ['明细', '统计', '设置']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byIcon(FLucideIcons.plus), findsOneWidget);
    // 六个色点都在。
    for (final accent in AppAccent.values) {
      expect(find.text(accent.label), findsOneWidget);
    }
  });

  testWidgets('默认蓝下预览用的就是统计页那份手挑渐变', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(heroStops(tester), const [
      Color(0xFF6BA3F7),
      Color(0xFF4A7FE8),
      Color(0xFF3B63D6),
    ]);
  });

  testWidgets('点色点后预览跟着换色，不是静态图', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final before = heroStops(tester);
    await tester.tap(find.text(AppAccent.purple.label));
    await tester.pumpAndSettle();
    final after = heroStops(tester);

    expect(after, isNot(before));
    // 换的是色相，亮度阶梯不动：白字对比度不该随主题色漂。
    expect(after.length, before.length);
    for (var i = 0; i < after.length; i++) {
      expect(
        HSLColor.fromColor(after[i]).hue,
        isNot(closeTo(HSLColor.fromColor(before[i]).hue, 1)),
        reason: '第 $i 个色停的色相没变',
      );
    }
  });

  /// 浮层当前的选中值。
  AccentChoice choiceOf(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  ).read(appAccentProvider);

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
    expect(dragging.getString('app_accent'), isNull);

    await gesture.up();
    await tester.pumpAndSettle();
    final released = await SharedPreferences.getInstance();
    expect(released.getString('app_accent'), startsWith('custom:'));
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

  testWidgets('底栏选中态与 FAB 用当前主色', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppAccent.teal.label));
    await tester.pumpAndSettle();

    final expected = AppAccent.teal.light;
    // 选中的「明细」走主色，未选中的「设置」走 inactive。
    expect(tester.widget<Text>(find.text('明细')).style!.color, expected);
    expect(
      tester.widget<Text>(find.text('设置')).style!.color,
      AppColors.light.inactive,
    );
    final fab = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(FLucideIcons.plus),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((fab.decoration! as BoxDecoration).color, expected);
  });
}
