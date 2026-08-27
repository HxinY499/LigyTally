import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:ligy_tally/core/appearance/appearance.dart';
import 'package:ligy_tally/core/branding/app_brand.dart';
import 'package:ligy_tally/core/branding/privacy_policy.dart';
import 'package:ligy_tally/core/theme/app_theme.dart';
import 'package:ligy_tally/features/settings/presentation/privacy_screen.dart';

Widget _host(Widget home) {
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
    home: home,
  );
}

void main() {
  test('对外名与隐私政策域名对齐备案', () {
    expect(kAppDisplayName, '里格账');
    expect(kPrivacyPolicyUrl, 'https://ligezhang.cn/privacy.html');
    expect(kIcpFilingNumber, '陕ICP备2026023367号');
    expect(kIcpQueryUrl, startsWith('https://beian.miit.gov.cn'));
  });

  test('隐私政策写明本地存储、可选定位、更新联网', () {
    final body = kPrivacyPolicySections.map((s) => s.body).join();
    expect(body, contains('只保存在你这台手机'));
    expect(body, contains('定位'));
    expect(body, contains('检查新版本'));
    expect(body, contains('不提供云端同步'));
  });

  test('正文不出现开发者姓名，但留有联系方式', () {
    final all = kPrivacyPolicySections.map((s) => '${s.title}${s.body}').join();
    expect(all, isNot(contains('何欣宇')));
    expect(kSupportEmail, isNotEmpty);
    expect(all, contains(kSupportEmail));
  });

  testWidgets('二级页同时展示政策章节与备案号', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(const PrivacyScreen()));
    await tester.pumpAndSettle();

    expect(find.text('隐私与备案'), findsWidgets);
    expect(find.text(kPrivacyPolicySections.first.title), findsOneWidget);
    expect(find.textContaining('没有账号系统'), findsOneWidget);

    await tester.scrollUntilVisible(find.text(kIcpFilingNumber), 200);
    expect(find.text(kIcpFilingNumber), findsOneWidget);
  });
}
