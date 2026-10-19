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

const kPrivacyPolicyUpdatedAt = '2026年10月19日';

const kPrivacyPolicySections = <PrivacySection>[
  PrivacySection(
    '这份政策说什么',
    '$kAppDisplayName 是一款本地记账工具，没有账号系统，也不提供云端同步。'
        '这份政策说明它会用到哪些信息、存在哪里，以及你能怎么收回。'
        'AI 助手是可选功能，只有你主动配置并使用它时才会联网处理数据。',
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
    '应用会连接网络，用于检查新版本、下载安装包，以及在你使用 AI 助手时'
        '直接请求 DeepSeek API。检查更新不会附带你的账单内容；'
        'AI 请求的数据范围见下面的「AI 助手」一节。'
        '隐私政策网页托管在 ligezhang.cn。',
  ),
  PrivacySection(
    'AI 助手（可选）',
    'AI 助手默认关闭，需要你在应用内填入自己的 DeepSeek API Key 才能使用。'
        '这个 Key 只保存在本机 Android Keystore，不写入备份，也不会上传到'
        '本应用的服务器。使用 AI 时，你输入的问题、本次查询所需的账单摘要'
        '或片段，以及当前时间会通过 HTTPS 直接发送给 DeepSeek 的 API；'
        '图片、位置和备份不会发送。DeepSeek 可能按其隐私政策处理这些数据，'
        '详情见 https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html。'
        'AI 对话记录保存在本机，可在会话列表删除；关闭 AI 或卸载应用后，'
        '手动记账功能不受影响。',
  ),
  PrivacySection(
    '不会做的事',
    '不注册账号，不做广告，不接统计分析 SDK，'
        '不把账单、图片、位置或备份上传到本应用的服务器，也不出售数据。'
        '只有你主动使用 AI 助手时，才会把本次问题所需的账单摘要或片段'
        '发送给 DeepSeek；不会发送图片、位置或备份。',
  ),
  PrivacySection(
    '权限随时可关',
    '定位、相机、相册都可以在系统设置里收回。'
        '关掉后，对应功能不可用，已保存在本地的记录不会因此被删。'
        '要删除全部数据，卸载应用即可。',
  ),
  PrivacySection('联系方式', '对本政策或数据处理有疑问，可发邮件到 $kSupportEmail。'),
];
