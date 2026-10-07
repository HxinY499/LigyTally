import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/theme/app_motion.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/shared/widgets/app_switch.dart';

const _thumb = 27.0;

Widget _harness({bool initial = false, AppMotion motion = const AppMotion()}) {
  var value = initial;
  return MaterialApp(
    theme: ThemeData(extensions: [motion]),
    home: Center(
      child: StatefulBuilder(
        builder: (context, setState) => AppSwitch(
          value: value,
          onChange: (next) => setState(() => value = next),
        ),
      ),
    ),
  );
}

/// 圆点左右沿与轨道色。画笔是私有类，按字段名读。
({double left, double right, Color track}) _frame(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(AppSwitch),
      matching: find.byType(CustomPaint),
    ),
  );
  final dynamic painter = paint.painter;
  return (
    left: painter.left as double,
    right: painter.right as double,
    track: painter.track as Color,
  );
}

void main() {
  group('果冻开关', () {
    testWidgets('布局就是 51×31 的轨道，没有隐形留白', (tester) async {
      await tester.pumpWidget(_harness());
      expect(tester.getSize(find.byType(AppSwitch)), const Size(51, 31));
    });

    testWidgets('途中拉长成胶囊、越过终点压扁，350ms 后回弹成正圆停在右端', (tester) async {
      await tester.pumpWidget(_harness());
      final start = _frame(tester);
      expect(start.right - start.left, _thumb);
      expect(start.track, AppColors.light.primarySoft);

      await tester.tap(find.byType(AppSwitch));
      await tester.pump();

      var maxWidth = 0.0;
      var minWidth = double.infinity;
      for (var ms = 0; ms < 350; ms += 10) {
        await tester.pump(const Duration(milliseconds: 10));
        final f = _frame(tester);
        final width = f.right - f.left;
        if (width > maxWidth) maxWidth = width;
        if (width < minWidth) minWidth = width;
        expect(f.right, lessThanOrEqualTo(49 + 1e-9), reason: '前沿不能冲出轨道');
      }
      expect(maxWidth, greaterThan(_thumb * 1.3));
      expect(minWidth, lessThan(_thumb * 0.92));

      await tester.pumpAndSettle();
      final end = _frame(tester);
      expect(end.left, closeTo(22, 1e-9));
      expect(end.right - end.left, closeTo(_thumb, 1e-9));
      expect(end.track, AppColors.light.primary);
    });

    testWidgets('动画途中再点一次，从当前画面接着往回走，不跳帧', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.tap(find.byType(AppSwitch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final before = _frame(tester);

      await tester.tap(find.byType(AppSwitch));
      await tester.pump();
      final after = _frame(tester);
      expect(after.left, closeTo(before.left, 1e-9));
      expect(after.right, closeTo(before.right, 1e-9));
      expect(after.track, before.track);

      await tester.pumpAndSettle();
      final end = _frame(tester);
      expect(end.left, closeTo(2, 1e-9));
      expect(end.right - end.left, closeTo(_thumb, 1e-9));
    });

    testWidgets('动效关闭档下一帧直接落到终点', (tester) async {
      await tester.pumpWidget(_harness(motion: MotionLevel.off.tokens));
      await tester.tap(find.byType(AppSwitch));
      await tester.pump();
      await tester.pump();
      final f = _frame(tester);
      expect(f.left, closeTo(22, 1e-9));
      expect(f.right - f.left, closeTo(_thumb, 1e-9));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('读屏：暴露开关状态并可点按切换', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness(initial: true));
      expect(
        tester.getSemantics(find.byType(AppSwitch)),
        isSemantics(
          isToggled: true,
          hasToggledState: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
