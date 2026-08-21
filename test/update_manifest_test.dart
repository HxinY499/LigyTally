import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/update/update_service.dart';

void main() {
  const sha256 =
      'fb262b6dea1d448ae7f81b7751175de350a5af717399c40d6d49ba09f5adc845';

  String manifest({
    String tag = 'v1.5.9',
    String url =
        'https://ligy-tally-releases.oss-cn-hangzhou.aliyuncs.com/LigyTally-1.5.9.apk',
    String name = 'LigyTally-1.5.9.apk',
    Object? sha = sha256,
    int size = 24600000,
    String body = '## 更新内容\n\n- 统计页可以排除分类',
  }) {
    final shaField = sha == null ? '' : '"sha256": "$sha",';
    return '''
{
  "tag_name": "$tag",
  "body": ${body.contains('\n') ? '"${body.replaceAll('\n', r'\n')}"' : '"$body"'},
  "apk_name": "$name",
  "apk_url": "$url",
  "apk_size": $size,
  $shaField
  "unused": true
}
''';
  }

  test('合法清单解析出版本、地址、校验值和更新文案', () {
    final info = parseUpdateManifest(manifest());
    expect(info, isNotNull);
    expect(info!.version.toString(), '1.5.9');
    expect(info.tagName, 'v1.5.9');
    expect(info.apkName, 'LigyTally-1.5.9.apk');
    expect(
      info.apkUrl,
      'https://ligy-tally-releases.oss-cn-hangzhou.aliyuncs.com/LigyTally-1.5.9.apk',
    );
    expect(info.apkSize, 24600000);
    expect(info.sha256, sha256);
    expect(info.releaseNotes, contains('统计页可以排除分类'));
  });

  test('校验值允许大写，解析后收成小写', () {
    final info = parseUpdateManifest(manifest(sha: sha256.toUpperCase()));
    expect(info?.sha256, sha256);
  });

  test('没有 sha256 仍然能解析，下载时跳过校验', () {
    final info = parseUpdateManifest(manifest(sha: null));
    expect(info, isNotNull);
    expect(info!.sha256, isNull);
  });

  test('格式不对时返回 null，检查更新应静默跳过', () {
    expect(parseUpdateManifest('{'), isNull);
    expect(parseUpdateManifest('[]'), isNull);
    expect(parseUpdateManifest(manifest(tag: 'not-a-version')), isNull);
    expect(parseUpdateManifest(manifest(url: 'http://insecure.example/a.apk')), isNull);
    expect(parseUpdateManifest(manifest(name: 'LigyTally-1.5.9.zip')), isNull);
    expect(parseUpdateManifest(manifest(sha: 'too-short')), isNull);
  });
}
