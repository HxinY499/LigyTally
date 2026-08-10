import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/features/ledger/application/amount_expression.dart';

void main() {
  group('AmountExpression.evaluate', () {
    test('plain number', () {
      expect(AmountExpression.evaluate('12.5'), 12.5);
    });

    test('empty is zero', () {
      expect(AmountExpression.evaluate(''), 0);
    });

    test('addition chain', () {
      expect(AmountExpression.evaluate('3.5+7+12'), 22.5);
    });

    test('subtraction', () {
      expect(AmountExpression.evaluate('20-5.5'), 14.5);
    });

    test('mixed add and subtract', () {
      expect(AmountExpression.evaluate('100+20-30'), 90);
    });

    test('trailing operator is ignored', () {
      expect(AmountExpression.evaluate('10+'), 10);
    });

    test('avoids floating point drift', () {
      expect(AmountExpression.evaluate('0.1+0.2'), 0.3);
    });
  });

  group('AmountExpression.hasOperator', () {
    test('detects operator', () {
      expect(AmountExpression.hasOperator('3+5'), true);
      expect(AmountExpression.hasOperator('12.5'), false);
    });
  });

  group('AmountExpression.format', () {
    test('empty stays empty', () {
      expect(AmountExpression.format(''), '');
    });

    test('groups thousands in integer part', () {
      expect(AmountExpression.format('12000'), '12,000');
      expect(AmountExpression.format('1234567'), '1,234,567');
    });

    test('leaves short integers alone', () {
      expect(AmountExpression.format('999'), '999');
    });

    // 用户可能正停在 `12.` 或 `12.5`，补零/截断会让显示与下一次按键对不上。
    test('keeps partial decimals verbatim', () {
      expect(AmountExpression.format('12.'), '12.');
      expect(AmountExpression.format('12.5'), '12.5');
      expect(AmountExpression.format('12000.5'), '12,000.5');
    });

    test('pads operators and uses real minus sign', () {
      expect(AmountExpression.format('3.5+7'), '3.5 + 7');
      expect(AmountExpression.format('20-5'), '20 − 5');
    });

    test('groups every segment of a chain', () {
      expect(AmountExpression.format('12000+3500'), '12,000 + 3,500');
    });

    test('grouped false keeps raw digits', () {
      expect(AmountExpression.format('12000', grouped: false), '12000');
    });

    test('trailing operator survives formatting', () {
      expect(AmountExpression.format('10+'), '10 + ');
    });
  });
}
