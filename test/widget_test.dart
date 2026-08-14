import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/category_config/category_config_service.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/database/default_categories.dart';
import 'package:ligy_tally/core/media/image_storage.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/utils/ledger_date.dart';
import 'package:ligy_tally/features/ledger/application/providers.dart';
import 'package:ligy_tally/features/ledger/presentation/ledger_screen.dart';
import 'package:ligy_tally/features/statistics/presentation/stats_design.dart';
import 'package:ligy_tally/shared/widgets/summary_band.dart';

void main() {
  test('month range uses a left-closed right-open boundary', () {
    final range = monthRange(DateTime(2026, 2, 18));

    expect(range.start, DateTime(2026, 2));
    expect(range.endExclusive, DateTime(2026, 3));
    expect(range.dayCount, 28);
  });

  test('money formatting keeps integer-cent precision', () {
    expect(formatMoney(1234), '¥12.34');
    expect(formatMoney(-505, signed: true), '-¥5.05');
    expect(formatMoney(505, signed: true), '+¥5.05');
  });

  test('money formatting groups thousands and can be disabled', () {
    expect(formatMoney(1904260), '¥19,042.60');
    expect(formatMoney(1904260, grouped: false), '¥19042.60');
    expect(formatMoney(-1234567890, signed: true), '-¥12,345,678.90');
  });

  test('default category seed preserves a generic two-level tree', () {
    expect(defaultCategorySeeds, hasLength(44));
    expect(
      defaultCategorySeeds.where((item) => item.level == 1),
      hasLength(16),
    );
    expect(
      defaultCategorySeeds.where((item) => item.level == 2),
      hasLength(28),
    );
    expect(
      defaultCategorySeeds.any(
        (item) => item.name == '宠物食品' && item.parentId == 'expense_pet',
      ),
      isTrue,
    );
    expect(defaultCategorySeeds.any((item) => item.name == '果冻'), isFalse);
  });

  test(
    'database creates the full category tree and stores subcategories',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final categories = await database.exportCategories();

      expect(categories, hasLength(44));
      expect(categories.where((item) => item.level == 1), hasLength(16));
      expect(categories.where((item) => item.level == 2), hasLength(28));

      final petFood = categories.singleWhere((item) => item.name == '宠物食品');
      final pet = categories.singleWhere((item) => item.name == '宠物');
      expect(petFood.parentId, pet.id);

      final now = DateTime(2026, 8, 8, 17);
      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: 'test-transaction',
          kind: 0,
          amountCents: 2350,
          categoryId: petFood.id,
          accountingDate: '2026-08-08',
          occurredAt: now.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
          note: const Value('猫粮'),
        ),
        newImages: const [],
        removedImageIds: const {},
      );
      final items = await database
          .watchTransactions(
            LedgerDateRange(DateTime(2026, 8), DateTime(2026, 9)),
          )
          .first;
      expect(items.single.category.name, '宠物食品');
      expect(
        await database.deleteCategory(petFood.id),
        CategoryDeleteResult.inUse,
      );
    },
  );

  test(
    'category config import replaces active config with a two-level tree',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final directory = await Directory.systemTemp.createTemp(
        'ligy_categories',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/categories.json');
      await file.writeAsString('''
        {
          "format": "ligy-tally-categories",
          "version": 1,
          "expense": [
            {
              "name": "通勤",
              "icon": "transport",
              "children": [{"name": "地铁", "icon": "subway"}]
            }
          ],
          "income": [
            {"name": "薪资", "icon": "salary", "children": []}
          ]
        }
      ''');

      final service = CategoryConfigService(
        database,
        ImageStorage.atRoot(directory.path),
      );
      final preview = await service.inspect(file.path);
      expect(preview.parentCount, 2);
      expect(preview.childCount, 1);
      // v1 的老配置里不可能有自定义图标，导入路径不该凭空造出图片。
      expect(preview.iconImageCount, 0);

      await service.importAndReplace(file.path);
      final active = (await database.exportCategories())
          .where((category) => category.isActive)
          .toList();
      expect(active, hasLength(3));
      final subway = active.singleWhere((category) => category.name == '地铁');
      final commute = active.singleWhere((category) => category.name == '通勤');
      expect(subway.parentId, commute.id);
      expect(
        await database.deleteCategory(subway.id),
        CategoryDeleteResult.deleted,
      );
    },
  );

  testWidgets('summary band presents expense, income and net values', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SummaryBand(
              summary: LedgerSummary(
                incomeCents: 10000,
                expenseCents: 3575,
                entryCount: 2,
                activeDayCount: 2,
              ),
            ),
          ),
        ),
      ),
    );

    // Hero 大数字不带 ¥ 前缀，收入/净收支才带
    expect(find.text('35.75'), findsOneWidget);
    expect(find.text('100.00'), findsOneWidget);
    expect(find.text('+64.25'), findsOneWidget);
  });

  group('卡片阴影全应用统一', () {
    testWidgets('统计页的卡片阴影就是全局色板那一份', (tester) async {
      // 统计页早先在 StatsTokens 里自带一份阴影常量。这里断言它是**同一个
      // 对象**（identical 而非 ==），确保是「转发」而不是「抄了一份数值」——
      // 抄一份的话，以后改色板里的阴影统计页不会跟着变，两屏就漂移了。
      //
      // 深浅两套都要验：转发关系只要在某一套里被写成硬取 light，
      // 深色模式下统计页就会挂着一份浅色阴影。
      for (final brightness in Brightness.values) {
        late StatsTokens stats;
        late AppColors colors;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildMaterialTheme(brightness),
            home: Builder(
              builder: (context) {
                stats = StatsTokens.of(context);
                colors = context.colors;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        // MaterialApp 换主题会走 200ms 淡变，首帧拿到的还是插值中的旧亮度，
        // 必须等它落定再取值。
        await tester.pumpAndSettle();
        expect(colors.brightness, brightness);
        expect(identical(stats.shadowCard, colors.shadowCard), isTrue);
        expect(identical(stats.shadowHero, colors.shadowHeroPrimary), isTrue);
        // Hero 卡渐变同理：统计页概览卡和记账页月度摘要卡是同一个视觉元素，
        // 色停必须来自色板同一份，否则调了一屏另一屏不动。
        expect(stats.heroGradient, colors.heroGradient);
      }
    });

    test('卡片阴影是两层叠加：近距离收边 + 远距离柔光', () {
      // 单层阴影要么硬得像描边，要么糊成一团灰。这条锁住「两层」这个设计决定。
      for (final colors in [AppColors.light, AppColors.dark]) {
        expect(colors.shadowCard, hasLength(2));
        final near = colors.shadowCard.first;
        final far = colors.shadowCard.last;
        // 近层负责压边界：偏移小、模糊小。
        expect(near.offset.dy, lessThan(far.offset.dy));
        expect(near.blurRadius, lessThan(far.blurRadius));
      }
      // 浅色下阴影不是纯黑——纯黑压在浅灰底上会发脏，要带一点冷色调（蓝 > 红）。
      final light = AppColors.light.shadowCard.first;
      expect(light.color.b, greaterThan(light.color.r));
      // 深色下反过来要更黑更重：浅色那套 4% 的灰压在深底上等于没有。
      expect(
        AppColors.dark.shadowCard.first.color.a,
        greaterThan(AppColors.light.shadowCard.first.color.a),
      );
    });

    testWidgets('记账页的日卡带上了统一阴影', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      // 用一次性查询而不是 watchCategories 的首帧：流式查询会在测试里留下
      // 活跃订阅，容易与后面的 pump 相互等待。
      final categories = await database.exportCategories();
      final expense = categories.firstWhere((item) => item.kind == 0);
      final now = DateTime.now();
      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: 'shadow-probe',
          kind: 0,
          amountCents: 1200,
          categoryId: expense.id,
          accountingDate: dateKey(now),
          occurredAt: now.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
        newImages: const [],
        removedImageIds: const {},
      );

      final forui = buildForuiTheme();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: buildMaterialTheme(Brightness.light),
            builder: (context, child) => FTheme(
              data: forui,
              child: FToaster(child: child!),
            ),
            // 必须自己套 Scaffold：LedgerScreen 不自带，实际运行时由
            // home_shell 提供 Material 祖先，页头里的 InkResponse 依赖它。
            home: const Scaffold(body: LedgerScreen()),
          ),
        ),
      );
      // 不用 pumpAndSettle：页面里有持续动画时它会等不到静止帧而挂死。
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      // 日卡的特征是「白面 + 18 圆角」，靠这两点定位。
      // 日卡的阴影挂在 DecoratedBox 上（白底由内层 Material 提供，
      // 这样卡片本身才是水波画布——见 _DayCard 注释）。
      // 靠「18 圆角 + 有阴影 + 无底色」定位到它。
      final dayCards = tester
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
      expect(dayCards, isNotEmpty);
      for (final card in dayCards) {
        expect(card.boxShadow, AppColors.light.shadowCard);
      }

      // drift 取消订阅时会排一个 0ms 的清理定时器，测试结束前要放掉它。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });

    testWidgets('月度摘要卡用的是主色阴影', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: SummaryBand(
                summary: LedgerSummary(
                  incomeCents: 10000,
                  expenseCents: 3575,
                  entryCount: 2,
                  activeDayCount: 2,
                ),
              ),
            ),
          ),
        ),
      );

      // 摘要卡是主题色渐变，配中性灰阴影会发浊，必须用带主色相的那组。
      final band = tester
          .widgetList<Container>(find.byType(Container))
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.gradient != null)
          .toList();
      expect(band, hasLength(1));
      expect(band.single.boxShadow, AppColors.light.shadowHeroPrimary);
    });
  });

  group('首页的点击反馈', () {
    /// 造一条今天的支出，返回内存库。
    Future<AppDatabase> seed(WidgetTester tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final categories = await database.exportCategories();
      final expense = categories.firstWhere((item) => item.kind == 0);
      final now = DateTime.now();
      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: 'ink-probe',
          kind: 0,
          amountCents: 1200,
          categoryId: expense.id,
          accountingDate: dateKey(now),
          occurredAt: now.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
        newImages: const [],
        removedImageIds: const {},
      );
      return database;
    }

    Future<void> pumpLedger(WidgetTester tester, AppDatabase database) async {
      final forui = buildForuiTheme();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: buildMaterialTheme(Brightness.light),
            builder: (context, child) => FTheme(
              data: forui,
              child: FToaster(child: child!),
            ),
            home: const Scaffold(body: LedgerScreen()),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('日卡自己提供 Material，水波才有地方画', (tester) async {
      final database = await seed(tester);
      await pumpLedger(tester, database);

      // 关键约定：白底必须由 Material 提供，不能是 Container(color:)。
      //
      // 水波画在「最近的 Material 上、且在子节点之下」。如果日卡白底是
      // 不透明 Container，最近的 Material 就是 Scaffold 那层，水波会被
      // 白卡整块盖住——实测过按下时像素零变化，点击毫无反馈。
      final cards = tester
          .widgetList<Material>(find.byType(Material))
          .where(
            (material) =>
                material.color == AppColors.light.surface &&
                material.borderRadius ==
                    const BorderRadius.all(Radius.circular(18)),
          )
          .toList();
      expect(cards, isNotEmpty);
      for (final card in cards) {
        // 必须裁剪，否则水波会在圆角外溢出成方块。
        expect(card.clipBehavior, Clip.antiAlias);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });

    testWidgets('账单行与卡片头都配了反馈色', (tester) async {
      final database = await seed(tester);
      await pumpLedger(tester, database);

      final inks = tester
          .widgetList<InkWell>(find.byType(InkWell))
          .where((ink) => ink.highlightColor == AppColors.light.pressed)
          .toList();
      // 至少三处：卡片头、账单行、吸顶月份按钮。
      expect(inks.length, greaterThanOrEqualTo(3));
      for (final ink in inks) {
        // 水波比按下底色更淡——水波是动态扩散的，同色会显得炸开一朵蓝花。
        expect(ink.splashColor, AppColors.light.ripple);
        expect(ink.hoverColor, AppColors.light.ripple);
      }
      expect(AppColors.light.ripple.a, lessThan(AppColors.light.pressed.a));

      // 带长按的那个才是账单行（卡片头只有 onTap）。
      final rows = tester
          .widgetList<InkWell>(find.byType(InkWell))
          .where((ink) => ink.onLongPress != null)
          .toList();
      expect(rows, hasLength(1));
      expect(rows.single.highlightColor, AppColors.light.pressed);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });

    testWidgets('按下时像素真的会变——这是本次修复的核心证据', (tester) async {
      // 用最小复现对比两种结构，直接量「按下前后有多少字节不同」。
      //
      // 这条比「断言 InkWell 配了颜色」强得多：配色写对了但被上层不透明
      // 底色盖住，视觉上依然毫无反馈——原来的首页就是这种情况。
      Future<int> pressDiff(Widget Function(Widget child) wrap) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: AppColors.light.canvas,
              body: Center(
                child: RepaintBoundary(
                  key: key,
                  child: wrap(
                    InkWell(
                      onTap: () {},
                      highlightColor: AppColors.light.pressed,
                      splashColor: AppColors.light.ripple,
                      child: const SizedBox(height: 60, width: 200),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Future<List<int>> shot() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          late List<int> bytes;
          // toImage 是真异步，必须放进 runAsync，否则拿到的是空白帧。
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            bytes = data!.buffer.asUint8List().toList();
            image.dispose();
          });
          return bytes;
        }

        final idle = await shot();
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(InkWell)),
        );
        // 高亮是淡入的，多推几帧到最盛态再抓，否则可能抓到刚起步的一帧。
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
        final pressed = await shot();
        await gesture.cancel();
        await tester.pumpAndSettle();

        var diff = 0;
        for (var i = 0; i < idle.length; i++) {
          if (idle[i] != pressed[i]) diff++;
        }
        return diff;
      }

      // 旧结构：白底由 Container 提供。最近的 Material 是 Scaffold 那层，
      // 水波画在它上面、被白卡整块盖住 → 像素零变化。
      final oldDiff = await pressDiff(
        (child) => Container(
          decoration: BoxDecoration(
            color: AppColors.light.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppColors.light.shadowCard,
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      );
      expect(oldDiff, 0, reason: 'Container 白底会把反馈完全遮住（问题根因）');

      // 新结构：卡片自己就是 Material，于是它成了水波画布。
      final newDiff = await pressDiff(
        (child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            boxShadow: AppColors.light.shadowCard,
          ),
          child: Material(
            color: AppColors.light.surface,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      );
      expect(newDiff, greaterThan(0), reason: 'Material 白底下反馈必须可见');
    });
  });

  group('删除确认弹窗', () {
    testWidgets('确定与取消两颗按钮同宽', (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final categories = await database.exportCategories();
      final expense = categories.firstWhere((item) => item.kind == 0);
      final now = DateTime.now();
      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: 'dialog-probe',
          kind: 0,
          amountCents: 1200,
          categoryId: expense.id,
          accountingDate: dateKey(now),
          occurredAt: now.millisecondsSinceEpoch,
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
        newImages: const [],
        removedImageIds: const {},
      );

      final forui = buildForuiTheme();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: buildMaterialTheme(Brightness.light),
            builder: (context, child) => FTheme(
              data: forui,
              child: FToaster(child: child!),
            ),
            home: const Scaffold(body: LedgerScreen()),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      final row = find.byWidgetPredicate(
        (widget) => widget is InkWell && widget.onLongPress != null,
      );
      await tester.longPress(row);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('确定'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      // 原来「取消」是裸 TextButton，宽度只跟着文字走，
      // 和撑满的「确定」并排时一长一短。这条锁住两颗按钮等宽。
      final confirm = tester.getSize(
        find.ancestor(
          of: find.text('确定'),
          matching: find.byType(OutlinedButton),
        ),
      );
      final cancel = tester.getSize(
        find.ancestor(of: find.text('取消'), matching: find.byType(TextButton)),
      );
      expect(cancel.width, confirm.width);
      // 高度也应一致（同一组 vertical padding + 同字号）。
      expect(cancel.height, confirm.height);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  });
}
