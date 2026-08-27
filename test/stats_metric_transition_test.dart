import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/theme/app_motion.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/statistics/presentation/stats_states.dart';

/// 切换统计口径（支出/收入/结余）时，卡片内容要淡入淡出，不能硬切。
///
/// ## 这条用例为什么不能只断言「最后显示的是新数据」
///
/// 修好之前，最终态一直是对的——问题全在过程里：口径切换换的是 stream 本身，
/// 而 [StreamBuilder] 换 stream 时保留旧 data，所以既不经过加载态、也不改
/// 数据态的 key，[AnimatedSwitcher] 把它当成「同一个 child 更新」直接换掉。
/// 只看首尾两帧的用例对这个 bug 完全免疫。
///
/// 所以这里逐帧读**每个 Text 被祖先 FadeTransition 累乘出来的不透明度**，
/// 断言中途确实存在「旧的在淡出、新的在淡入」这一段。
void main() {
  group('切换统计口径时内容淡入淡出', () {
    testWidgets('过渡中途旧内容半透明、新内容半透明地共存', (tester) async {
      final harness = await _pump(tester);

      await harness.switchTo(1, '收入');

      // 走到过渡中段。durTap 是 220ms，取 100ms 处。
      await tester.pump(const Duration(milliseconds: 100));
      final mid = _opacities(tester);

      expect(
        mid.keys,
        containsAll(['DATA:支出', 'DATA:收入']),
        reason: '过渡中段应当新旧内容同时在树上；只有一个说明还是硬切',
      );
      expect(mid['DATA:支出'], lessThan(0.9), reason: '旧内容没有在淡出');
      expect(mid['DATA:支出'], greaterThan(0.0));
      expect(mid['DATA:收入'], lessThan(0.9), reason: '新内容没有在淡入');
      expect(mid['DATA:收入'], greaterThan(0.0));

      await tester.pumpAndSettle();
      final settled = _opacities(tester);
      expect(settled.keys, ['DATA:收入']);
      expect(settled['DATA:收入'], 1.0);
    });

    testWidgets('同一口径下的数据刷新不触发过渡', (tester) async {
      // dataKey 只认口径。同口径下的数据刷新（用户新增一笔账单）必须是原地
      // 更新，否则每次写库都会让整张卡闪一下。
      final harness = await _pump(tester);

      harness.emit(0, '支出2');
      // 两次 pump：stream 事件在微任务里派发，第一次 pump 之后才落到
      // StreamBuilder 上。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final frame = _opacities(tester);
      expect(frame.keys, ['DATA:支出2'], reason: '同口径刷新却出现了新旧共存');
      expect(frame['DATA:支出2'], 1.0, reason: '同口径刷新不该有淡入');
    });

    testWidgets('动效关闭档下直接换掉，不留过渡', (tester) async {
      final harness = await _pump(tester, motionScale: 0);

      await harness.switchTo(1, '收入');
      await tester.pump(const Duration(milliseconds: 1));

      final frame = _opacities(tester);
      expect(frame.keys, ['DATA:收入']);
      expect(frame['DATA:收入'], 1.0);
    });

    testWidgets('内容换高时高度是补间的，不是一步跳到位', (tester) async {
      // 淡入淡出期间 AnimatedSwitcher 按新旧内容的最大值定尺，旧内容被移除的
      // 那一刻高度会掉下来。分类构成卡从 6 行支出切到 1 行收入要掉三百多像素，
      // 下方整块内容跟着往上一跳。这条锁的是「那一下被 AnimatedSize 接住了」。
      final harness = await _pump(tester, tall: true);
      final finder = find.byType(StatsStreamBuilder<String>);
      final before = tester.getSize(finder).height;

      await harness.switchTo(1, '收入');
      final heights = <double>[];
      for (var frame = 0; frame < 16; frame++) {
        await tester.pump(const Duration(milliseconds: 40));
        heights.add(tester.getSize(finder).height);
      }
      await tester.pumpAndSettle();
      final after = tester.getSize(finder).height;

      expect(after, lessThan(before), reason: '新内容本该更矮');
      expect(
        heights.any((height) => height > after && height < before),
        isTrue,
        reason: '高度从 $before 直接跳到 $after，中间没有任何补间值：$heights',
      );
    });
  });
}

/// 建一棵最小的树：一个按口径换 stream 的 [StatsStreamBuilder]。
///
/// 刻意不搬整个统计页进来：那需要真数据库、五条 stream 和图表绘制，
/// 而这条用例要验的东西全在 [StatsStreamBuilder] 这一层。
Future<_Harness> _pump(
  WidgetTester tester, {
  double motionScale = 1,
  bool tall = false,
}) async {
  final controllers = <int, StreamController<String>>{
    0: StreamController<String>.broadcast(),
    1: StreamController<String>.broadcast(),
  };
  addTearDown(() {
    for (final controller in controllers.values) {
      controller.close();
    }
  });

  var kind = 0;
  late StateSetter setOuter;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme().copyWith(
        extensions: <ThemeExtension<dynamic>>[
          AppColors.light,
          AppMotion(scale: motionScale),
        ],
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return StatsStreamBuilder<String>(
                dataKey: kind,
                stream: controllers[kind]!.stream,
                loading: const Text('SKELETON'),
                // 支出那份更高：验高度定尺时要能区分出两份内容。
                builder: (context, data) => SizedBox(
                  height: tall && data.startsWith('支出') ? 240 : 60,
                  child: Text('DATA:$data'),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  controllers[0]!.add('支出');
  await tester.pumpAndSettle();

  return _Harness(
    tester: tester,
    controllers: controllers,
    setKind: (value) => setOuter(() => kind = value),
  );
}

class _Harness {
  _Harness({
    required this.tester,
    required this.controllers,
    required this.setKind,
  });

  final WidgetTester tester;
  final Map<int, StreamController<String>> controllers;
  final void Function(int kind) setKind;

  void emit(int kind, String value) => controllers[kind]!.add(value);

  /// 切到 [kind] 并让新 stream 吐出 [value]。
  ///
  /// 中间那次 `pump` 不能省：broadcast stream 会丢掉「还没有监听者」时发出的
  /// 事件，必须先让新的订阅建立起来。这也正好复现真实时序——切换口径的那一帧
  /// 屏幕上还是旧数据。
  Future<void> switchTo(int kind, String value) async {
    setKind(kind);
    await tester.pump();
    controllers[kind]!.add(value);
    await tester.pump();
  }
}

/// 树上每个 Text 的文案 → 它被各层 [FadeTransition] 累乘后的实际不透明度。
Map<String, double> _opacities(WidgetTester tester) {
  final result = <String, double>{};
  for (final element in find.byType(Text).evaluate()) {
    final text = element.widget as Text;
    var opacity = 1.0;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is FadeTransition) opacity *= widget.opacity.value;
      return true;
    });
    result[text.data!] = opacity;
  }
  return result;
}
