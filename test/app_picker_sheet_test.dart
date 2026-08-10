import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/utils/ledger_date.dart';
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
        picked = await showAppDatePicker(
          context,
          initial: DateTime(2026, 3, 15),
        );
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

  group('日期区间浮层', () {
    /// 打开区间浮层并返回结果的读取闭包。
    ///
    /// 统一封装：每个用例都要 pumpWidget → tap open → settle，
    /// 差别只在初始区间和后续操作。
    Future<LedgerDateRange? Function()> open(
      WidgetTester tester, {
      required LedgerDateRange initial,
      DateTime? firstDate,
      DateTime? lastDate,
    }) async {
      LedgerDateRange? picked;
      await tester.pumpWidget(
        _host((context) async {
          picked = await showAppDateRangePicker(
            context,
            initial: initial,
            firstDate: firstDate,
            lastDate: lastDate,
          );
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => picked;
    }

    testWidgets('原样确认返回传入区间', (tester) async {
      final picked = await open(
        tester,
        initial: LedgerDateRange(DateTime(2026, 3, 1), DateTime(2026, 3, 16)),
      );
      expect(find.text('选择日期区间'), findsOneWidget);
      // 预览文案：同年时终点省略年份，并给出天数。
      expect(find.text('2026 年 3 月 1 日 - 3 月 15 日 · 15 天'), findsOneWidget);

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      final range = picked();
      expect(range, isNotNull);
      expect(range!.start, DateTime(2026, 3, 1));
      // 回传的是半开区间：末端为选中末日 + 1 天。
      expect(range.endExclusive, DateTime(2026, 3, 16));
      expect(range.dayCount, 15);
    });

    testWidgets('倒序点选也能得到正向区间', (tester) async {
      final picked = await open(
        tester,
        initial: LedgerDateRange(DateTime(2026, 3, 10), DateTime(2026, 3, 11)),
      );
      // 先点 20 定住一端，再点 5——forui 对早于起点的日期会改起点，
      // 所以最终必须是 5 → 20 而不是负向区间。
      //
      // 日期网格会渲染邻月的溢出日，`5` 会同时命中 3 月 5 日和邻月的某个 5，
      // 所以取 first：网格按时间正序排列，当月的 5 号排在 4 月的 5 号之前。
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      final range = picked();
      expect(range, isNotNull);
      expect(range!.start, DateTime(2026, 3, 5));
      expect(range.endExclusive, DateTime(2026, 3, 21));
      expect(range.dayCount, 16);
    });

    testWidgets('选择被清空时确定不可点', (tester) async {
      final picked = await open(
        tester,
        initial: LedgerDateRange(DateTime(2026, 3, 10), DateTime(2026, 3, 11)),
      );
      // 单日区间的起止是同一天，再点它一次 forui 会把选择清空。
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      expect(find.text('请选择起止日期'), findsOneWidget);

      // 此时确定按钮禁用：点下去浮层不关闭，也不回调。
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('选择日期区间'), findsOneWidget);
      expect(picked(), isNull);
    });

    testWidgets('跨年区间的预览带上终点年份', (tester) async {
      await open(
        tester,
        initial: LedgerDateRange(DateTime(2025, 12, 20), DateTime(2026, 1, 6)),
      );
      // 半开区间末端 1/6，对应的选中末日是 1/5。
      expect(
        find.text('2025 年 12 月 20 日 - 2026 年 1 月 5 日 · 17 天'),
        findsOneWidget,
      );
    });

    testWidgets('闰年 2 月 29 日可选中', (tester) async {
      final picked = await open(
        tester,
        // 2028 是闰年，2 月有 29 天。
        initial: LedgerDateRange(DateTime(2028, 2, 1), DateTime(2028, 2, 2)),
      );
      await tester.tap(find.text('29'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      final range = picked();
      expect(range, isNotNull);
      expect(range!.start, DateTime(2028, 2, 1));
      expect(range.endExclusive, DateTime(2028, 3, 1));
      expect(range.dayCount, 29);
    });

    testWidgets('取消返回 null', (tester) async {
      final picked = await open(
        tester,
        initial: LedgerDateRange(DateTime(2026, 3, 1), DateTime(2026, 3, 16)),
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(picked(), isNull);
    });
  });

  group('日历融入浮层且撑满宽度', () {
    /// 日历左右留白，与 `app_picker_sheet.dart` 里的 `_kCalendarInset` 一致。
    const inset = 8.0;

    /// 日期网格的实际渲染宽度。
    ///
    /// 直接量渲染结果而不是去翻样式参数：用户看到的是最终几何，
    /// 断言几何才能真正锁住「撑满」这件事。
    double gridWidth(WidgetTester tester) {
      // 一周 7 列，用星期表头行定位网格：它和日期格子同宽。
      final grid = find.byType(GridView);
      expect(grid, findsWidgets);
      return tester.getSize(grid.first).width;
    }

    /// 断言日历撑满可用宽度（= 屏宽 − 左右留白），且没有自带描边卡片。
    void expectStretchedAndBorderless(WidgetTester tester) {
      final screen = tester.getSize(find.byType(MaterialApp)).width;
      // 网格宽度按 7 列整除会有不到 1px 的取整误差，给 1px 容差。
      expect(gridWidth(tester), closeTo(screen - inset * 2, 1.0));

      // forui 默认给日历套 ShapeDecoration（描边 + card 底色 + 圆角）；
      // 浮层本身已是白面卡片，再套一层就成「框中框」。
      //
      // 只找**真正画出线**的边框：日期格子的选中态背景也是
      // ShapeDecoration + RoundedSuperellipseBorder，但它的 side 是
      // `BorderStyle.none`，不能算描边，否则误判。
      final bordered = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<ShapeDecoration>()
          .where((d) {
            final shape = d.shape;
            if (shape is! RoundedSuperellipseBorder) return false;
            return shape.side.style != BorderStyle.none && shape.side.width > 0;
          })
          .toList();
      expect(bordered, isEmpty);
    }

    testWidgets('单日选择浮层', (tester) async {
      await tester.pumpWidget(
        _host(
          (context) =>
              showAppDatePicker(context, initial: DateTime(2026, 3, 15)),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expectStretchedAndBorderless(tester);
    });

    testWidgets('区间选择浮层', (tester) async {
      await tester.pumpWidget(
        _host(
          (context) => showAppDateRangePicker(
            context,
            initial: LedgerDateRange(
              DateTime(2026, 8, 1),
              DateTime(2026, 9, 1),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expectStretchedAndBorderless(tester);
    });

    testWidgets('换到窄屏后仍然撑满', (tester) async {
      // 固定格子宽度（触屏预设 44 → 7×44=308）在窄屏上会溢出或留白，
      // 所以要验证宽度是跟着容器算的，而不是写死的。
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          (context) =>
              showAppDatePicker(context, initial: DateTime(2026, 3, 15)),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(gridWidth(tester), closeTo(360 - inset * 2, 1.0));
    });
  });
}
