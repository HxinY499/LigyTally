import 'package:flutter/material.dart';

import '../../core/appearance/appearance_config.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_theme.dart';
import 'category_icon_view.dart';

/// 记账页与统计排除共用的分类选择器。
///
/// 格子、一级展开二级、列表/网格两种排法都在这里，避免两处各写一套
/// 然后慢慢漂开。选中语义由调用方解释：记账是单选，排除是多选。
class CategoryPicker extends StatefulWidget {
  const CategoryPicker({
    super.key,
    required this.categories,
    required this.selectedIds,
    required this.accent,
    required this.layout,
    required this.onSelected,
  });

  final List<CategoryEntry> categories;

  /// 当前选中的分类 id。记账页通常只有一个；排除浮层可以有多个。
  final Set<String> selectedIds;

  /// 选中态的图标/文字色。
  final Color accent;
  final CategoryPickerLayout layout;
  final ValueChanged<String> onSelected;

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  static const _columns = 5;

  /// 手风琴模式：同一时间只允许一个一级分类展开。
  String? _expandedId;

  /// 每行最近一次展开过的一级分类 id（网格模式，key 为行号）。
  ///
  /// 收起后 [_expandedId] 变 null，但该行的面板必须继续留在树上、拿着原来的
  /// 二级分类数据，才能把收起动画播完，所以要单独记住"这行该给谁挂面板"。
  final Map<int, String> _rowPanelOwner = {};

  @override
  void initState() {
    super.initState();
    _expandedId = _parentIdOf(_firstSelectedId);
  }

