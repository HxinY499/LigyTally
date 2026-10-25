import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/ai/application/ai_approval.dart';
import 'package:ligy_tally/features/ai/presentation/ai_bill_confirm_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host() {
    const config = AppearanceConfig.initial;
    return MaterialApp(
      theme: buildMaterialTheme(Brightness.light, config),
      builder: (context, child) =>
          FTheme(data: foruiThemeFor(Brightness.light, config), child: child!),
      home: const Scaffold(body: SizedBox.expand()),
    );
  }

  Future<void> open(WidgetTester tester, ToolApprovalRequest request) async {
    final context = tester.element(find.byType(Scaffold));
    showAiBillConfirmDialog(context, request);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
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
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final _save = ToolApprovalRequest(
  toolName: 'save_transaction',
  confirmLabel: '确认记账',
  title: '记一笔',
  message: '记',
  bill: ToolApprovalBill(
    kind: 0,
    amountCents: 2800,
    accountingDate: DateTime(2026, 10, 19),
    categoryName: '三餐',
    note: '午饭',
  ),
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
    accountingDate: DateTime(2026, 10, 18),
    categoryName: '三餐',
    note: '午饭',
  ),
  changes: const [
    ToolApprovalChange(label: '金额', before: '¥28.00', after: '¥30.00'),
  ],
);
