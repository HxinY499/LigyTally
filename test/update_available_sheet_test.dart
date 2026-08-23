import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/core/update/app_version.dart';
import 'package:ligy_tally/core/update/update_available_sheet.dart';
import 'package:ligy_tally/core/update/update_controller.dart';
import 'package:ligy_tally/core/update/update_progress.dart';
import 'package:ligy_tally/core/update/update_service.dart';

Widget _host(void Function(BuildContext) onPress, {UpdateService? service}) {
  const config = AppearanceConfig.initial;
  return ProviderScope(
    overrides: [
      if (service != null) updateServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
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

class _HangingUpdateService extends UpdateService {
  @override
  Future<AppVersion?> currentVersion() async => const AppVersion(1, 5, 0);

  @override
  Future<bool> canInstallPackages() async => true;

  @override
  Future<void> cleanupOldApks({String? keepName}) async {}

  @override
  Future<File> downloadApk(
    UpdateInfo info, {
    required void Function(DownloadProgress) onProgress,
    bool Function()? cancelled,
  }) {
    return Completer<File>().future;
  }
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

- 功能 记账时可记录位置
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
    expect(find.text('功能 记账时可记录位置'), findsNothing);
    expect(find.text('地点可改成店名'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.sparkles), findsOneWidget);
    expect(find.text('忽略'), findsOneWidget);
    expect(find.text('更新'), findsOneWidget);
  });

  testWidgets('点更新后浮层不关，按钮换成进度和取消', (tester) async {
    await tester.pumpWidget(
      _host((context) {
        showUpdateAvailableSheet(
          context,
          _info(notes: '## 更新内容\n\n- 一条说明'),
        );
      }, service: _HangingUpdateService()),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('更新'), findsNothing);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('0 / 57 MB'), findsOneWidget);
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

  test('进度文案有体积时写兆字节，校验中换短句', () {
    const info = UpdateInfo(
      version: AppVersion(1, 5, 9),
      tagName: 'v1.5.9',
      apkUrl: 'https://example.com/a.apk',
      apkName: 'a.apk',
      apkSize: 25 * 1024 * 1024,
    );
    expect(
      updateDownloadLabel(
        UpdateState(
          phase: UpdatePhase.downloading,
          info: info,
          progress: const DownloadProgress(
            received: 12 * 1024 * 1024,
            total: 25 * 1024 * 1024,
            stage: DownloadStage.downloading,
          ),
        ),
      ),
      '12 / 25 MB',
    );
    expect(
      updateDownloadChipLabel(
        const UpdateState(
          phase: UpdatePhase.verifying,
          info: info,
          progress: DownloadProgress(
            received: 25 * 1024 * 1024,
            total: 25 * 1024 * 1024,
            stage: DownloadStage.verifying,
          ),
        ),
      ),
      '正在校验',
    );
  });
}
