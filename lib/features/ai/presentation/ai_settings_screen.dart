import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;

import '../../../core/platform/open_url.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/ai_settings.dart';
import 'ai_platform_logo.dart';

/// 各官方平台的 BYOK 设置页。
///
/// Key 不预填、不回显完整值；保存后只展示首尾各四位。测试连接走各家不消耗
/// 对话额度的接口。配好的平台，模型才会出现在下面和对话里。
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final Map<AiPlatform, TextEditingController> _keyControllers = {
    for (final platform in AiPlatform.values) platform: TextEditingController(),
  };
  AiSettings? _settings;
  String _model = kDeepSeekDefaultModel;
  AiReasoningEffort _reasoning = AiReasoningEffort.fallback;
  bool _loading = true;
  AiPlatform? _saving;
  AiPlatform? _testing;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _keyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final value = await ref.read(aiSettingsProvider.future);
      if (!mounted) return;
      setState(() {
        _settings = value;
        _model = value.model;
        _reasoning = value.reasoning;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _retry() async {
    ref.invalidate(aiSettingsProvider);
    await _load();
  }

  Future<void> _save(AiPlatform platform) async {
    if (_saving != null) return;
    final spec = platformSpec(platform);
    final typed = _keyControllers[platform]!.text.trim();
    final existing = _settings?.keyFor(platform);
    final key = typed.isNotEmpty ? typed : existing;
    if (key == null || key.isEmpty) {
      _toast('请输入 ${spec.label} API Key', level: AppToastLevel.error);
      return;
    }
    setState(() => _saving = platform);
    await ref
        .read(aiSettingsProvider.notifier)
        .saveKey(platform: platform, apiKey: key);
    if (!mounted) return;
    final state = ref.read(aiSettingsProvider);
    setState(() => _saving = null);
    if (state.hasError) {
      _toast('保存失败：${state.error}', level: AppToastLevel.error);
      return;
    }
    _keyControllers[platform]!.clear();
    setState(() {
      _settings = state.value;
      _model = state.value?.model ?? _model;
    });
    _toast('${spec.label} Key 已保存', level: AppToastLevel.success);
  }

  Future<void> _test(AiPlatform platform) async {
    if (_testing != null) return;
    final spec = platformSpec(platform);
    final typed = _keyControllers[platform]!.text.trim();
    final key = typed.isNotEmpty ? typed : _settings?.keyFor(platform);
    if (key == null || key.isEmpty) {
      _toast('请先填写 API Key', level: AppToastLevel.error);
      return;
    }
    setState(() => _testing = platform);
    try {
      final response = await http
          .get(
            Uri.parse(spec.probeUrl),
            headers: {'Authorization': 'Bearer $key'},
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      switch (response.statusCode) {
        case 200:
          var available = true;
          if (platform == AiPlatform.deepseek) {
            try {
              final body = jsonDecode(response.body);
              if (body is Map && body['is_available'] == false) {
                available = false;
              }
            } on Object {
              // 余额接口的正文解析失败不影响「连接成功」这个结论。
            }
          }
          _toast(
            available ? '连接成功，Key 可用' : 'Key 有效，但账户当前不可用',
            level: available ? AppToastLevel.success : AppToastLevel.error,
          );
        case 401:
          _toast('Key 无效，请检查是否复制完整', level: AppToastLevel.error);
        case 402:
          _toast('${spec.label} 余额不足，请先充值', level: AppToastLevel.error);
        case 429:
          _toast('请求过于频繁，请稍后再试', level: AppToastLevel.error);
        default:
          _toast(
            '连接失败（HTTP ${response.statusCode}）',
            level: AppToastLevel.error,
          );
      }
    } on Object {
      if (mounted) {
        _toast('连接失败，请检查网络后重试', level: AppToastLevel.error);
      }
    } finally {
      if (mounted) setState(() => _testing = null);
    }
  }

  Future<void> _clear(AiPlatform platform) async {
    final label = platformSpec(platform).label;
    final confirmed = await showAppConfirmDialog(
      context,
      message: '清除 $label Key 后，这个平台的模型不再可选。账单数据不受影响。',
      confirmLabel: '清除 Key',
    );
    if (!confirmed || !mounted) return;
    await ref.read(aiSettingsProvider.notifier).clearKey(platform);
    if (!mounted) return;
    final state = ref.read(aiSettingsProvider);
    if (state.hasError) {
      _toast('清除失败：${state.error}', level: AppToastLevel.error);
      return;
    }
    _keyControllers[platform]!.clear();
    setState(() {
      _settings = state.value;
      _model = state.value?.model ?? _model;
    });
    _toast('Key 已清除', level: AppToastLevel.success);
  }

  void _toast(String message, {AppToastLevel level = AppToastLevel.info}) {
    showAppToast(context, message: message, level: level);
  }

  Future<void> _open(String url) async {
    final ok = await openExternalUrl(url);
    if (!ok && mounted) {
      _toast('无法打开网页', level: AppToastLevel.error);
    }
  }

  Widget _platformCard(AiPlatformSpec spec, AppColors colors) {
    final configured = _settings?.hasKeyFor(spec.id) ?? false;
    final saving = _saving == spec.id;
    final testing = _testing == spec.id;
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AiPlatformLogo(spec.id, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      spec.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.ink,
                        height: 1.2,
                      ),
                    ),
                  ),
                  Text(
                    configured ? _settings!.maskedKeyFor(spec.id) : '未配置',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.inactive,
                      height: 1.2,
                    ),
                  ),
                  if (configured)
                    _CardAction(
                      label: '清除',
                      color: colors.danger,
                      onTap: () => _clear(spec.id),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              AppTextField(
                controller: _keyControllers[spec.id],
                hint: configured ? '留空则保持当前 Key' : '粘贴 API Key',
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
              ),
              Row(
                children: [
                  _KeyLink(
                    label: '申请 Key',
                    onTap: () => _open(spec.keyPageUrl),
                  ),
                  const Spacer(),
                  _CardAction(
                    label: testing ? '测试中' : '测试',
                    color: colors.muted,
                    onTap: _testing != null ? null : () => _test(spec.id),
                  ),
                  _CardAction(
                    label: saving ? '保存中' : '保存',
                    color: colors.primary,
                    onTap: _saving != null ? null : () => _save(spec.id),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTopBar(
      title: 'AI 助手设置',
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            40 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverList.list(
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null)
                _ErrorCard(message: '读取设置失败：$_loadError', onRetry: _retry)
              else ...[
                for (final spec in kAiPlatforms) ...[
                  _platformCard(spec, colors),
                  const SizedBox(height: 10),
                ],
                const SectionLabel('模型'),
                if ((_settings?.availableModels ?? const []).isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '配好 Key 后，对应平台的模型会出现在这里。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: colors.inactive,
                      ),
                    ),
                  )
                else
                  SettingsCard(
                    children: [
                      for (final model in _settings!.availableModels)
                        _ModelOption(
                          title: model.id,
                          mark: AiPlatformLogo(model.platform, size: 22),
                          selected: model.id == _model,
                          onTap: () async {
                            setState(() => _model = model.id);
                            await ref
                                .read(aiSettingsProvider.notifier)
                                .setModel(model.id);
                          },
                        ),
                    ],
                  ),
                const SizedBox(height: 18),
                const SectionLabel('思考'),
                SettingsCard(
                  children: [
                    for (final effort in AiReasoningEffort.values)
                      _ModelOption(
                        title: effort.label,
                        icon: FLucideIcons.brain,
                        selected: effort == _reasoning,
                        onTap: () async {
                          setState(() => _reasoning = effort);
                          await ref
                              .read(aiSettingsProvider.notifier)
                              .setReasoning(effort);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '从下一轮对话开始生效。智谱和 Kimi 的当前模型不能关闭思考，选「关」时按最低强度发送。',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.inactive,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({required this.label, required this.color, this.onTap});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _KeyLink extends StatelessWidget {
  const _KeyLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: colors.primary,
                height: 1.2,
              ),
            ),
            const SizedBox(width: 4),
            Icon(FLucideIcons.externalLink, size: 13, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

class _ModelOption extends StatelessWidget {
  const _ModelOption({
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon = FLucideIcons.cpu,
    this.mark,
  });

  final String title;
  final IconData icon;
  final Widget? mark;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: selected ? colors.primarySoft : Colors.transparent,
      child: SettingsItem(
        icon: icon,
        mark: mark,
        title: title,
        selected: selected,
        trailing: selected
            ? Icon(FLucideIcons.check, size: 18, color: colors.primary)
            : const SizedBox(width: 18, height: 18),
        onTap: onTap,
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message, style: TextStyle(color: context.colors.danger)),
              const SizedBox(height: 12),
              AppButton(
                variant: AppButtonVariant.outline,
                onPress: onRetry,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
