import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/settings/presentation/csv_export_sheet.dart';

Widget _host(void Function(BuildContext) onPress) {
  final theme = buildForuiTheme();
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: const [
      FLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => FTheme(data: theme, child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => onPress(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('默认不含图片，点本月直接带上关着的开关', (tester) async {
    CsvExportChoice? choice;
    await tester.pumpWidget(
      _host((context) async {
        choice = await showCsvExportSheet(context);
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('导出账单'), findsOneWidget);
    expect(find.text('不含图片，可用表格软件打开'), findsNothing);
    expect(find.text('同时导出图片'), findsOneWidget);

    await tester.tap(find.text('本月'));
    await tester.pumpAndSettle();
    expect(choice?.preset, CsvExportPreset.month);
    expect(choice?.includeImages, isFalse);
  });

  testWidgets('勾选后副标题换成 Excel，点范围才确认', (tester) async {
    CsvExportChoice? choice;
    await tester.pumpWidget(
      _host((context) async {
        choice = await showCsvExportSheet(context);
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('同时导出图片'));
    await tester.pump();
    expect(find.text('导出账单'), findsOneWidget, reason: '勾选不能把浮层关掉');

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(choice?.preset, CsvExportPreset.all);
    expect(choice?.includeImages, isTrue);
  });
}
