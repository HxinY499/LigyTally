import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ligy_tally/core/update/app_version.dart';
import 'package:ligy_tally/core/update/update_controller.dart';
import 'package:ligy_tally/core/update/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「查不到」必须和「没有新版本」分开。
///
/// 这条 bug 的样子是：断网点「检查更新」，提示「当前已是最新版本 (v1.6.1)」——
/// 而 1.7.0 已经发布了。括号里还是旧版本号却说已是最新，本身就自相矛盾，
/// 但用户没法从这句话看出这其实是一次失败。
///
/// 根因是 `checkForUpdate` 用一个 `null` 同时表示了「已是最新」「网络失败」
/// 「清单格式不认识」「读不到本机版本」，而手动检查把 `null` 一律翻译成
/// 「已是最新」。
void main() {
  // 要 mock 原生 channel 与 SharedPreferences，两者都依赖已初始化的 binding。
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.ligy.ligy_tally/app_update');

  /// 让原生 channel 报告一个版本号；[versionName] 为 null 时模拟读不到。
  void mockNativeVersion(String? versionName) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'getVersionInfo') return null;
          if (versionName == null) return null;
          return <String, Object?>{'versionName': versionName};
        });
  }

  String manifest({required String tag}) => jsonEncode({
    'tag_name': tag,
    'body': '## 更新内容\n\n- 一条说明',
    'apk_name': 'LigyTally-${tag.substring(1)}.apk',
    'apk_url':
        'https://github.com/HxinY499/LigyTally-Releases/releases/download/'
        '$tag/LigyTally-${tag.substring(1)}.apk',
    'apk_size': 24516200,
    'sha256': 'a' * 64,
  });

  /// 200 响应。**必须显式给 utf8**：`http.Response` 在没有 content-type 时
  /// 按 latin1 编码 body，而生产代码读的是 `bodyBytes` 再 `utf8.decode`，
  /// 于是清单文案里的中文会解码失败，被归成一次网络错误——夹具自己造出一个
  /// 假的失败，测不到想测的分支。
  http.Response ok(String body) => http.Response.bytes(utf8.encode(body), 200);

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => mockNativeVersion(null));

  group('checkForUpdate 报的是事实，不是「要不要打扰用户」', () {
    test('线上更新时给 UpdateAvailable', () async {
      mockNativeVersion('1.6.1');
      final service = UpdateService(
        client: MockClient((_) async => ok(manifest(tag: 'v1.7.0'))),
      );
      addTearDown(service.dispose);

      final result = await service.checkForUpdate();
      expect(result, isA<UpdateAvailable>());
      expect(
        (result as UpdateAvailable).info.version,
        const AppVersion(1, 7, 0),
      );
    });

    test('本机已是最新时给 UpdateUpToDate，并带上本机版本号', () async {
      mockNativeVersion('1.7.0');
      final service = UpdateService(
        client: MockClient((_) async => ok(manifest(tag: 'v1.7.0'))),
      );
      addTearDown(service.dispose);

      final result = await service.checkForUpdate();
      expect(result, isA<UpdateUpToDate>());
      expect((result as UpdateUpToDate).current, const AppVersion(1, 7, 0));
    });

    test('连不上时给 network 失败，而不是「已是最新」', () async {
      mockNativeVersion('1.6.1');
      final service = UpdateService(
        client: MockClient((_) => throw const SocketExceptionStub()),
      );
      addTearDown(service.dispose);

      final result = await service.checkForUpdate();
      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).reason, UpdateFailure.network);
    });

    test('超时时给 network 失败', () async {
      mockNativeVersion('1.6.1');
      final service = UpdateService(
        client: MockClient((_) => throw TimeoutException('timeout')),
      );
      addTearDown(service.dispose);

      final result = await service.checkForUpdate();
      expect((result as UpdateCheckFailed).reason, UpdateFailure.network);
    });

    test('服务器答了但不是 200，归到 manifest 而不是 network', () async {
      // 这两种要分开：网络问题用户自己能重试，源站拒下只能等修。
      mockNativeVersion('1.6.1');
      final service = UpdateService(
        client: MockClient((_) async => http.Response('nope', 403)),
      );
      addTearDown(service.dispose);

      final result = await service.checkForUpdate();
      expect((result as UpdateCheckFailed).reason, UpdateFailure.manifest);
    });

    test('清单格式不认识，也归到 manifest', () async {
      mockNativeVersion('1.6.1');
      final service = UpdateService(
        client: MockClient((_) async => ok('{"foo":1}')),
      );
      addTearDown(service.dispose);

      final result = await service.checkForUpdate();
      expect((result as UpdateCheckFailed).reason, UpdateFailure.manifest);
    });

    test('读不到本机版本号时给 localVersion 失败', () async {
      mockNativeVersion(null);
      final service = UpdateService(
        client: MockClient((_) async => ok(manifest(tag: 'v1.7.0'))),
      );
      addTearDown(service.dispose);

      final result = await service.checkForUpdate();
      expect((result as UpdateCheckFailed).reason, UpdateFailure.localVersion);
    });

    test('被忽略的版本对启动检查等价于已是最新，手动检查照样看得到', () async {
      mockNativeVersion('1.6.1');
      final service = UpdateService(
        client: MockClient((_) async => ok(manifest(tag: 'v1.7.0'))),
      );
      addTearDown(service.dispose);
      await service.ignoreVersion(const AppVersion(1, 7, 0));

      expect(await service.checkForUpdate(), isA<UpdateUpToDate>());
      expect(
        await service.checkForUpdate(respectIgnore: false),
        isA<UpdateAvailable>(),
        reason: '忽略只该关掉启动弹窗，手动检查仍要能看到这个版本',
      );
    });
  });

  group('手动检查的提示文案', () {
    Future<ManualCheckOutcome> check(http.Client client) async {
      final service = UpdateService(client: client);
      addTearDown(service.dispose);
      final controller = UpdateController(service);
      addTearDown(controller.dispose);
      return controller.checkManually();
    }

    test('查不到时说的是失败，且不带版本号', () async {
      mockNativeVersion('1.6.1');
      final outcome = await check(
        MockClient((_) => throw const SocketExceptionStub()),
      );

      expect(outcome.failed, isTrue, reason: 'toast 要走 error 级别');
      expect(outcome.message, contains('失败'));
      expect(
        outcome.message,
        isNot(contains('最新')),
        reason: '这正是原来的 bug：查不到被说成「已是最新」',
      );
      expect(
        outcome.message,
        isNot(contains('1.6.1')),
        reason: '带上版本号会让这句话被读成一个结论，而失败时没有结论',
      );
    });

    test('真的已是最新时不算失败，且带上版本号', () async {
      mockNativeVersion('1.7.0');
      final outcome = await check(
        MockClient((_) async => ok(manifest(tag: 'v1.7.0'))),
      );

      expect(outcome.failed, isFalse);
      expect(outcome.message, '当前已是最新版本 (v1.7.0)');
    });

    test('发现新版本时报出版本号', () async {
      mockNativeVersion('1.6.1');
      final outcome = await check(
        MockClient((_) async => ok(manifest(tag: 'v1.7.0'))),
      );

      expect(outcome.failed, isFalse);
      expect(outcome.message, '发现新版本 v1.7.0');
    });

    test('三种失败原因给的是三句不同的话', () async {
      // 用户能做的事不同：网络问题自己能重试，其余两种只能等修。
      // 全都说成「请稍后重试」会让人白重试很多次。
      mockNativeVersion('1.6.1');
      final network = await check(
        MockClient((_) => throw const SocketExceptionStub()),
      );
      final serverSide = await check(
        MockClient((_) async => http.Response('nope', 403)),
      );
      mockNativeVersion(null);
      final localVersion = await check(
        MockClient((_) async => ok(manifest(tag: 'v1.7.0'))),
      );

      final messages = {
        network.message,
        serverSide.message,
        localVersion.message,
      };
      expect(messages, hasLength(3));
      for (final outcome in [network, serverSide, localVersion]) {
        expect(outcome.failed, isTrue);
      }
    });
  });
}

/// 站位用的网络异常。不直接用 `dart:io` 的 SocketException：
/// 这里只需要「一个非 _ManifestException 的异常」，用真类型会把测试绑到平台上。
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => '连不上';
}
