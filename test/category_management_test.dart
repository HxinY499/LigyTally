import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/database/app_database.dart';
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
      expect(
        await database.categoryNameExists(kind: 0, name: '餐饮'),
        isTrue,
      );
      // 收入侧没有——两侧分类互不相干，同名合法。
      expect(
        await database.categoryNameExists(kind: 1, name: '餐饮'),
        isFalse,
      );
      // 「三餐」是餐饮的子分类，不算一级重名。
      expect(
        await database.categoryNameExists(kind: 0, name: '三餐'),
        isFalse,
      );
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
  });

  group('分类管理页', () {
    Future<void> pump(WidgetTester tester, AppDatabase database) async {
      final forui = buildForuiTheme();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: forui.toApproximateMaterialTheme(),
            builder: (context, child) =>
                FTheme(data: forui, child: FToaster(child: child!)),
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
      expect(find.text('选择图标'), findsOneWidget);

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
  });
}
