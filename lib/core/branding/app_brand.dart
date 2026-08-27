/// 对外品牌与上架合规信息。
///
/// 桌面名、关于页、商店、软著、APP 备案必须用同一套中文名。
/// 包名 `com.ligy.ligy_tally` 与发布签名不在这里，也不许改。
library;

/// 用户看见的应用名。
const kAppDisplayName = '里格账';

/// 口头说法，不替代 [kAppDisplayName]。
const kAppSlogan = '理个账';

/// 工信部核发的备案编号，必须与 beian.miit.gov.cn 查询结果逐字一致。
///
/// 当前填的是主体号。若阿里云里「里格账」那条是带 `-1` 的 APP 号，
/// 关于页应改成那一条，不要只挂主体号。
const kIcpFilingNumber = '陕ICP备2026023367号';

/// 工信部备案查询页。备案号必须可点到这里。
const kIcpQueryUrl = 'https://beian.miit.gov.cn/';

/// 商店与关于页使用的隐私政策地址。页面在已备案域名上，不用 OSS 默认域名。
const kPrivacyPolicyUrl = 'https://ligezhang.cn/privacy.html';

/// 隐私政策与商店页公示的联系邮箱。
///
/// 政策正文不写开发者姓名，可联系这一条就落在这里，不能留空。
const kSupportEmail = '838195242@qq.com';
