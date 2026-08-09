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
}
