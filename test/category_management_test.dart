import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/database/default_categories.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/utils/category_icons.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/features/settings/presentation/category_management_screen.dart';

void main() {
  group('分类的数据层约束', () {
    test('同层级重名会被拦住，不同层级 / 不同收支侧互不影响', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final all = await database.exportCategories();
      final food = all.singleWhere((item) => item.name == '餐饮');

      // 支出侧已经有一级分类「餐饮」。
      expect(await database.categoryNameExists(kind: 0, name: '餐饮'), isTrue);
      // 收入侧没有——两侧分类互不相干，同名合法。
      expect(await database.categoryNameExists(kind: 1, name: '餐饮'), isFalse);
      // 「三餐」是餐饮的子分类，不算一级重名。
      expect(await database.categoryNameExists(kind: 0, name: '三餐'), isFalse);
      expect(
        await database.categoryNameExists(
          kind: 0,
          name: '三餐',
          parentId: food.id,
        ),
        isTrue,
      );
      // 编辑自己时要排除自己，否则「只改图标不改名」会被误判成重名。
      expect(
        await database.categoryNameExists(
          kind: 0,
          name: '餐饮',
          excludeId: food.id,
        ),
        isFalse,
      );
    });

    test('新建分类可以带图标，不再一律是「其他」', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await database.addCategory(
        id: 'probe-with-icon',
        kind: 0,
        name: '健身',
        iconKey: 'sport',
      );
      final created = (await database.exportCategories()).singleWhere(
        (item) => item.id == 'probe-with-icon',
      );
      expect(created.iconKey, 'sport');
      expect(created.level, 1);
    });

    test('改名换图标不会动层级和归属', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final meals = (await database.exportCategories()).singleWhere(
        (item) => item.name == '三餐',
      );

      await database.updateCategory(
        id: meals.id,
        name: '早午晚饭',
        iconKey: 'fine_dining',
      );
      final updated = (await database.exportCategories()).singleWhere(
        (item) => item.id == meals.id,
      );
      expect(updated.name, '早午晚饭');
      expect(updated.iconKey, 'fine_dining');
      // 换父级等于悄悄改写历史账单的归类，所以这两项必须原样保留。
      expect(updated.parentId, meals.parentId);
      expect(updated.level, meals.level);
    });

    test('停用不能把一侧的可用一级分类清空', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final roots = (await database.exportCategories())
          .where((item) => item.kind == 0 && item.level == 1)
          .toList();

      // 逐个停用支出的一级分类，留最后一个。
      for (final root in roots.take(roots.length - 1)) {
        expect(
          await database.setCategoryActive(root.id, false),
          CategoryToggleResult.ok,
        );
      }
      // 最后一个必须被拦住——否则记账页的分类选择器会空掉，没法记账。
      // 删除路径早有同样的约束，停用是软删除，不该能绕过它。
      expect(
        await database.setCategoryActive(roots.last.id, false),
        CategoryToggleResult.lastRoot,
      );
      final stillActive = (await database.exportCategories()).where(
        (item) => item.kind == 0 && item.level == 1 && item.isActive,
      );
      expect(stillActive, hasLength(1));
    });

    test('停用一级分类会连带停用它的子分类', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final food = (await database.exportCategories()).singleWhere(
        (item) => item.name == '餐饮',
      );

      await database.setCategoryActive(food.id, false);
      final children = (await database.exportCategories()).where(
        (item) => item.parentId == food.id,
      );
      expect(children, isNotEmpty);
      expect(children.every((item) => !item.isActive), isTrue);
    });
  });

  group('图标选择清单', () {
    test('清单里没有重复图形，也没有失效的 key', () {
      // 直接把 categoryIcons.keys 铺进选择网格，用户会看到十几对
      // 一模一样的格子（meal/restaurant 都是餐具、travel/flight 都是飞机）。
      // 这条锁住「按图形去重」这个决定。
      final glyphs = categoryIconChoices.map(categoryIcon).toList();
      expect(glyphs.toSet(), hasLength(glyphs.length));
      // key 必须都在映射表里，否则会静默回落到 receipt 兜底图标。
      for (final key in categoryIconChoices) {
        expect(categoryIcons.containsKey(key), isTrue, reason: '$key 不在映射表里');
      }
    });

    test('每个可选图标都归属某个分组，扁平清单与分组一致', () {
      // 原则之三：无组可归的图标说明它不属于记账语境，直接不收。
      // 扁平清单是由分组推导出来的，这条同时锁住「两者不会脱节」。
      final fromGroups = [
        for (final group in categoryIconGroups) ...group.keys,
      ];
      expect(categoryIconChoices, fromGroups);
      // 同一个 key 不该出现在两个分组里——用户会以为是两个不同图标。
      expect(fromGroups.toSet(), hasLength(fromGroups.length));
      for (final group in categoryIconGroups) {
        expect(group.keys, isNotEmpty, reason: '${group.label} 是空组');
        expect(group.label, isNotEmpty);
      }
    });

    test('覆盖了常见自建分类，不再让多个分类挤同一个图标', () {
      // 原则之一：覆盖优先于精简。这批分类以前无图可选，只能凑 car / finance
      // 之类，导致「加油 / 停车 / 洗车」三个分类共用一个图标、失去区分度。
      // 每一项都必须有**独占**的图形。
      const shouldCover = {
        '加油': 'fuel',
        '停车': 'parking',
        '话费': 'phone_bill',
        '住宿': 'hotel',
        '门票': 'ticket',
        '保险': 'insurance',
        '税': 'tax',
        '存钱': 'savings',
        '转账': 'transfer',
        '订阅': 'subscription',
        '日用品': 'household',
        '家电': 'appliance',
        '家具': 'furniture',
        '装修': 'renovation',
        '奶茶': 'milk_tea',
        '超市': 'supermarket',
      };
      for (final entry in shouldCover.entries) {
        expect(
          categoryIconChoices,
          contains(entry.value),
          reason: '「${entry.key}」没有可选图标',
        );
      }
      // 独占性由上一条的「无重复图形」保证，这里额外确认它们彼此不同图。
      final glyphs = shouldCover.values.map(categoryIcon).toSet();
      expect(glyphs, hasLength(shouldCover.length));
    });

    test('内置分类种子用到的图标 key 全部还在映射表里', () {
      // categoryIcons 的 key 是以字符串存进数据库、也写进导出 JSON 的。
      // 删 key 或改指向会让已有分类和老备份的图标变成兜底的 receipt，
      // 所以那张表只能加。这条守住向后兼容。
      for (final seed in defaultCategorySeeds) {
        expect(
          categoryIcons.containsKey(seed.iconKey),
          isTrue,
          reason: '种子「${seed.name}」的 ${seed.iconKey} 从映射表里消失了',
        );
      }
    });
  });

  group('分类管理页', () {
    Future<void> pump(WidgetTester tester, AppDatabase database) async {
      final forui = buildForuiTheme();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: forui.toApproximateMaterialTheme(),
            builder: (context, child) => FTheme(
              data: forui,
              child: FToaster(child: child!),
            ),
            home: const CategoryManagementScreen(),
          ),
        ),
      );
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

    testWidgets('小屏 + 键盘弹起时面板不溢出，图标区自动缩小', (tester) async {
      // 面板高度是算出来的，算错就会 RenderFlex overflow。最容易出事的组合是
      // 「小屏 + 键盘」——名称框是 autofocus 的，一打开就是这个状态。
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3;
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.reset);

      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      await tester.tap(find.text('添加子分类').first);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      // 键盘占掉 300 逻辑像素后，可用高度只剩 340。图标区必须缩到下限，
      // 而不是硬撑出一个溢出的面板。
      expect(tester.takeException(), isNull, reason: '面板不该溢出');
      expect(find.byIcon(FLucideIcons.imagePlus), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('一级分类各占一张卡，卡片阴影与首页日卡一致', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      expect(find.text('餐饮'), findsOneWidget);
      // 子分类直接铺在卡里，不用再点进去。
      expect(find.text('三餐'), findsOneWidget);

      // 卡片必须自己是 Material（白底 + 18 圆角 + 裁剪），
      // 否则水波会被不透明白底盖住，点击毫无反馈（首页踩过这个坑）。
      final cards = tester
          .widgetList<Material>(find.byType(Material))
          .where(
            (material) =>
                material.color == AppColors.surface &&
                material.borderRadius ==
                    const BorderRadius.all(Radius.circular(18)),
          )
          .toList();
      expect(cards, isNotEmpty);
      for (final card in cards) {
        expect(card.clipBehavior, Clip.antiAlias);
      }

      final shadowed = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .where(
            (decoration) =>
                decoration.borderRadius ==
                    const BorderRadius.all(Radius.circular(18)) &&
                decoration.boxShadow != null,
          )
          .toList();
      expect(shadowed, isNotEmpty);
      for (final card in shadowed) {
        expect(card.boxShadow, AppShadows.card);
      }

      await teardown(tester);
    });

    testWidgets('每张卡自带「添加子分类」——父级由入口决定，不再用下拉选', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      // 屏幕内可见的每张卡都自带入口（列表是懒加载的，只断言可见部分），
      // 用户看着哪张卡就往哪张卡里加，不用先去想「它是第几个一级分类」。
      expect(find.text('添加子分类'), findsWidgets);

      // 旧版对话框里的「所属层级」下拉必须已经消失。
      expect(find.text('所属层级'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);

      await teardown(tester);
    });

    testWidgets('新建面板能填名字、选图标，创建后落到正确的父级下', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      // 点「餐饮」卡片里的第一个「添加子分类」。
      await tester.tap(find.text('添加子分类').first);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      // 面板标题说明了归属，用户不需要再自己选父级。
      expect(find.text('新建子分类'), findsOneWidget);
      expect(find.text('归属「餐饮」'), findsOneWidget);
      // 图标区不再是一片无标题的连续网格，第一组标题就在视口里。
      expect(find.text('吃喝'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '夜宵');
      await tester.pump();
      await tester.tap(find.text('创建'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      final food = (await database.exportCategories()).singleWhere(
        (item) => item.name == '餐饮',
      );
      final created = (await database.exportCategories()).singleWhere(
        (item) => item.name == '夜宵',
      );
      expect(created.parentId, food.id);
      expect(created.level, 2);
      expect(created.kind, 0);

      await teardown(tester);
    });

    testWidgets('同层级重名会留在面板里报错，不写库', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      await tester.tap(find.text('添加子分类').first);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      // 「三餐」已经是餐饮的子分类。
      await tester.enterText(find.byType(TextField), '三餐');
      await tester.pump();
      await tester.tap(find.text('创建'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      // 面板不关闭：错误要能就地改，而不是关掉再重来一遍。
      expect(find.text('新建子分类'), findsOneWidget);
      expect(find.text('同一分类下已有「三餐」'), findsOneWidget);
      final meals = (await database.exportCategories()).where(
        (item) => item.name == '三餐',
      );
      expect(meals, hasLength(1));

      await teardown(tester);
    });

    testWidgets('停用的分类仍然列出来，并标出「已停用」', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final food = (await database.exportCategories()).singleWhere(
        (item) => item.name == '餐饮',
      );
      await database.setCategoryActive(food.id, false);
      await pump(tester, database);

      // 管理页必须用 activeOnly: false —— 否则停用等于弄丢了，
      // 用户再也找不回来重新启用。
      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('已停用'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('图标网格按组分段，且分组标题不吸顶', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      await tester.tap(find.text('添加子分类').first);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      // 120 个图标无序平铺就是图标海。分组标题是这块区域的导航，
      // 用户扫的是十来个词而不是一百多个图形。
      expect(find.text('吃喝'), findsOneWidget);

      // 但标题**不能吸顶**。这里有十一个分组，每个都 pinned 的话，
      // 往下滚时它们会一个个堆在顶上不走，十来行文字压掉整个视口，
      // 图标反被挤得看不见（真实踩过：满屏只剩一列灰色组名）。
      //
      // 只查分组标题自己的祖先链：页面上还有个合法的吸顶条
      // （背后分类管理页的收支切换），不能一竿子打死。
      expect(
        find.ancestor(
          of: find.text('吃喝'),
          matching: find.byType(SliverPersistentHeader),
        ),
        findsNothing,
      );

      // 往下滚一段，第一组的标题必须跟着滚出去。
      // 拖「吃喝」这个标题本身：背后的分类卡片上也有同名文字，
      // 按文字找会撞上（「购物」同时是组名和一级分类名）。
      final label = find.text('吃喝');
      final before = tester.getRect(label);
      await tester.drag(label, const Offset(0, -120));
      await tester.pump();
      expect(
        tester.getRect(label).top,
        lessThan(before.top),
        reason: '标题应随内容上移，而不是钉在原处',
      );

      await teardown(tester);
    });

    testWidgets('编辑已有分类时，图标区自动滚到它所在的那一组', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      // savings（存钱罐）在最后几组的「收支」里，离首屏很远。
      await database.addCategory(
        id: 'scroll-probe',
        kind: 0,
        name: '房租测试',
        iconKey: 'savings',
      );
      await pump(tester, database);

      // 滚到底找到这张卡再点它的卡头。
      await tester.scrollUntilVisible(find.text('房租测试'), 200);
      await tester.pump();
      await tester.tap(find.text('房租测试'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.text('编辑分类'), findsOneWidget);

      // 面板一打开就该停在「收支」组，否则用户看不到当前选中的图标，
      // 会以为自己从没选过。
      //
      // 这里断言的是**格子**而不是分组标题：标题是 SliverPersistentHeader，
      // 滚出视口后仍留在 widget 树里（find.text 照样能找到），
      // 而网格子项是懒加载的 —— 只有滚到附近才会被建出来。
      // 所以「savings 格子已建 + 第一组的格子没建」才真正证明滚动生效了。
      //
      // 按 ValueKey 而不是图形来找：同一个图标在页面别处也会出现
      // （名称行的预览圆片、背后卡片里的分类图标），按图形找会撞上。
      expect(find.byKey(const ValueKey('icon-cell-savings')), findsOneWidget);
      expect(find.byKey(const ValueKey('icon-cell-restaurant')), findsNothing);

      await teardown(tester);
    });
    testWidgets('页头的导出/导入按钮点得开菜单', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      // 这条锁的是一个真实存在过的死键：当时 AppHeaderAction 传了
      // `onTap: null` + `enabled: true`，指望外层的 FPopoverMenu 接管点击。
      // 但 forui 的 popover 只把 child 当锚点、不装手势（Material 的
      // PopupMenuButton 才会），于是按钮看起来是亮的、点了毫无反应，
      // 而因为视觉正常，一直没人发现。
      expect(find.text('导出分类配置'), findsNothing);

      await tester.tap(find.byIcon(FLucideIcons.arrowLeftRight));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(find.text('导出分类配置'), findsOneWidget);
      expect(find.text('导入并替换配置'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('图标选择器第一组就是上传入口', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      await tester.tap(find.text('添加子分类').first);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      // 上传入口必须在面板打开时就可见。排在 120 个内置图标后面等于藏起来，
      // 用户不会为了找它去滚十几屏。
      expect(find.text('自己的图片'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.imagePlus), findsOneWidget);
      // 第一组在最上面，所以内置图标的第一组标题也还在视口里。
      expect(find.text('吃喝'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('图标区吃满可用空间，不再是写死的 208', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      await tester.tap(find.text('添加子分类').first);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      // 原来图标区写死 208（约三行半格子），120 个图标要翻七八屏才看完。
      // 改成按可用空间算：测试屏只有 600 逻辑像素高都能拿到 276，
      // 真机（950+）上会宽裕得多。
      //
      // 找图标区的 CustomScrollView：页面上另有一个（分类管理页本身），
      // 所以从「自己的图片」这个只存在于图标区的标题往上找祖先。
      final picker = tester.getRect(
        find.ancestor(
          of: find.text('自己的图片'),
          matching: find.byType(CustomScrollView),
        ),
      );
      expect(picker.height, greaterThan(208), reason: '图标区应吃满可用空间，而不是固定 208');
      // 但不能吃满整屏：底部面板要露出上方背景，否则就成了全屏页，
      // 下滑关闭的手势也没了落点。
      expect(picker.height, lessThan(600));

      await teardown(tester);
    });

    testWidgets('已有自定义图标的分类，打开编辑面板时它占一格且是选中态', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.addCategory(
        id: 'custom-icon-probe',
        kind: 0,
        name: '自定义图',
        iconKey: customCategoryIconKey('11111111-2222-3333-4444-555555555555'),
      );
      await pump(tester, database);

      await tester.scrollUntilVisible(find.text('自定义图'), 200);
      await tester.pump();
      await tester.tap(find.text('自定义图'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(find.text('编辑分类'), findsOneWidget);
      // 网格里必须有一格代表这张图并且是选中态，否则用户看不到自己选的是
      // 哪个（内置图标那 120 格里没有一格会亮），会以为图丢了。
      expect(find.byKey(const ValueKey('icon-cell-custom')), findsOneWidget);
      // 图片文件在测试环境里不存在，应当回落到默认图标而不是抛异常 /
      // 留一块空白 —— 备份缺图、换机后图片没跟过来都是真实会发生的情况。
      expect(tester.takeException(), isNull);

      await teardown(tester);
    });
    testWidgets('图标本来就在首屏时不滚动——别把上传入口顶出视口', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await pump(tester, database);

      // 「餐饮」的 restaurant 是第一组第一个，一打开就看得见。
      // 这种情况下还去滚，会把顶上的「自己的图片」上传入口推出视口——
      // 为了露出一个本来就露着的格子，反而藏掉一个功能入口。
      await tester.tap(find.text('餐饮'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(find.text('编辑分类'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.imagePlus), findsOneWidget);
      final upload = tester.getRect(find.byIcon(FLucideIcons.imagePlus));
      final header = tester.getRect(find.text('自己的图片'));
      expect(
        upload.top,
        greaterThanOrEqualTo(header.bottom),
        reason: '上传格子不该被吸顶标题盖住，说明列表没有被无谓地滚动',
      );

      await teardown(tester);
    });
  });
}
