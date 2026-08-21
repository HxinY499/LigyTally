import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/shared/widgets/app_widgets.dart';

/// 页头一致性回归测试。
///
/// 页头是全应用出现频率最高的元素，一旦某页自绘就会破坏统一感
/// （历史上统计页用过 22 号字 + 随内容滚走）。这里把四条硬性规则锁死：
///
/// 1. 一级页展开态：标题左缘 / 顶边 / 字号完全相同（切 Tab 不跳动）
/// 2. 紧凑态（一级页折叠后、二级页默认、搜索框）：标题垂直中心线 / 字号相同
/// 3. 操作图标与标题垂直中心对齐（展开跟大标题、折叠收到 56/2，右缘恒为 gutter）
/// 4. 毛玻璃**只在内容穿过后存在**：静止时不该挂 BackdropFilter
void main() {
  final forui = buildForuiTheme();

  Widget host(Widget child) => MaterialApp(
    theme: forui.toApproximateMaterialTheme(),
    builder: (context, c) => FTheme(
      data: forui,
      child: FToaster(child: c!),
    ),
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
    testWidgets('展开态：大标题左缘对齐 gutter，图标与标题同一高度', (tester) async {
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

      final title = tester.getRect(find.text('统计'));
      expect(title.left, kAppHeaderGutter);
      expect(fontSizeOf(tester, '统计'), 28, reason: '展开态是大标题');

      final icon = tester.getRect(find.byIcon(FLucideIcons.search));
      expect(
        icon.center.dy,
        closeTo(title.center.dy, 1.5),
        reason: '不滚动时图标也要和大标题同一条水平线',
      );
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

    testWidgets('折叠态：标题与图标收到紧凑条同一中心线，浮出毛玻璃', (tester) async {
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

      await collapse(tester);

      expect(fontSizeOf(tester, '统计'), 20, reason: '折叠后回到紧凑字号');
      expect(tester.getRect(find.text('统计')).center.dy, centerLine);
      expect(tester.getRect(find.text('统计')).left, kAppHeaderGutter);
      expect(
        tester.getRect(find.byIcon(FLucideIcons.search)).center.dy,
        centerLine,
        reason: '折叠后图标和大标题一起收到紧凑条中心',
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

    testWidgets('默认就是紧凑条：标题与返回箭头同一行，没有大标题', (tester) async {
      await tester.pumpWidget(host(secondary()));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(fontSizeOf(tester, '分类管理'), 20, reason: '二级页不做大标题');
      expect(tester.getRect(find.text('分类管理')).center.dy, centerLine);
      expect(
        tester.getRect(find.text('分类管理')).left,
        56,
        reason: '有返回时标题让到箭头右侧',
      );

      final back = tester.getRect(find.byIcon(FLucideIcons.chevronLeft));
      expect(back.left, kAppHeaderGutter, reason: '返回图标光学左缘落在 gutter');
      expect(back.center.dy, centerLine);
      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: '静止时内容还没穿过，不该挂毛玻璃',
      );
    });

    testWidgets('滚动不改变页头几何，内容穿过后才出毛玻璃', (tester) async {
      await tester.pumpWidget(host(secondary()));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final titleBefore = tester.getRect(find.text('分类管理'));
      final backBefore = tester.getRect(find.byIcon(FLucideIcons.chevronLeft));

      await collapse(tester);

      expect(tester.getRect(find.text('分类管理')), titleBefore);
      expect(tester.getRect(find.byIcon(FLucideIcons.chevronLeft)), backBefore);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
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

  group('壁纸模式下页头自带蒙版', () {
    /// 铬层底板的填充色。它是 [AppChromeGlass] 里那层 DecoratedBox。
    Color? chromeFill(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(AppChromeGlass),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    Widget wallpaperHost(Widget child) {
      const config = AppearanceConfig(
        wallpaper: WallpaperConfig(enabled: true, opacity: 1),
      );
      final forui = foruiThemeFor(Brightness.light, config);
      return MaterialApp(
        theme: buildMaterialTheme(Brightness.light, config),
        builder: (context, c) => FTheme(
          data: forui,
          child: FToaster(child: c!),
        ),
        home: child,
      );
    }

    testWidgets('没指定底色的页头，在壁纸下自己铺一层实色', (tester) async {
      // 浓度拖到 1.0 时壁纸层那层蒙版已经完全消失，页头如果也跟着透明，
      // 20px 的标题就直接压在照片上。这一层是它的可读性下限。
      await tester.pumpWidget(
        wallpaperHost(
          Scaffold(body: AppPageHeader(title: '设置', slivers: longSlivers())),
        ),
      );
      await tester.pumpAndSettle();

      final fill = chromeFill(tester)!;
      expect(fill.a, greaterThan(0.5), reason: '页头在壁纸下没有自己的底');
      expect(fill.a, lessThan(1), reason: '页头糊成实色了，壁纸完全看不见');
    });

    testWidgets('蒙版不跟着折叠变薄——内容穿过来时正是最需要底的时候', (tester) async {
      await tester.pumpWidget(
        wallpaperHost(
          Scaffold(body: AppPageHeader(title: '设置', slivers: longSlivers())),
        ),
      );
      await tester.pumpAndSettle();
      final resting = chromeFill(tester)!.a;

      await collapse(tester);
      expect(chromeFill(tester)!.a, resting);
    });

    testWidgets('显式传了透明的页面（记一笔）不被蒙版糊住', (tester) async {
      // 这条是整个改动的分界线：页头必须分清「调用方没指定」和「调用方
      // 指定了透明」。记一笔页要让自己铺的账单图背板透过页头，
      // 给它加一层蒙版就等于把那张图的上半截盖掉。
      await tester.pumpWidget(
        wallpaperHost(
          Scaffold(
            body: AppTopBar(
              backgroundColor: Colors.transparent,
              title: '记一笔',
              slivers: longSlivers(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(chromeFill(tester), Colors.transparent);
    });
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
    expect(tester.getRect(find.text('keypad')), panel, reason: '常驻面板不随内容滚动');
    expect(
      tester.getRect(find.byType(CustomScrollView)).bottom,
      panel.top,
      reason: '滚动区止于面板上沿，二者不重叠',
    );
  });
}
