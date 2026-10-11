import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../application/ledger_service.dart';
import '../application/providers.dart';
import 'template_screen.dart';
import 'template_widgets.dart';

/// 明细页「模板」入口弹出的记账面板：点一行就记一笔，面板不关。
///
/// 不关是刻意的：每月固定账单往往是一串（房租、话费、会员、工资），
/// 每点一笔就关一次，用户得反复打开。点过的行挂「已记」角标，
/// 防止同一笔手滑记两次却没察觉；真记错了，toast 上有撤销。
Future<void> showTemplateSheet(BuildContext context) {
  final colors = context.colors;
  return showModalBottomSheet<void>(
    context: context,
    // 和明细页同一层关系：灰底上浮白卡，模板行与账单行长得一样。
    backgroundColor: colors.canvasBase,
    shape: context.radii.sheetTopShape,
    clipBehavior: Clip.antiAlias,
    // 让面板高度跟内容走，不被默认的 9/16 屏高截住；上限由列表自己控制。
    isScrollControlled: true,
    builder: (_) => const _TemplateSheet(),
  );
}

class _TemplateSheet extends ConsumerStatefulWidget {
  const _TemplateSheet();

  @override
  ConsumerState<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends ConsumerState<_TemplateSheet> {
  /// 本次打开面板后每个模板记了几笔。只活在这一次面板里：
  /// 它回答的是「我刚才点没点过」，不是「这个月记没记过」。
  final Map<String, int> _recorded = {};

  /// 正在写库的模板，防连点重复记账。
  final Set<String> _pending = {};

  late final Stream<List<TemplateItem>> _templates = ref
      .read(databaseProvider)
      .watchTemplates();

  Future<void> _record(TemplateItem item) async {
    final id = item.template.id;
    if (_pending.contains(id)) return;
    // 撤销可能发生在面板关掉之后：服务和 toast 宿主都要先拿稳，
    // 不能在回调里再碰 ref 和本面板的 context。
    final service = ref.read(ledgerServiceProvider);
    final host = Navigator.of(context, rootNavigator: true).context;
    final grouped = ref.read(moneyGroupedProvider);
    setState(() => _pending.add(id));
    try {
      final transactionId = await service.recordTemplate(item);
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() {
          _pending.remove(id);
          _recorded.update(id, (count) => count + 1, ifAbsent: () => 1);
        });
      }
      if (!host.mounted) return;
      final sign = item.template.kind == 0 ? '-' : '+';
      showAppToast(
        host,
        message: '已记入今天',
        description:
            '${item.title} $sign'
            '${formatMoney(item.template.amountCents, grouped: grouped)}',
        level: AppToastLevel.success,
        // 默认 2 秒不够反应过来点撤销。
        duration: const Duration(seconds: 4),
        suffixBuilder: (_, entry) => _UndoButton(
          onTap: () {
            entry.dismiss();
            _undo(service, host, id, transactionId);
          },
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _pending.remove(id));
      if (host.mounted) {
        showAppToast(host, message: '记账失败：$error', level: AppToastLevel.error);
      }
    }
  }

  Future<void> _undo(
    LedgerService service,
    BuildContext host,
    String templateId,
    String transactionId,
  ) async {
    try {
      await service.undoTemplateRecord(transactionId);
      if (mounted) {
        setState(() {
          final left = (_recorded[templateId] ?? 1) - 1;
          if (left > 0) {
            _recorded[templateId] = left;
          } else {
            _recorded.remove(templateId);
          }
        });
      }
      if (host.mounted) showAppToast(host, message: '已撤销这笔');
    } catch (error) {
      if (host.mounted) {
        showAppToast(host, message: '撤销失败：$error', level: AppToastLevel.error);
      }
    }
  }

  void _openManagement() {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const TemplateScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final grouped = ref.watch(moneyGroupedProvider);
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.6;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(
            height: 44,
            child: Stack(
              children: [
                Center(
                  child: Text(
                    '模板记账',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: InkWell(
                      onTap: _openManagement,
                      borderRadius: context.radii.chipAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          '管理',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          StreamBuilder<List<TemplateItem>>(
            stream: _templates,
            builder: (context, snapshot) {
              final all = snapshot.data;
              if (all == null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: CircularProgressIndicator(color: colors.primary),
                );
              }
              // 分类停用的模板不在这里出现：用户停用分类就是不想再往里记。
              // 管理页仍列着它们，可以改到别的分类。
              final usable = [
                for (final item in all)
                  if (item.category.isActive) item,
              ];
              if (usable.isEmpty) {
                return TemplateEmptyState(
                  title: all.isEmpty ? '还没有模板' : '没有可用的模板',
                  detail: all.isEmpty
                      ? '把每月固定的房租、话费、工资存成模板，之后点一下就能记一笔'
                      : '模板用到的分类都已停用，去「管理」里换个分类',
                  onCreate: () => openTemplateEditor(context),
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxListHeight),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: TemplateCard(
                        children: [
                          for (final item in usable)
                            TemplateTile(
                              item: item,
                              grouped: grouped,
                              onTap: () => _record(item),
                              iconBadge: _recorded.containsKey(item.template.id)
                                  ? _RecordedBadge(
                                      key: ValueKey(
                                        'template-recorded-${item.template.id}',
                                      ),
                                      count: _recorded[item.template.id]!,
                                    )
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      '点一下立即记入今天，记完可在明细里修改',
                      style: TextStyle(fontSize: 12, color: colors.inactive),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 「本次已记」角标：一笔画勾，多笔写数字。
///
/// 和记一笔页图片入口的张数角标同一副长相（18 圆、品牌色、白字）。
class _RecordedBadge extends StatelessWidget {
  const _RecordedBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: colors.surface, width: 1.5),
      ),
      child: count > 1
          ? Text(
              '$count',
              style: const TextStyle(
                fontSize: 10,
                height: 1,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            )
          : const Icon(FLucideIcons.check, size: 11, color: Colors.white),
    );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          '撤销',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: context.colors.primary,
          ),
        ),
      ),
    );
  }
}