  @override
  void didUpdateWidget(covariant CategoryPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIds.isEmpty && _expandedId != null) {
      _expandedId = null;
      _rowPanelOwner.clear();
    }
  }

  String? get _firstSelectedId =>
      widget.selectedIds.isEmpty ? null : widget.selectedIds.first;

  String? _parentIdOf(String? categoryId) {
    if (categoryId == null) return null;
    for (final category in widget.categories) {
      if (category.id == categoryId) {
        return category.level == 1 ? category.id : category.parentId;
      }
    }
    return null;
  }

  List<CategoryEntry> _childrenOf(String parentId) {
    return widget.categories
        .where((item) => item.parentId == parentId)
        .toList();
  }

  bool _parentSelected(CategoryEntry parent) {
    if (widget.selectedIds.contains(parent.id)) return true;
    return widget.categories.any(
      (item) =>
          item.parentId == parent.id && widget.selectedIds.contains(item.id),
    );
  }

  bool _childSelected(CategoryEntry child) {
    if (widget.selectedIds.contains(child.id)) return true;
    final parentId = child.parentId;
    return parentId != null && widget.selectedIds.contains(parentId);
  }

  void _onParentTap(CategoryEntry parent, bool hasChildren, {int? rowIndex}) {
    // 一级分类本身就是可选中的：点击即选中；
    // 有二级分类时同时展开/收起，二级只是进一步的细选，可以不选。
    widget.onSelected(parent.id);
    if (!hasChildren) return;
    setState(() {
      _expandedId = _expandedId == parent.id ? null : parent.id;
      if (rowIndex != null) _rowPanelOwner[rowIndex] = parent.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final parents = widget.categories.where((item) => item.level == 1).toList();
    if (widget.layout == CategoryPickerLayout.grid) {
      return _buildGrid(parents);
    }
    return _buildList(parents);
  }

  Widget _buildList(List<CategoryEntry> parents) {
    return Column(
      children: [
        for (final parent in parents) ...[
          _ParentCategoryTile(
            key: ValueKey('cat-tile-${parent.id}'),
            category: parent,
            selected: _parentSelected(parent),
            expanded: _expandedId == parent.id,
            hasChildren: _childrenOf(parent.id).isNotEmpty,
            accent: widget.accent,
            onTap: () =>
                _onParentTap(parent, _childrenOf(parent.id).isNotEmpty),
          ),
          _ChildrenPanel(
            key: ValueKey('cat-panel-${parent.id}'),
            ownerId: parent.id,
            visible: _expandedId == parent.id,
            children: _childrenOf(parent.id),
            isSelected: _childSelected,
            accent: widget.accent,
            columns: _columns,
            indent: 16,
            onSelected: widget.onSelected,
          ),
        ],
      ],
    );
  }

  Widget _buildGrid(List<CategoryEntry> parents) {
    final rows = <Widget>[];
    for (var rowIndex = 0; rowIndex * _columns < parents.length; rowIndex++) {
      final start = rowIndex * _columns;
      final rowParents = parents.sublist(
        start,
        start + _columns > parents.length ? parents.length : start + _columns,
      );
      CategoryEntry? panelOwner;
      for (final parent in rowParents) {
        if (parent.id == _expandedId) panelOwner = parent;
      }
      if (panelOwner == null) {
        final remembered = _rowPanelOwner[rowIndex];
        for (final parent in rowParents) {
          if (parent.id == remembered) panelOwner = parent;
        }
      }
      rows.add(
        Row(
          key: ValueKey('cat-row-$rowIndex'),
          children: [
            for (var i = 0; i < _columns; i++)
              Expanded(
                child: i < rowParents.length
                    ? _ParentGridCell(
                        key: ValueKey('category-${rowParents[i].id}'),
                        category: rowParents[i],
                        selected: _parentSelected(rowParents[i]),
                        expanded: _expandedId == rowParents[i].id,
                        hasChildren: _childrenOf(rowParents[i].id).isNotEmpty,
                        accent: widget.accent,
                        onTap: () => _onParentTap(
                          rowParents[i],
                          _childrenOf(rowParents[i].id).isNotEmpty,
                          rowIndex: rowIndex,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
      rows.add(
        _ChildrenPanel(
          key: ValueKey('cat-panel-row-$rowIndex'),
          ownerId: panelOwner?.id,
          visible: panelOwner != null && _expandedId == panelOwner.id,
          children: panelOwner == null
              ? const <CategoryEntry>[]
              : _childrenOf(panelOwner.id),
          isSelected: _childSelected,
          accent: widget.accent,
          columns: _columns,
          onSelected: widget.onSelected,
        ),
      );
    }
    return Column(children: rows);
  }
}

class _ParentCategoryTile extends StatelessWidget {
  const _ParentCategoryTile({
    super.key,
    required this.category,
    required this.selected,
    required this.expanded,
    required this.hasChildren,
    required this.accent,
    required this.onTap,
  });

  final CategoryEntry category;
  final bool selected;
  final bool expanded;
  final bool hasChildren;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? accent : colors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radii.blockAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            CategoryIconView(
              iconKey: category.iconKey,
              color: color,
              size: 24,
              selected: selected,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? colors.ink : colors.muted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (hasChildren)
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: selected ? accent : colors.line,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ParentGridCell extends StatelessWidget {
  const _ParentGridCell({
    super.key,
    required this.category,
    required this.selected,
    required this.expanded,
    required this.hasChildren,
    required this.accent,
    required this.onTap,
  });

  final CategoryEntry category;
  final bool selected;
  final bool expanded;
  final bool hasChildren;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? accent : colors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radii.blockAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 30,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  CategoryIconView(
                    iconKey: category.iconKey,
                    color: color,
                    size: 26,
                    selected: selected,
                  ),
                  if (hasChildren)
                    Positioned(
                      right: -2,
                      bottom: 0,
                      child: AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? accent : colors.line,
                          ),
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                color: selected ? colors.ink : colors.muted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildrenPanel extends StatefulWidget {
  const _ChildrenPanel({
    super.key,
    required this.ownerId,
    required this.visible,
    required this.children,
    required this.isSelected,
    required this.accent,
    required this.columns,
    required this.onSelected,
    this.indent = 0,
  });

  final String? ownerId;
  final bool visible;
  final List<CategoryEntry> children;
  final bool Function(CategoryEntry child) isSelected;
  final Color accent;
  final int columns;
  final ValueChanged<String> onSelected;
  final double indent;

  @override
  State<_ChildrenPanel> createState() => _ChildrenPanelState();
}

class _ChildrenPanelState extends State<_ChildrenPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _expand = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.15, 1, curve: Curves.easeOut),
    reverseCurve: const Interval(0.4, 1, curve: Curves.easeIn),
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 200),
      vsync: this,
      value: widget.visible ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _ChildrenPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownerChanged = widget.ownerId != oldWidget.ownerId;
    if (widget.visible == oldWidget.visible && !ownerChanged) return;

    if (!widget.visible) {
      _controller.reverse();
      return;
    }
    if (ownerChanged) _controller.value = 0;
    _controller.forward();
    if (widget.children.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (widget.children.isEmpty) {
      return const SizedBox(width: double.infinity, height: 0);
    }
    return SizeTransition(
      sizeFactor: _expand,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _fade,
        child: Padding(
          padding: EdgeInsets.only(left: widget.indent, bottom: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: context.radii.cardAll,
            ),
            child: Column(children: _childRows()),
          ),
        ),
      ),
    );
  }

  List<Widget> _childRows() {
    final rows = <Widget>[];
    for (
      var start = 0;
      start < widget.children.length;
      start += widget.columns
    ) {
      rows.add(
        Row(
          children: [
            for (var i = start; i < start + widget.columns; i++)
              Expanded(
                child: i < widget.children.length
                    ? _CategoryCell(
                        key: ValueKey('category-${widget.children[i].id}'),
                        iconKey: widget.children[i].iconKey,
                        name: widget.children[i].name,
                        selected: widget.isSelected(widget.children[i]),
                        accent: widget.accent,
                        onTap: () =>
                            widget.onSelected(widget.children[i].id),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
    }
    return rows;
  }
}

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    super.key,
    required this.iconKey,
    required this.name,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String iconKey;
  final String name;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? accent : colors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radii.blockAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryIconView(
              iconKey: iconKey,
              size: 24,
              color: color,
              selected: selected,
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                color: selected ? colors.ink : colors.muted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
