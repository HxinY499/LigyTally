/// 已经接入的官方平台。配了哪一家的 Key，模型列表就多出那一家。
enum AiPlatform { deepseek, glm, kimi }

class AiPlatformSpec {
  const AiPlatformSpec({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.keyPageUrl,
    required this.keyLinkLabel,
    required this.probeUrl,
  });

  final AiPlatform id;
  final String label;

  /// OpenAI 兼容的 Chat Completions 根地址，请求时再补 `/chat/completions`。
  final String baseUrl;
  final String keyPageUrl;
  final String keyLinkLabel;

  /// 不消耗对话额度的连通性检查。
  final String probeUrl;
}

class AiModelSpec {
  const AiModelSpec({
    required this.id,
    required this.platform,
    required this.acceptsImages,
    required this.thinkingAlwaysOn,
  });

  final String id;
  final AiPlatform platform;
  final bool acceptsImages;

  /// 官方不允许关掉思考。界面上的「关」会按最低强度发送，避免请求直接失败。
  final bool thinkingAlwaysOn;
}

const kAiPlatforms = <AiPlatformSpec>[
  AiPlatformSpec(
    id: AiPlatform.deepseek,
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    keyPageUrl: 'https://platform.deepseek.com/api_keys',
    keyLinkLabel: '去 DeepSeek 开放平台申请 Key',
    probeUrl: 'https://api.deepseek.com/user/balance',
  ),
  AiPlatformSpec(
    id: AiPlatform.glm,
    label: '智谱',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    keyPageUrl: 'https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys',
    keyLinkLabel: '去智谱开放平台申请 Key',
    probeUrl: 'https://open.bigmodel.cn/api/paas/v4/models',
  ),
  AiPlatformSpec(
    id: AiPlatform.kimi,
    label: 'Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    keyPageUrl: 'https://platform.kimi.com/console/api-keys',
    keyLinkLabel: '去 Kimi 开放平台申请 Key',
    probeUrl: 'https://api.moonshot.cn/v1/users/me/balance',
  ),
];

/// 各家当前文档里还在提供的模型。退役的 id 不放进来。
const kAiModels = <AiModelSpec>[
  AiModelSpec(
    id: 'deepseek-flash',
    platform: AiPlatform.deepseek,
    acceptsImages: true,
    thinkingAlwaysOn: false,
  ),
  AiModelSpec(
    id: 'deepseek-v4-pro',
    platform: AiPlatform.deepseek,
    acceptsImages: false,
    thinkingAlwaysOn: false,
  ),
  AiModelSpec(
    id: 'glm-5.3',
    platform: AiPlatform.glm,
    acceptsImages: false,
    thinkingAlwaysOn: true,
  ),
  AiModelSpec(
    id: 'glm-5.3-flash',
    platform: AiPlatform.glm,
    acceptsImages: true,
    thinkingAlwaysOn: true,
  ),
  AiModelSpec(
    id: 'kimi-k3.1-pro',
    platform: AiPlatform.kimi,
    acceptsImages: true,
    thinkingAlwaysOn: true,
  ),
  AiModelSpec(
    id: 'kimi-k3.1-pro-highspeed',
    platform: AiPlatform.kimi,
    acceptsImages: true,
    thinkingAlwaysOn: true,
  ),
  AiModelSpec(
    id: 'kimi-k3',
    platform: AiPlatform.kimi,
    acceptsImages: true,
    thinkingAlwaysOn: true,
  ),
];

const kDeepSeekDefaultModel = 'deepseek-flash';

AiPlatformSpec platformSpec(AiPlatform id) {
  for (final spec in kAiPlatforms) {
    if (spec.id == id) return spec;
  }
  throw ArgumentError.value(id, 'id', '未知的模型平台');
}

AiModelSpec? aiModelById(String id) {
  for (final spec in kAiModels) {
    if (spec.id == id) return spec;
  }
  return null;
}

bool modelAcceptsImages(String id) => aiModelById(id)?.acceptsImages ?? false;

/// 已配置的平台按 [kAiModels] 的顺序叠在一起。
List<AiModelSpec> modelsForConfigured(Set<AiPlatform> configured) {
  return [
    for (final spec in kAiModels)
      if (configured.contains(spec.platform)) spec,
  ];
}

/// 记忆的模型还在、并且那一家已经配了 Key 时沿用，否则用第一个可用模型。
String resolveSelectedModel(String? stored, Set<AiPlatform> configured) {
  final spec = stored == null ? null : aiModelById(stored);
  if (spec != null && configured.contains(spec.platform)) return spec.id;
  for (final model in kAiModels) {
    if (configured.contains(model.platform)) return model.id;
  }
  return kDeepSeekDefaultModel;
}
