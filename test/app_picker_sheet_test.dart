import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/shared/widgets/app_picker_sheet.dart';

Widget _host(void Function(BuildContext) onPress) {
  final theme = buildForuiTheme();
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: const [
      FLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => FTheme(data: theme, child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => onPress(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('日期浮层可打开并确认', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      _host((context) async {
        picked = await showAppDatePicker(
          context,
          initial: DateTime(2026, 3, 15),
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('选择日期'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 3, 15));
  });

  testWidgets('时间浮层可打开并确认', (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      _host((context) async {
        picked = await showAppTimePicker(
          context,
          initial: const TimeOfDay(hour: 20, minute: 46),
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('选择时间'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(picked, const TimeOfDay(hour: 20, minute: 46));
  });

  testWidgets('时间浮层滚动后返回新时刻', (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      _host((context) async {
        picked = await showAppTimePicker(
          context,
          initial: const TimeOfDay(hour: 20, minute: 46),
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 往上拖分钟轮：itemExtent 约 22.5，拖 3 格确保跨过若干分钟。
    final wheels = find.byType(ListWheelScrollView);
    expect(wheels, findsNWidgets(2));
    await tester.drag(wheels.last, const Offset(0, -70));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.hour, 20);
    expect(picked!.minute, greaterThan(46));
  });

  testWidgets('日期浮层可选中另一天', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      _host((context) async {
        picked = await showAppDatePicker(
          context,
          initial: DateTime(2026, 3, 15),
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 3, 20));
  });

  testWidgets('取消返回 null', (tester) async {
    var called = false;
    DateTime? picked;
    await tester.pumpWidget(
      _host((context) async {
        picked = await showAppDatePicker(context, initial: DateTime(2026, 3, 15));
        called = true;
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(picked, isNull);
  });
}
