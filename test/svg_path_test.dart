import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/features/ai/presentation/svg_path.dart';

void main() {
  test('直线闭合后边界就是矩形', () {
    final bounds = parseSvgPath('M0 0 L10 0 L10 10 Z').getBounds();
    expect(bounds.left, 0);
    expect(bounds.top, 0);
    expect(bounds.right, 10);
    expect(bounds.bottom, 10);
  });

  test('相对弧线能落到终点一侧', () {
    final path = parseSvgPath('M10 10 a5 5 0 1 0 10 0');
    final bounds = path.getBounds();
    expect(bounds.left, lessThan(11));
    expect(bounds.right, greaterThan(19));
  });

  test('三家标志都落在 24 的画布里', () {
    for (final name in ['deepseek', 'kimi', 'zhipu']) {
      final svg = File('assets/branding/$name.svg').readAsStringSync();
      final data = RegExp(r'd="([^"]+)"').firstMatch(svg)!.group(1)!;
      final bounds = parseSvgPath(data).getBounds();
      expect(bounds.width, greaterThan(8), reason: name);
      expect(bounds.height, greaterThan(8), reason: name);
      expect(bounds.left, greaterThan(-0.5), reason: name);
      expect(bounds.top, greaterThan(-0.5), reason: name);
      expect(bounds.right, lessThan(24.5), reason: name);
      expect(bounds.bottom, lessThan(24.5), reason: name);
    }
  });
}
