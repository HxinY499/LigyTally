import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/ledger/presentation/transaction_editor.dart';

/// 金额卡的三条硬性行为，锁死防回归：
/// 1. 溢出往左裁（尾部与光标始终可见），不是省略号截尾
/// 2. 卡片高度不随「有无运算符」变化
/// 3. 负数给出文字解释，而不是只把保存键置灰
void main() {
  /// 把金额卡放进受限宽度里渲染，模拟真机窄屏。
  Future<void> pump(WidgetTester tester, Widget card, {double width = 320}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: card),
          ),
        ),
      ),
    );
  }

  group('金额卡溢出方向', () {
    testWidgets('超长表达式向左溢出，不使用省略号截尾', (tester) async {
      await pump(
        tester,
        const AmountCardForTest(
          expression: '1234.56+7890.12+3456.78',
          amountValue: 12581.46,
          kind: 0,
        ),
      );

      // 主行的大数字不能带 ellipsis —— 那会把刚按下的尾部数字吃掉。
      final texts = tester.widgetList<Text>(find.byType(Text));
      for (final text in texts) {
        if (text.style?.fontWeight == FontWeight.w800) {
          expect(
            text.overflow,
            isNot(TextOverflow.ellipsis),
            reason: '主数字行不应省略号截尾',
          );
          expect(text.softWrap, false);
        }
      }

      // 反向滚动容器负责把左边裁掉。
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.reverse, true, reason: '必须反向，才能让尾部停在可视区');
      expect(scroll.scrollDirection, Axis.horizontal);
      expect(
        scroll.physics,
        isA<NeverScrollableScrollPhysics>(),
        reason: '金额不该被手指划走',
      );
    });

    testWidgets('无溢出时也不会报 overflow', (tester) async {
      await pump(
        tester,
        const AmountCardForTest(expression: '12.5', amountValue: 12.5, kind: 0),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('金额卡高度稳定', () {
    testWidgets('按下运算符后卡片总高不变', (tester) async {
      await pump(
        tester,
        const AmountCardForTest(expression: '100', amountValue: 100, kind: 0),
      );
      final plain = tester.getSize(find.byType(AmountCardForTest)).height;

      await pump(
        tester,
        const AmountCardForTest(
          expression: '100+50',
          amountValue: 150,
          kind: 0,
        ),
      );
      final withOperator = tester
          .getSize(find.byType(AmountCardForTest))
          .height;

      expect(withOperator, plain, reason: '高度一变，下面的分类网格就会跳');
    });

    testWidgets('空态与有值态同高', (tester) async {
      await pump(
        tester,
        const AmountCardForTest(expression: '', amountValue: 0, kind: 0),
      );
      final empty = tester.getSize(find.byType(AmountCardForTest)).height;

      await pump(
        tester,
        const AmountCardForTest(expression: '8', amountValue: 8, kind: 0),
      );
      expect(tester.getSize(find.byType(AmountCardForTest)).height, empty);
    });
  });

  group('金额卡内容', () {
    testWidgets('含运算符时主行显示合计、辅助行显示过程', (tester) async {
      await pump(
        tester,
        const AmountCardForTest(
          expression: '3.5+7',
          amountValue: 10.5,
          kind: 0,
        ),
      );
      expect(find.text('10.50'), findsOneWidget, reason: '合计当主角');
      expect(find.text('3.5 + 7'), findsOneWidget, reason: '过程退为辅助行');
    });

    testWidgets('千分位与全局偏好一致', (tester) async {
      await pump(
        tester,
        const AmountCardForTest(
          expression: '12000',
          amountValue: 12000,
          kind: 0,
        ),
      );
      expect(find.text('12,000'), findsOneWidget);
    });

    testWidgets('关闭千分位时显示裸数字', (tester) async {
      await pump(
        tester,
        const AmountCardForTest(
          expression: '12000',
          amountValue: 12000,
          kind: 0,
          grouped: false,
        ),
      );
      expect(find.text('12000'), findsOneWidget);
    });

    testWidgets('负数给出文字解释', (tester) async {
      await pump(
        tester,
        const AmountCardForTest(expression: '5-8', amountValue: -3, kind: 0),
      );
      expect(find.text('金额需大于 0'), findsOneWidget, reason: '不能只把保存键置灰而不解释');
    });

    testWidgets('空态显示灰色占位', (tester) async {
      await pump(
        tester,
        const AmountCardForTest(expression: '', amountValue: 0, kind: 0),
      );
      expect(find.text('0.00'), findsOneWidget);
    });
  });
}
