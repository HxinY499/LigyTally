import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../application/providers.dart';
import 'template_widgets.dart';
import 'transaction_editor.dart';

/// 打开模板编辑页。[existing] 为 null 时新建。
Future<void> openTemplateEditor(
  BuildContext context, {
  TemplateItem? existing,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => TransactionEditor.template(existingTemplate: existing),
    ),
  );
}

/// 模板管理页：列出全部模板（含分类已停用的），点一行进编辑，右上角新建。
///
/// 停用分类的模板也列在这里：记账面板会把它们藏起来，这里再不露面，
/// 用户就再也找不回来改了。
class TemplateScreen extends ConsumerWidget {
  const TemplateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(databaseProvider);
    final grouped = ref.watch(moneyGroupedProvider);
    return Scaffold(
      body: StreamBuilder<List<TemplateItem>>(
        stream: database.watchTemplates(),
        builder: (context, snapshot) {
          final items = snapshot.data;
          return AppTopBar(
            title: '记账模板',
            actions: [
              AppHeaderAction(
                icon: FLucideIcons.plus,
                tooltip: '新建模板',
                onTap: () => openTemplateEditor(context),
              ),
            ],
            slivers: [
              if (items == null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: context.colors.primary,
                      ),
                    ),
                  ),
                )
              else if (items.isEmpty)
                SliverToBoxAdapter(
                  child: TemplateEmptyState(
                    title: '还没有模板',
                    detail:
                        '把每月固定的房租、话费、工资存成模板，'
                        '在明细页点「模板」就能一键记账',
                    onCreate: () => openTemplateEditor(context),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverList.list(
                    children: [
                      TemplateCard(
                        children: [
                          for (final item in items)
                            TemplateTile(
                              item: item,
                              grouped: grouped,
                              onTap: () =>
                                  openTemplateEditor(context, existing: item),
                              trailing: Icon(
                                FLucideIcons.chevronRight,
                                size: 18,
                                color: context.colors.faint,
                              ),
                            ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                        child: Text(
                          '套用模板时记入今天、当前时刻，记完可以在明细里再改。',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.inactive,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
