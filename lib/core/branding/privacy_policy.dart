/// 隐私政策正文。应用内与网站页用同一套事实，不要各写各的。
///
/// 主体写应用名、不写开发者姓名。《个人信息保护法》要求能告知处理者并留下
/// 联系方式，这里由 [kSupportEmail] 承担——去掉姓名不等于去掉可联系。
library;

import 'app_brand.dart';

/// 政策展示用的一节。
class PrivacySection {
  const PrivacySection(this.title, this.body);

  final String title;
  final String body;
}

const kPrivacyPolicyUpdatedAt = '2026年8月27日';

const kPrivacyPolicySections = <PrivacySection>[
  PrivacySection(
    '这份政策说什么',
    '$kAppDisplayName 是一款本地记账工具，没有账号系统，也不提供云端同步。'
        '这份政策说明它会用到哪些信息、存在哪里，以及你能怎么收回。',
  ),
  PrivacySection(
    '记账数据存在哪',
    '收支、分类、备注、账单图片和备份都只保存在你这台手机的应用私有目录。'
        '卸载应用会一并删除这些数据，除非你事先导出了备份。',
  ),
  PrivacySection(
    '位置',
    '可选。只有你打开「记账时自动记录位置」，或主动给某笔账记位置时，'
        '才会向系统申请定位，并用系统逆地理把坐标转成地名。'
        '位置写在该笔账的本地记录里，不会上传。',
  ),
  PrivacySection(
    '相机与照片',
    '只有你主动拍照或从相册选图当账单附件时，才会使用相机或系统照片选择器。'
        '图片会在本地重新编码并去掉 EXIF、GPS 等元数据，然后只存在应用私有目录。',
  ),
  PrivacySection(
    '网络',
    '应用会连接网络，用于检查新版本并下载安装包。'
        '检查更新不会附带你的账单内容。'
        '隐私政策网页托管在 ligezhang.cn。',
  ),
  PrivacySection(
    '不会做的事',
    '不注册账号，不做广告，不接统计分析 SDK，'
        '不把账单、图片、位置或备份上传到本应用的服务器，也不出售或共享给第三方。',
  ),
  PrivacySection(
    '权限随时可关',
    '定位、相机、相册都可以在系统设置里收回。'
        '关掉后，对应功能不可用，已保存在本地的记录不会因此被删。'
        '要删除全部数据，卸载应用即可。',
  ),
  PrivacySection('联系方式', '对本政策或数据处理有疑问，可发邮件到 $kSupportEmail。'),
];
