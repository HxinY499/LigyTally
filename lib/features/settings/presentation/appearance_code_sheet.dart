import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_widgets.dart';
import 'settings_widgets.dart';

/// 主题码浮层：上面是本机当前的码（可复制），下面可以粘一段别人的码。
///
/// ## 为什么值得做
///
/// 「让用户构造自己的 app」如果只是多给十几个开关，用户调完了也只有自己看得
/// 到。能把整套外观变成一段文本发出去，这件事才让那些开关有了外部意义——群里
/// 互相发码、README 里放几套官方码，都不需要再写任何功能。
///
/// 成本几乎为零，因为 [AppearanceConfig] 本来就是一个字符串（落盘用的就是
/// 同一套编解码，见 [AppearanceConfig.encode]）。
///
/// ## 壁纸不在码里
///
/// 壁纸是本机的一张图片文件，编进码里发给别人只会指向一个不存在的路径。
/// 所以导出时它被剔掉，导入时**保留接收方自己的壁纸**——否则贴一段别人的
/// 配色会顺手把自己的壁纸关掉。
/// 返回 true 表示确实套用了一段码；关掉浮层或只复制不导入返回 null。
///
/// 成功提示由调用方弹，不在浮层里弹：浮层这时候正在被销毁，
/// 拿它自己的 context 去找 toaster 会摸到一个已经失效的节点。
Future<bool?> showAppearanceCodeSheet(BuildContext context) {
  return showFSheet<bool>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (sheetContext) => const _AppearanceCodeSheet(),
  );
}

class _AppearanceCodeSheet extends ConsumerStatefulWidget {
  const _AppearanceCodeSheet();

  @override
  ConsumerState<_AppearanceCodeSheet> createState() =>
      _AppearanceCodeSheetState();
}

class _AppearanceCodeSheetState extends ConsumerState<_AppearanceCodeSheet> {
  final TextEditingController _input = TextEditingController();

  /// 上一次导入失败的提示；null 表示还没试过或成功了。
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    showAppToast(context, message: '主题码已复制', level: AppToastLevel.success);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) setState(() => _error = '剪贴板里没有文本');
      return;
    }
    _input.text = text;
    setState(() => _error = null);
  }

  void _apply() {
    final ok = ref.read(appearanceProvider.notifier).importCode(_input.text);
    if (!ok) {
      setState(() => _error = '这段文本不是主题码');
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // 导出的是**当前**配置，所以要 watch：浮层开着的时候用户仍可能
    // 从别处改到外观（比如撤销一次导入），码必须跟着变。
    final code = ref.watch(appearanceProvider).encode(includeWallpaper: false);
    final error = _error;
    return Material(
      color: colors.surface,
      borderRadius: context.radii.sheetTop,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '主题码',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  '整套外观压成一段文本，可以发给别人；壁纸不包含在内',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: colors.muted,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const SectionLabel('本机当前'),
              _CodeBlock(code: code, onCopy: () => _copy(code)),
              const SizedBox(height: 18),
              const SectionLabel('套用别人的'),
              AppTextField(
                controller: _input,
                hint: 'LT1~…',
                // 每次变化都 setState：既清掉上一次的报错，也让「套用」
                // 从空输入的禁用态里解禁。
                onChange: (_) => setState(() => _error = null),
              ),
              // 高度恒定：报错出现 / 消失时浮层不跳动。
              SizedBox(
                height: 20,
                child: error == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          error,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.danger,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      variant: AppButtonVariant.outline,
                      onPress: _paste,
                      child: const Text('从剪贴板粘贴'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      // 空输入时直接禁用，而不是让用户点一下才看到报错。
                      onPress: _input.text.trim().isEmpty ? null : _apply,
                      child: const Text('套用'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 码本身：等宽小字 + 一颗复制按钮。
///
/// 用凹底而不是描边框：这块是「可以拿走的一段数据」，不是输入框，
/// 不该长得像能改。
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.onCopy});

  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: context.radii.blockAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              code,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: colors.muted,
                // 码里全是短枚举名和数字，等宽下换行位置稳定，
                // 肉眼比对两段码时不会错位。
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            onPressed: onCopy,
            visualDensity: VisualDensity.compact,
            icon: Icon(FLucideIcons.copy, size: 17, color: colors.primary),
            tooltip: '复制',
          ),
        ],
      ),
    );
  }
}
