import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/shared/widgets/app_widgets.dart';

/// 页头一致性回归测试。
///
/// 页头是全应用出现频率最高的元素，一旦某页自绘就会破坏统一感
/// （历史上统计页用过 22 号字 + 随内容滚走）。这里把四条硬性规则锁死：
///
/// 1. 展开态：所有页面标题左缘 / 顶边 / 字号完全相同（跨页切换不跳动）
/// 2. 折叠态：所有页面标题垂直中心线 / 字号完全相同
/// 3. 操作行图标位置**不随折叠变化**（中心线恒为 56/2，右缘恒为 gutter）
/// 4. 毛玻璃**只在吸顶后存在**：展开态不该挂 BackdropFilter，
///    它每帧都要把背后像素读回来重新模糊，而展开态背后根本没有内容
void main() {
  final forui = buildForuiTheme();

  Widget host(Widget child) => MaterialApp(
    theme: forui.toApproximateMaterialTheme(),
    builder: (context, c) => FTheme(data: forui, child: FToaster(child: c!)),
    home: child,
  );

  /// 测试视口宽度（flutter_test 默认 800×600）。
  const viewportWidth = 800.0;

  /// 折叠态图标与标题的公共中心线。
  ///
  /// 测试环境的 MediaQuery.padding 为 0，所以页头 extent 里不含状态栏，
  /// 几何可以直接和令牌对照。
  const centerLine = kAppHeaderHeight / 2;

  /// 够长的内容，保证能滚出折叠所需距离。
  List<Widget> longSlivers() => [
    SliverList.list(
      children: [
        for (var i = 0; i < 40; i++)
          SizedBox(height: 60, child: Text('row $i')),
      ],
    ),
  ];

  double fontSizeOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.fontSize!;

  /// 滚动到完全折叠。拖动量需 > 折叠距离（展开高 - 折叠高）。
  Future<void> collapse(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
  }

  group('一级页页头', () {
    testWidgets('展开态：大标题左缘对齐 gutter，图标居中在操作行', (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            body: AppPageHeader(
              title: '统计',
              actions: [
                AppHeaderAction(icon: FLucideIcons.search, onTap: () {}),
              ],
              slivers: longSlivers(),
            ),
          ),
        ),
      );

      expect(tester.getRect(find.text('统计')).left, kAppHeaderGutter);
      expect(fontSizeOf(tester, '统计'), 28, reason: '展开态是大标题');

      final icon = tester.getRect(find.byIcon(FLucideIcons.search));
      expect(icon.center.dy, centerLine, reason: '图标居中在顶部操作行，不跟着大标题下移');
      expect(
        viewportWidth - icon.right,
        kAppHeaderGutter,
        reason: '图标光学右缘与标题左缘对称',
      );

      expect(
        tester.getRect(find.text('row 0')).top,
        kAppHeaderExpandedHeight,
        reason: '内容起始线就是页头展开高度 —— 这是「切 Tab 不上下跳」的落点',
      );
      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: '展开态页头背后没有内容，不该白烧一次离屏模糊',
      );
    });

    testWidgets('折叠态：标题缩到紧凑条并垂直居中，图标位置不变，浮出毛玻璃', (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            body: AppPageHeader(
              title: '统计',
              actions: [
                AppHeaderAction(icon: FLucideIcons.search, onTap: () {}),
              ],
              slivers: longSlivers(),
            ),
          ),
        ),
      );
      final iconBefore = tester.getRect(find.byIcon(FLucideIcons.search));

      await collapse(tester);

      expect(fontSizeOf(tester, '统计'), 20, reason: '折叠后回到紧凑字号');
      expect(tester.getRect(find.text('统计')).center.dy, centerLine);
      expect(tester.getRect(find.text('统计')).left, kAppHeaderGutter);
      expect(
        tester.getRect(find.byIcon(FLucideIcons.search)),
        iconBefore,
        reason: '折叠过程中图标必须绝对静止，否则观感会漂',
      );
      expect(
        find.byType(BackdropFilter),
        findsOneWidget,
        reason: '吸顶后内容从页头背后穿过，此时才需要毛玻璃',
      );
    });
  });

  group('二级页页头', () {
    Widget secondary() => Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                body: AppTopBar(
                  title: '分类管理',
                  actions: [
                    AppHeaderAction(icon: FLucideIcons.plus, onTap: () {}),
                  ],
                  slivers: longSlivers(),
                ),
              ),
            ),
          ),
          child: const Text('go'),
        ),
      ),
    );

    testWidgets('展开态：返回箭头独占一行，大标题左缘与一级页同线', (tester) async {
      await tester.pumpWidget(host(secondary()));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.text('分类管理')).left,
        kAppHeaderGutter,
        reason:
            '这是「进二级页标题不横跳」的硬保证：'
            '返回箭头在标题上方，不再横向挤压标题',
      );
      expect(fontSizeOf(tester, '分类管理'), 28);

      final back = tester.getRect(find.byIcon(FLucideIcons.chevronLeft));
      expect(back.left, kAppHeaderGutter, reason: '返回图标光学左缘同样落在 gutter');
      expect(back.center.dy, centerLine);
    });

    testWidgets('折叠态：标题收进箭头那一行，箭头不动', (tester) async {
      await tester.pumpWidget(host(secondary()));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final backBefore = tester.getRect(find.byIcon(FLucideIcons.chevronLeft));

      await collapse(tester);

      expect(fontSizeOf(tester, '分类管理'), 20);
      expect(tester.getRect(find.text('分类管理')).center.dy, centerLine);
      expect(
        tester.getRect(find.byIcon(FLucideIcons.chevronLeft)),
        backBefore,
        reason: '返回箭头在折叠前后必须完全不动',
      );
    });
  });

  testWidgets('一级页与二级页：展开态标题几何完全重合', (tester) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: AppPageHeader(title: 'A', slivers: longSlivers()),
        ),
      ),
    );
    final primary = tester.getRect(find.text('A'));

    await tester.pumpWidget(
      host(
        Scaffold(
          body: AppTopBar(title: 'A', slivers: longSlivers()),
        ),
      ),
    );
    final secondary = tester.getRect(find.text('A'));

    expect(secondary.left, primary.left, reason: '跨页切换标题不得横向跳动');
    expect(secondary.top, primary.top, reason: '跨页切换标题不得纵向跳动');
  });

  testWidgets('搜索框模式：页头固定为紧凑高度，输入框不被缩放', (tester) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: AppPageHeader(
            content: const SizedBox(height: 38, child: TextField()),
            actions: [AppHeaderAction(icon: FLucideIcons.x, onTap: () {})],
            slivers: longSlivers(),
          ),
        ),
      ),
    );

    expect(tester.getRect(find.byType(TextField)).left, kAppHeaderGutter);
    expect(tester.getRect(find.byType(TextField)).center.dy, centerLine);

    // 搜索态不该有大标题空间，滚动也不改变高度。
    final before = tester.getRect(find.byType(TextField));
    await collapse(tester);
    expect(
      tester.getRect(find.byType(TextField)),
      before,
      reason: '搜索框模式恒为折叠态，滚动不该让它移动',
    );
  });

  testWidgets('底部常驻面板：不进滚动体，内容不会滚到它背后', (tester) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: AppTopBar(
            title: '记一笔',
            slivers: longSlivers(),
            bottom: const SizedBox(height: 120, child: Text('keypad')),
          ),
        ),
      ),
    );

    final panel = tester.getRect(find.text('keypad'));
    await collapse(tester);
    expect(
      tester.getRect(find.text('keypad')),
      panel,
      reason: '常驻面板不随内容滚动',
    );
    expect(
      tester.getRect(find.byType(CustomScrollView)).bottom,
      panel.top,
      reason: '滚动区止于面板上沿，二者不重叠',
    );
  });
}
