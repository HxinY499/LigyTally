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

const _deepSeekPrivacyUrl =
    'https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html';
const _deepSeekKeysUrl = 'https://platform.deepseek.com/api_keys';

/// DeepSeek BYOK 设置页。
///
/// Key 不预填、不回显完整值；保存后只展示首尾各四位。测试连接走 DeepSeek
/// 的余额接口，既不消耗 token，也能顺带发现余额不足。
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  AiSettings? _settings;
  String _model = kDeepSeekDefaultModel;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyController.dispose();
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

  Future<void> _save() async {
    if (_saving) return;
    final typed = _keyController.text.trim();
    final existing = _settings?.apiKey?.trim();
    final key = typed.isNotEmpty ? typed : existing;
    if (key == null || key.isEmpty) {
      _toast('请输入 DeepSeek API Key', level: AppToastLevel.error);
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(aiSettingsProvider.notifier)
        .save(apiKey: key, model: _model);
    if (!mounted) return;
    final state = ref.read(aiSettingsProvider);
    setState(() => _saving = false);
    if (state.hasError) {
      _toast('保存失败：${state.error}', level: AppToastLevel.error);
      return;
    }
    _keyController.clear();
    setState(() => _settings = state.value);
    _toast('AI 设置已保存', level: AppToastLevel.success);
  }

  Future<void> _test() async {
    if (_testing) return;
    final typed = _keyController.text.trim();
    final key = typed.isNotEmpty ? typed : _settings?.apiKey?.trim();
    if (key == null || key.isEmpty) {
      _toast('请先填写 API Key', level: AppToastLevel.error);
      return;
    }
    setState(() => _testing = true);
    try {
      final response = await http
          .get(
            Uri.parse('https://api.deepseek.com/user/balance'),
            headers: {'Authorization': 'Bearer $key'},
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      switch (response.statusCode) {
        case 200:
          var available = true;
          try {
            final body = jsonDecode(response.body);
            if (body is Map && body['is_available'] == false) {
              available = false;
            }
          } on Object {
            // 余额接口的正文解析失败不影响「连接成功」这个结论。
          }
          _toast(
            available ? '连接成功，Key 可用' : 'Key 有效，但账户当前不可用',
            level: available ? AppToastLevel.success : AppToastLevel.error,
          );
        case 401:
          _toast('Key 无效，请检查是否复制完整', level: AppToastLevel.error);
        case 402:
          _toast('DeepSeek 余额不足，请先充值', level: AppToastLevel.error);
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
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showAppConfirmDialog(
      context,
      message: '清除 DeepSeek Key 后 AI 助手将不可用，账单数据不受影响。',
      confirmLabel: '清除 Key',
    );
    if (!confirmed || !mounted) return;
    await ref.read(aiSettingsProvider.notifier).clearKey();
    if (!mounted) return;
    final state = ref.read(aiSettingsProvider);
    if (state.hasError) {
      _toast('清除失败：${state.error}', level: AppToastLevel.error);
      return;
    }
    _keyController.clear();
    setState(() => _settings = state.value);
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
                const SectionLabel('DeepSeek'),
                SettingsCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTextField(
                            controller: _keyController,
                            label: const Text('API Key'),
                            hint: 'sk-...',
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.visiblePassword,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '当前：${_settings?.maskedKey ?? '未配置'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.inactive,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => _open(_deepSeekKeysUrl),
                            child: Text(
                              '去 DeepSeek 开放平台申请 Key',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.primary,
                                height: 1.35,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  onPress: _saving ? null : _save,
                                  child: Text(_saving ? '保存中…' : '保存'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AppButton(
                                  variant: AppButtonVariant.outline,
                                  onPress: _testing ? null : _test,
                                  child: Text(_testing ? '测试中…' : '测试连接'),
                                ),
                              ),
                            ],
                          ),
                          if (_settings?.hasKey ?? false) ...[
                            const SizedBox(height: 8),
                            AppButton(
                              variant: AppButtonVariant.ghost,
                              onPress: _clear,
                              child: const Text('清除 Key'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const SectionLabel('模型'),
                SettingsCard(
                  children: [
                    for (final model in kDeepSeekModels)
                      SettingsItem(
                        icon: model == 'deepseek-flash'
                            ? FLucideIcons.zap
                            : FLucideIcons.brain,
                        title: model,
                        subtitle: model == 'deepseek-flash'
                            ? '日常查账、记账，速度快'
                            : '复杂分析，成本更高',
                        trailing: model == _model
                            ? Icon(
                                FLucideIcons.check,
                                size: 18,
                                color: colors.primary,
                              )
                            : null,
                        onTap: () async {
                          setState(() => _model = model);
                          await ref
                              .read(aiSettingsProvider.notifier)
                              .setModel(model);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const SectionLabel('数据与隐私'),
                SettingsCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Key 只保存在本机 Android Keystore，AI 请求直接发往 DeepSeek，不经过本应用服务器。\n\n'
                        '使用 AI 时，你输入的问题、本次查询所需的账单摘要或片段，以及当前时间会发送给 DeepSeek；图片、位置和备份不会发送。AI 对话保存在本机，可在聊天页清空。\n\n'
                        'DeepSeek 可能按其隐私政策处理这些数据，请先阅读并确认。',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.ink,
                          height: 1.55,
                        ),
                      ),
                    ),
                    SettingsItem(
                      icon: FLucideIcons.shieldCheck,
                      title: 'DeepSeek 隐私政策',
                      showChevron: true,
                      onTap: () => _open(_deepSeekPrivacyUrl),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'AI 可能理解错金额或分类。涉及删除时会弹确认，记账前请核对摘要。',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.inactive,
                    height: 1.45,
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
