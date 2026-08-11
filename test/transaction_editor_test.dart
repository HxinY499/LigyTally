import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/features/ledger/presentation/transaction_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记账页「金额显示 + 键盘」合成一块输入面板后的三条硬性行为：
/// 1. 金额显示条属于底部面板，不再是滚动区里的独立卡片
/// 2. 备注聚焦（系统键盘接管）时数字键盘区收起，小屏也不溢出
/// 3. 收起后有明确出口能把数字键盘换回来
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 各偏好的 Notifier 在 build 里异步读盘，没有 mock 会抛到未捕获的 Future 里。
    SharedPreferences.setMockInitialValues({});
  });

  /// 默认的 800x600 测试视口比手机矮，滚动区会被输入面板挤到放不下分类网格
  /// （网格整块落在可视区外就不会被渲染，找不到「餐饮」）。统一按 400x900 逻辑
  /// 像素跑，接近主流机型。
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(WidgetTester tester, AppDatabase database) async {
    final forui = buildForuiTheme();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: forui.toApproximateMaterialTheme(),
          builder: (context, child) =>
              FTheme(data: forui, child: FToaster(child: child!)),
          home: const TransactionEditor(),
        ),
      ),
    );
    // 不用 pumpAndSettle：页面里有持续动画时它会等不到静止帧而挂死。
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> teardown(WidgetTester tester) async {
    // drift 取消订阅时会排一个 0ms 的清理定时器，测试结束前要放掉它。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  group('金额显示与键盘合成一块面板', () {
    testWidgets('金额显示条在分类下方、紧贴键盘上方', (tester) async {
      usePhoneViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      final amount = tester.getRect(find.text('0.00'));
      final sevenKey = tester.getRect(find.text('7'));
      final category = tester.getRect(find.text('餐饮'));

      // 曾经金额卡在滚动区顶部、键盘钉在底部，眼睛要在屏幕两头来回跑。
      // 现在它必须落在分类下面 —— 也就是离开了滚动区。
      expect(
        amount.top,
        greaterThan(category.top),
        reason: '金额显示条还留在滚动区里',
      );
      expect(amount.bottom, lessThan(sevenKey.top), reason: '金额显示条必须在键盘之上');
      // 中间只隔着日期条和备注行。距离一旦拉大，就是又被塞回内容流了。
      expect(
        sevenKey.top - amount.bottom,
        lessThan(180),
        reason: '金额显示条与键盘之间不该有别的内容',
      );

      await teardown(tester);
    });

    testWidgets('显示条是通栏白条，不再是有边距的卡片', (tester) async {
      usePhoneViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      // 卡片形态的标志是左右留白；一体化后它必须吃满整个面板宽度，
      // 靠与下方灰底的色差分区，而不是靠圆角描边自证边界。
      final pageWidth = tester.getSize(find.byType(TransactionEditor)).width;
      final display = find
          .ancestor(of: find.text('¥'), matching: find.byType(Container))
          .first;
      expect(tester.getSize(display).width, pageWidth);

      await teardown(tester);
    });
  });

  group('空间不够时键盘区让位', () {
    /// 小屏：360x640 逻辑像素。页头占掉 112 后可用高度 528，
    /// 系统中文键盘再吃掉 300 就只剩 228，装不下 416 的完整面板。
    void useSmallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('小屏 + 系统键盘弹起，键盘区收起且不溢出', (tester) async {
      // 面板是固定高度、放在 Column 里，算错就是 RenderFlex overflow。
      // 这里刻意让 viewInsets 一步到位（而不是模拟键盘上滑的渐变），
      // 逼出最坏情况：空间瞬间缩水，键盘区必须在同一帧就撤掉。
      useSmallViewport(tester);

      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      await tester.tap(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(tester.takeException(), isNull, reason: '面板不该溢出');
      expect(find.text('7'), findsNothing, reason: '系统键盘接管后数字键盘要让位');
      expect(find.text('保存'), findsNothing);
      // 让位的只有按键区，金额和备注本身必须还看得见。
      expect(find.text('0.00'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('空间一恢复，数字键盘自己回来', (tester) async {
      useSmallViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await tester.pump();
      expect(find.text('7'), findsNothing);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      expect(find.text('7'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('大屏上空间够，备注一聚焦键盘区照样让位', (tester) async {
      // 427x952 这类主流尺寸，系统键盘吃掉 300 后剩余高度仍然大于阈值，
      // 光靠「装不装得下」拦不住 —— 两套键盘会一起堆在屏幕上，
      // 分类网格被挤没。所以聚焦本身也必须是收起条件。
      usePhoneViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      expect(find.text('7'), findsOneWidget);

      await tester.tap(find.byType(TextField));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(find.text('7'), findsNothing, reason: '备注聚焦后数字键盘要让位');
      expect(tester.takeException(), isNull);

      await teardown(tester);
    });

    testWidgets('点金额显示条能收起系统键盘', (tester) async {
      usePhoneViewport(tester);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // 键盘区收起时保存键也跟着不见了，必须有条路回到记账主流程，
      // 否则用户打完备注得在面板外找地方点一下才能保存。
      await tester.tap(find.text('0.00'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse, reason: '金额条要能收起系统键盘');

      await teardown(tester);
    });
  });
}
