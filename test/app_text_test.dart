import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/theme/app_text.dart';
import 'package:ligy_tally/shared/widgets/app_page_header.dart';

void main() {
  group('字距按字号推导', () {
    test('正文档位不收紧，12px 及以下恒为 0', () {
      // 小字的字腔本来就紧，再收会粘连；正文保持 0 也让绝大多数调用点
      // 不必关心这条规则。
      for (final size in [8.0, 10.0, 11.0, 12.0]) {
        expect(AppText.tracking(size), 0, reason: '$size 被收紧了');
      }
    });

    test('字号越大收得越紧，且一路单调', () {
      // 「大字显松散」是这条规则存在的唯一理由，所以单调性是它的核心性质：
      // 任何一段出现反转，就会有两个相邻字号的收紧量对不上。
      final sizes = [13.0, 15.0, 16.0, 20.0, 27.0, 28.0, 40.0];
      var previous = 0.0;
      for (final size in sizes) {
        final tracking = AppText.tracking(size);
        expect(tracking, lessThan(0), reason: '$size 没有收紧');
        expect(tracking, lessThan(previous), reason: '$size 处收紧量反转了');
        previous = tracking;
      }
    });

    test('收紧量封顶，超大字号不会挤成一团', () {
      // 不封顶的话 100px 会收到 -3.6，字与字开始互相咬。
      final capped = AppText.tracking(400);
      expect(capped / 400, closeTo(-0.030, 0.0001));
    });

    test('页头那两个人工调准过的锚点没有被改变观感', () {
      // 这条规则的曲线是按页头原有的 -0.2（20px 折叠态）与 -0.6（28px 展开态）
      // 拟合的。锚点漂了就意味着换用统一规则后页头的观感变了，
      // 而那次替换的前提恰恰是「观感不变」。
      expect(AppText.tracking(20), closeTo(-0.2, 0.05));
      expect(AppText.tracking(28), closeTo(-0.6, 0.05));
    });

    testWidgets('页头标题真的用了这条规则，没有留下写死的字距', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppPageHeader(title: '统计', slivers: [SliverToBoxAdapter()]),
          ),
        ),
      );
      final title = tester.widget<Text>(find.text('统计'));
      final size = title.style!.fontSize!;
      expect(
        title.style!.letterSpacing,
        closeTo(AppText.tracking(size), 0.001),
      );
    });
  });

  group('金额字阶', () {
    test('四档从小到大，且都落在收紧区间里', () {
      const ladder = [
        AppText.moneySm,
        AppText.moneyMd,
        AppText.moneyLg,
        AppText.moneyXl,
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(ladder[i], greaterThan(ladder[i - 1]));
      }
      // 金额是「数据」，四档全部大于正文档位上限，所以每一档都该有负字距。
      for (final size in ladder) {
        expect(AppText.tracking(size), lessThan(0));
      }
    });

    test('money() 的字距不是手填的，而是从字号算出来的', () {
      // 这是本 token 存在的意义：调用点给不了一个「和字号不匹配」的字距。
      for (final size in [AppText.moneySm, AppText.moneyXl]) {
        final style = AppText.money(size, color: const Color(0xFF000000));
        expect(style.letterSpacing, AppText.tracking(size));
        expect(style.fontSize, size);
      }
    });

    test('money() 不设置等宽数字特性', () {
      // 等宽数字是用户可关的一档外观设置，挂在 textTheme 上靠继承生效。
      // 这里显式写一遍会把那档设置钉死，用户关掉之后金额仍是等宽的。
      final style = AppText.money(
        AppText.moneyXl,
        color: const Color(0xFF000000),
      );
      expect(style.fontFeatures, isNull);
    });
  });
}
