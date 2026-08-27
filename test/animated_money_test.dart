import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/theme/app_motion.dart';
import 'package:ligy_tally/shared/widgets/animated_money.dart';

/// 金额逐位动画。
///
/// 这里替掉的上一版是对**分值**做补间，`0 → 242818` 中间要经过几十个无意义的
/// 数，520ms 才停在真值上。它在「打开首页」时最难受：账单流首帧没有数据，
/// 卡片先渲染 `0.00`，真实数据到达时就从 0 数上去——每次进首页都要等半秒
/// 才能读到本月支出。
void main() {
  const style = TextStyle(fontSize: 40, color: Color(0xFFFFFFFF));

  Widget host(String digits, {double motionScale = 1}) => MaterialApp(
    theme: ThemeData(
      extensions: <ThemeExtension<dynamic>>[AppMotion(scale: motionScale)],
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: AnimatedMoneyText(
          segments: [
            const MoneySegment('¥', style: TextStyle(fontSize: 22)),
            MoneySegment(digits, style: style, animate: true),
          ],
        ),
      ),
    ),
  );

  /// 当前金额里每个字形的文案（按从左到右）。过渡途中同一格上新旧字形并存，
  /// 所以这个列表在动画中会比静止时长。
  ///
  /// 只取 AnimatedMoneyText 子树里的：Scaffold / MaterialApp 自己也会带
  /// 一堆 Text 和过渡组件进来。
  List<String> glyphs(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(AnimatedMoneyText),
          matching: find.byType(Text),
        ),
      )
      .map((text) => text.data!)
      .toList();

  testWidgets('首次出现不做过渡，数字直接在位', (tester) async {
    // 首页流的首帧就是这一下。连它都要动画的话，用户会看到「数字滑进来」
    // 紧接着「数字翻一次」两段动作，读起来像闪了一下。
    await tester.pumpWidget(host('0.00'));
    await tester.pump();

    // 每格只有一个字形 = 没有任何一格在做过渡。
    expect(glyphs(tester), ['¥', '0', '.', '0', '0']);
  });

  testWidgets('数值变化时每一位只走一步，不经过中间数', (tester) async {
    await tester.pumpWidget(host('11.11'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(host('99.99'));
    await tester.pump(const Duration(milliseconds: 100));

    // 过渡中段：每个数字位上同时挂着旧字形和新字形，且只有这两个。
    // 数值补间会在这里出现 4、5、6 这类中间数字。
    final mid = glyphs(tester).where((glyph) => glyph != '¥').toSet();
    expect(mid, {'1', '9', '.'}, reason: '出现了 1 和 9 之外的数字，说明还在按数值补间');

    await tester.pumpAndSettle();
    expect(glyphs(tester), ['¥', '9', '9', '.', '9', '9']);
  });

  testWidgets('总时长只由动画决定，和数值大小无关', (tester) async {
    // 数值补间下「0 → 9」和「0 → 99999999」都要走满同一段时长，但后者中途
    // 要翻过八位数；逐位则两者完全一样：各自一步。
    // pumpAndSettle 返回的是走到静止用了多少帧，正好当时长的代理量。
    Future<int> settleFrames(String from, String to) async {
      await tester.pumpWidget(host(from));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(to));
      return tester.pumpAndSettle();
    }

    final small = await settleFrames('0.01', '0.09');
    final large = await settleFrames('0.01', '99,999,999.99');
    expect(small, large, reason: '总时长跟着位数变了，说明不是「每位一步」');
  });

  test('逐位时长明显短于统计页图表那档', () {
    // 那边补间的是一条曲线的形状，眼睛要跟着走完；这里每位只走一步，
    // 走完就没有新信息了。原来两者共用 520ms 才显得「跳太久」。
    expect(kMoneyDigitDuration.inMilliseconds, lessThanOrEqualTo(300));
  });

  testWidgets('位数变多时已有的位各自翻值，不整排洗牌', (tester) async {
    // key 按「从右数第几位」给。按从左数的下标给 key 的话，前面插进一位就会
    // 让所有位的 key 平移一格，每一位都被当成换了字符，整排一起动画。
    await tester.pumpWidget(host('9.99'));
    await tester.pumpAndSettle();
    final before = tester.widget<Text>(find.text('.'));

    await tester.pumpWidget(host('12.34'));
    await tester.pumpAndSettle();

    expect(glyphs(tester), ['¥', '1', '2', '.', '3', '4']);
    // 小数点在从右数第 2 位，前后都是它，格子该被复用而不是重建。
    expect(tester.widget<Text>(find.text('.')).style, before.style);
  });

  testWidgets('千分位逗号落在固定的从右位置，跨量级时不重建', (tester) async {
    // 小数部分恒为两位，所以逗号的从右位置是 6、10、14…，右对齐下天然稳定。
    await tester.pumpWidget(host('9,999.99'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host('10,000.00'));
    await tester.pumpAndSettle();

    expect(glyphs(tester), ['¥', '1', '0', ',', '0', '0', '0', '.', '0', '0']);
  });

  testWidgets('逗号和小数点不套过渡，只有数字位动', (tester) async {
    await tester.pumpWidget(host('1,111.11'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host('2,222.22'));
    await tester.pump(const Duration(milliseconds: 100));

    // 六个数字位各有新旧两个字形 = 12 个，加上不动的逗号、小数点和 ¥。
    final all = glyphs(tester);
    expect(all.where((glyph) => glyph == ',').length, 1, reason: '逗号被套了过渡');
    expect(all.where((glyph) => glyph == '.').length, 1, reason: '小数点被套了过渡');
  });

  testWidgets('动效关闭档直接换掉，一帧到位', (tester) async {
    await tester.pumpWidget(host('11.11', motionScale: 0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host('99.99', motionScale: 0));
    await tester.pump();

    // 关闭档压根不拆格：整段就是一个 Text。既省掉一堆 widget，也让
    // find.text 这类断言在这一档下照常可用。
    expect(glyphs(tester), ['¥', '99.99']);
  });

  testWidgets('整体给出完整金额的语义标签', (tester) async {
    // 拆成逐位之后，读屏会一个字符一个字符念，必须由外层补回完整文本。
    await tester.pumpWidget(host('2,428.18'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('¥2,428.18'), findsOneWidget);
  });
}
