import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/update/app_version.dart';
import 'package:ligy_tally/core/update/update_available_sheet.dart';
import 'package:ligy_tally/core/update/update_service.dart';

Widget _host(void Function(BuildContext) onPress) {
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

UpdateInfo _info({String? notes, int size = 57 * 1024 * 1024}) {
  return UpdateInfo(
    version: const AppVersion(1, 5, 2),
    tagName: 'v1.5.2',
    apkUrl: 'https://example.com/app.apk',
    apkName: 'LigyTally-1.5.2.apk',
    apkSize: size,
    releaseNotes: notes,
  );
}

void main() {
  testWidgets('浮层展示版本、体积和更新条目', (tester) async {
    await tester.pumpWidget(
      _host((context) {
        showUpdateAvailableSheet(
          context,
          _info(
            notes: '''
## 更新内容

- 记账时可记录位置
- 地点可改成店名
''',
          ),
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('v1.5.2 · 57MB'), findsOneWidget);
    expect(find.text('记账时可记录位置'), findsOneWidget);
    expect(find.text('地点可改成店名'), findsOneWidget);
    expect(find.text('忽略'), findsOneWidget);
    expect(find.text('更新'), findsOneWidget);
  });

  testWidgets('点更新返回 update', (tester) async {
    UpdateSheetAction? action;
    await tester.pumpWidget(
      _host((context) async {
        action = await showUpdateAvailableSheet(
          context,
          _info(notes: '## 更新内容\n\n- 一条说明'),
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(action, UpdateSheetAction.update);
  });

  testWidgets('点忽略返回 ignore', (tester) async {
    UpdateSheetAction? action;
    await tester.pumpWidget(
      _host((context) async {
        action = await showUpdateAvailableSheet(
          context,
          _info(notes: '## 更新内容\n\n- 一条说明'),
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('忽略'));
    await tester.pumpAndSettle();
    expect(action, UpdateSheetAction.ignore);
  });
}
