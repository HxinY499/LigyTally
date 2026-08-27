import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_widgets.dart';

/// 把已排除的分类收成一句短文案，给过滤条和 Hero 卡共用。
String statsExclusionCaption(List<CategoryEntry> excluded) {
  if (excluded.isEmpty) return '';
  if (excluded.length == 1) return '不含${excluded.single.name}';
  if (excluded.length == 2) {
    return '不含${excluded[0].name}、${excluded[1].name}';
  }
  return '不含${excluded[0].name}、${excluded[1].name}等 ${excluded.length} 类';
}

/// 按分类列表顺序取出 [ids] 对应的项，丢掉已经不存在的 id。
List<CategoryEntry> resolveExcludedCategories(
  List<CategoryEntry> categories,
  Set<String> ids,
) {
  if (ids.isEmpty) return const [];
  return [
    for (final item in categories)
      if (ids.contains(item.id)) item,
  ];
}

/// 点选排除项：一级会清掉它下面已勾的二级；二级会把所属一级从名单里拿掉。
Set<String> toggleExcludedCategory({
  required List<CategoryEntry> categories,
  required Set<String> selected,
  required String id,
}) {
  final byId = {for (final item in categories) item.id: item};
  final category = byId[id];
  if (category == null) return selected;
  final next = {...selected};
  if (next.contains(id)) {
    next.remove(id);
    return next;
  }
  if (category.level == 1) {
    next.removeWhere((item) => byId[item]?.parentId == id);
    next.add(id);
  } else {
    next.remove(category.parentId);
    next.add(id);
  }
  return next;
}

/// 统计页头右侧的过滤入口：和记账页搜索同一套操作行。
///
/// 过滤是整页口径，不该再占周期选择器下面一条——那会和「看哪一段时间」抢位置。
/// 开启后图标改成主色并带圆点，具体去掉了哪几类由 Hero 卡上的「不含 ××」说明。
class StatsExclusionAction extends StatelessWidget {
  const StatsExclusionAction({
    super.key,
    required this.categories,
    required this.excludedIds,
    required this.onChanged,
  });

  final List<CategoryEntry> categories;
  final Set<String> excludedIds;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final excluded = resolveExcludedCategories(categories, excludedIds);
    final active = excluded.isNotEmpty;
    final tooltip = active ? statsExclusionCaption(excluded) : '排除分类';

    return Tooltip(
      message: tooltip,
      child: InkResponse(
        key: const ValueKey('stats-exclusion-action'),
        onTap: () => _pick(context),
        radius: kAppHeaderActionSize / 2,
        containedInkWell: true,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: kAppHeaderActionSize,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                FLucideIcons.filter,
                size: kAppHeaderIconSize,
                color: active ? colors.primary : colors.ink,
              ),
              if (active)
                Positioned(
                  top: 7,
                  right: 7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.canvas, width: 1.5),
                    ),
                    child: const SizedBox.square(dimension: 8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final selected = await showStatsExclusionSheet(
      context,
      categories: categories,
      selectedIds: excludedIds,
    );
    if (selected == null) return;
    onChanged(selected);
  }
}

/// 多选要排除的分类，收支两侧都在里面。
/// 取消返回 null；确定返回新的 id 集合（可空 = 清除）。
Future<Set<String>?> showStatsExclusionSheet(
  BuildContext context, {
  required List<CategoryEntry> categories,
  required Set<String> selectedIds,
}) {
  return showFSheet<Set<String>>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    builder: (sheetContext) =>
        _ExclusionSheet(categories: categories, initialIds: selectedIds),
  );
}

class _ExclusionSheet extends StatefulWidget {
  const _ExclusionSheet({required this.categories, required this.initialIds});

  final List<CategoryEntry> categories;
  final Set<String> initialIds;

  @override
  State<_ExclusionSheet> createState() => _ExclusionSheetState();
}

class _ExclusionSheetState extends State<_ExclusionSheet> {
  late Set<String> _selected = {...widget.initialIds};

  /// 按收支切成两段。某一侧一个分类都没有时不出小标题，免得留一个空段。
  List<({String label, List<CategoryEntry> categories})> get _sections {
    final sections = <({String label, List<CategoryEntry> categories})>[];
    for (final (kind, label) in const [(0, '支出'), (1, '收入')]) {
      final items = widget.categories
          .where((item) => item.kind == kind)
          .toList();
      if (items.isEmpty) continue;
      sections.add((label: label, categories: items));
    }
    return sections;
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = toggleExcludedCategory(
        categories: widget.categories,
        selected: _selected,
        id: id,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Material(
      color: colors.surface,
      shape: context.radii.sheetTopShape,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: Row(
                children: [
                  _SheetAction(
                    label: '取消',
                    onTap: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '排除分类',
                          textAlign: TextAlign.center,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '只改统计口径，账单还在',
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(
                            fontSize: 12,
                            color: colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _SheetAction(
                    label: '确定',
                    primary: true,
                    onTap: () =>
                        Navigator.pop(context, Set<String>.of(_selected)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                child: Column(
                  children: [
                    if (_selected.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selected = {});
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: colors.primary,
                            minimumSize: const Size(88, 44),
                            tapTargetSize: MaterialTapTargetSize.padded,
                          ),
                          child: const Text('清除全部'),
                        ),
                      ),
                    // 收支两侧摆在同一条滚动轴上，不做分段切换：排除的是
                    // 分类，用户心里想的是「把这几类拿掉」，不是「先决定
                    // 看哪一侧」。小标题只用来说明滑到哪儿了。
                    for (final section in _sections) ...[
                      _SectionLabel(text: section.label),
                      CategoryPicker(
                        categories: section.categories,
                        selectedIds: _selected,
                        accent: colors.primary,
                        accentSoft: colors.primarySoft,
                        // 浮层的卡面已经是白的，底座只能往下走一档。
                        idleBackground: colors.fill,
                        layout: CategoryPickerLayout.grid,
                        onSelected: _toggle,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 浮层里的分段小标题：`支出` / `收入`。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.colors.muted,
          ),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radii.chipAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: primary ? colors.primary : colors.muted,
            fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
