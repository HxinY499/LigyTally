import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/ai/application/ai_approval.dart';
import 'package:ligy_tally/features/ai/presentation/ai_bill_confirm_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host() {
    const config = AppearanceConfig.initial;
    return MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        FLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildMaterialTheme(Brightness.light, config),
      builder: (context, child) =>
          FTheme(data: foruiThemeFor(Brightness.light, config), child: child!),
      home: const Scaffold(body: SizedBox.expand()),
    );
  }

  Future<Future<ToolApprovalDecision>> open(
    WidgetTester tester,
    ToolApprovalRequest request, {
    List<CategoryEntry> categories = const [],
  }) async {
    final context = tester.element(find.byType(Scaffold));
    final future = showAiBillConfirmDialog(
      context,
      request,
      categories: categories,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return future;
  }

  testWidgets('记一笔确认框把金额放在最显眼的位置', (tester) async {
    _phone(tester);
    await tester.pumpWidget(host());
    await open(tester, _save);
    expect(find.text('记一笔'), findsOneWidget);
    expect(find.text('AI 想记一笔：'), findsNothing);
    expect(find.text('¥28.00'), findsOneWidget);
    expect(find.text('支出'), findsOneWidget);
    expect(find.textContaining('三餐'), findsOneWidget);
    expect(find.text('确认记账'), findsOneWidget);
  });

  testWidgets('改账确认框展示改完后的金额，并只列出变动', (tester) async {
    _phone(tester);
    await tester.pumpWidget(host());
    await open(tester, _edit);
    expect(find.text('修改这笔'), findsOneWidget);
    expect(find.text('¥30.00'), findsOneWidget);
    expect(find.textContaining('¥28.00'), findsOneWidget);
    expect(find.text('金额'), findsOneWidget);
    expect(find.text('分类'), findsNothing);
    expect(find.textContaining('图片保留'), findsOneWidget);
    expect(find.text('确认修改'), findsOneWidget);
  });

  testWidgets('确认框支持就地微调金额和分类并回传修改后的结果', (tester) async {
    _phone(tester);
    await tester.pumpWidget(host());
    final decisionFuture = await open(
      tester,
      _save,
      categories: _testCategories,
    );

    // 1. 点击金额，用内置键盘改为 45 元
    await tester.tap(find.byKey(const ValueKey('confirm-edit-amount')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('amount-key-4')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('amount-key-5')));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('¥45.00'), findsOneWidget);

    // 2. 点击分类胶囊，改成「交通」
    await tester.tap(find.byKey(const ValueKey('confirm-edit-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('交通'));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('交通'), findsOneWidget);

    // 3. 确认记账
    await tester.tap(find.text('确认记账'));
    await tester.pumpAndSettle();
    final decision = await decisionFuture;
    expect(decision.approved, isTrue);
    expect(decision.bills, hasLength(1));
    expect(decision.bills.single.amountCents, 4500);
    expect(decision.bills.single.categoryId, 'cat_transport');
    expect(decision.bills.single.categoryName, '交通');
  });

  testWidgets('批量记账清单支持取消勾选单条与点进单笔微调', (tester) async {
    _phone(tester);
    await tester.pumpWidget(host());
    final decisionFuture = await open(
      tester,
      _batchSave,
      categories: _testCategories,
    );

    expect(find.text('批量记账'), findsOneWidget);
    expect(find.text('确认记入 3 笔'), findsOneWidget);

    // 取消勾选第 2 笔（下标 1）
    await tester.tap(find.byKey(const ValueKey('batch-check-1')));
    await tester.pumpAndSettle();
    expect(find.text('确认记入 2 笔'), findsOneWidget);

    // 点开第 1 笔（下标 0），把金额从 28 元微调为 32 元
    await tester.tap(find.byKey(const ValueKey('batch-row-0')));
    await tester.pumpAndSettle();
    expect(find.text('调整第 1 笔'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-edit-amount')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('amount-key-3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('amount-key-2')));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    // 提交批量确认
    await tester.tap(find.text('确认记入 2 笔'));
    await tester.pumpAndSettle();
    final decision = await decisionFuture;
    expect(decision.approved, isTrue);
    expect(decision.bills, hasLength(2));
    expect(decision.bills[0].amountCents, 3200);
    expect(decision.bills[0].note, '午饭');
    expect(decision.bills[1].amountCents, 990);
    expect(decision.bills[1].note, '美式');
  });
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const _testCategories = <CategoryEntry>[
  CategoryEntry(
    id: 'cat_food',
    kind: 0,
    name: '三餐',
    iconKey: 'food',
    parentId: null,
    level: 1,
    sortOrder: 0,
    isActive: true,
    createdAt: 1,
    updatedAt: 1,
  ),
  CategoryEntry(
    id: 'cat_transport',
    kind: 0,
    name: '交通',
    iconKey: 'transport',
    parentId: null,
    level: 1,
    sortOrder: 1,
    isActive: true,
    createdAt: 1,
    updatedAt: 1,
  ),
  CategoryEntry(
    id: 'cat_salary',
    kind: 1,
    name: '工资',
    iconKey: 'salary',
    parentId: null,
    level: 1,
    sortOrder: 0,
    isActive: true,
    createdAt: 1,
    updatedAt: 1,
  ),
];

final _save = ToolApprovalRequest(
  toolName: 'save_transactions',
  confirmLabel: '确认记账',
  title: '记一笔',
  message: '记',
  bill: ToolApprovalBill(
    kind: 0,
    amountCents: 2800,
    categoryId: 'cat_food',
    categoryName: '三餐',
    categoryIconKey: 'food',
    accountingDate: DateTime(2026, 10, 19),
    note: '午饭',
  ),
);

final _batchSave = ToolApprovalRequest(
  toolName: 'save_transactions',
  confirmLabel: '确认记入 3 笔',
  title: '批量记账',
  message: '批量',
  bills: [
    ToolApprovalBill(
      kind: 0,
      amountCents: 2800,
      categoryId: 'cat_food',
      categoryName: '三餐',
      categoryIconKey: 'food',
      accountingDate: DateTime(2026, 10, 19),
      note: '午饭',
    ),
    ToolApprovalBill(
      kind: 0,
      amountCents: 1800,
      categoryId: 'cat_transport',
      categoryName: '交通',
      categoryIconKey: 'transport',
      accountingDate: DateTime(2026, 10, 19),
      note: '打车',
    ),
    ToolApprovalBill(
      kind: 0,
      amountCents: 990,
      categoryId: 'cat_food',
      categoryName: '三餐',
      categoryIconKey: 'food',
      accountingDate: DateTime(2026, 10, 19),
      note: '美式',
    ),
  ],
);

final _edit = ToolApprovalRequest(
  toolName: 'update_transaction',
  confirmLabel: '确认修改',
  title: '修改这笔',
  message: '改',
  footnote: '图片保留，位置保留。',
  bill: ToolApprovalBill(
    kind: 0,
    amountCents: 3000,
    categoryId: 'cat_food',
    categoryName: '三餐',
    categoryIconKey: 'food',
    accountingDate: DateTime(2026, 10, 18),
    note: '午饭',
  ),
  changes: const [
    ToolApprovalChange(label: '金额', before: '¥28.00', after: '¥30.00'),
  ],
);
