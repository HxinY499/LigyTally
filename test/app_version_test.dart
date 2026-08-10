import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/update/app_version.dart';

void main() {
  group('AppVersion.tryParse', () {
    test('解析标准三段式', () {
      final version = AppVersion.tryParse('1.2.3');
      expect(version, const AppVersion(1, 2, 3));
    });

    test('容忍 GitHub tag 的 v 前缀', () {
      expect(AppVersion.tryParse('v1.0.1'), const AppVersion(1, 0, 1));
      expect(AppVersion.tryParse('V2.10.0'), const AppVersion(2, 10, 0));
    });

    test('忽略 build number（versionCode 不代表版本新旧）', () {
      expect(AppVersion.tryParse('1.0.1+2'), const AppVersion(1, 0, 1));
      expect(AppVersion.tryParse('1.0.1+99'), const AppVersion(1, 0, 1));
    });

    test('忽略预发布后缀', () {
      expect(AppVersion.tryParse('1.2.0-beta.1'), const AppVersion(1, 2, 0));
    });

    test('两段式补零', () {
      expect(AppVersion.tryParse('1.5'), const AppVersion(1, 5, 0));
    });

    test('容忍首尾空白', () {
      expect(AppVersion.tryParse('  v1.0.1  '), const AppVersion(1, 0, 1));
    });

    test('格式不认识时返回 null 而不是猜', () {
      expect(AppVersion.tryParse(null), isNull);
      expect(AppVersion.tryParse(''), isNull);
      expect(AppVersion.tryParse('latest'), isNull);
      expect(AppVersion.tryParse('1.2.3.4'), isNull);
      expect(AppVersion.tryParse('1.x.0'), isNull);
      expect(AppVersion.tryParse('-1.0.0'), isNull);
    });
  });

  group('版本比较', () {
    test('patch 位递增', () {
      expect(
        const AppVersion(1, 0, 2).isNewerThan(const AppVersion(1, 0, 1)),
        isTrue,
      );
    });

    test('minor 位递增优先于 patch', () {
      expect(
        const AppVersion(1, 1, 0).isNewerThan(const AppVersion(1, 0, 99)),
        isTrue,
      );
    });

    test('major 位递增优先于 minor', () {
      expect(
        const AppVersion(2, 0, 0).isNewerThan(const AppVersion(1, 99, 99)),
        isTrue,
      );
    });

    test('相同版本不算新版本——这是「不该提示」的关键判断', () {
      expect(
        const AppVersion(1, 0, 1).isNewerThan(const AppVersion(1, 0, 1)),
        isFalse,
      );
    });

    test('线上版本更旧时不提示（防止回滚 Release 触发降级提示）', () {
      expect(
        const AppVersion(1, 0, 0).isNewerThan(const AppVersion(1, 0, 1)),
        isFalse,
      );
    });

    test('数字比较而非字符串比较：1.0.10 > 1.0.9', () {
      // 字符串比较会得出 "1.0.10" < "1.0.9" 的错误结论
      expect(
        const AppVersion(1, 0, 10).isNewerThan(const AppVersion(1, 0, 9)),
        isTrue,
      );
      expect(
        AppVersion.tryParse(
          'v1.0.10',
        )!.isNewerThan(AppVersion.tryParse('1.0.9+3')!),
        isTrue,
      );
    });

    test('build number 不同但版本名相同时不提示', () {
      final online = AppVersion.tryParse('v1.0.1')!;
      final local = AppVersion.tryParse('1.0.1+2')!;
      expect(online.isNewerThan(local), isFalse);
    });
  });
}
