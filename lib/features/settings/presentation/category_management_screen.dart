import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/media/image_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/providers.dart';
import 'category_editor_sheet.dart';

/// 分类管理页。
///
/// ## 结构与其它页面的一致性
///
/// 视觉语言完全对齐首页与统计页：**一个一级分类 = 一张白色圆角大卡**
/// （同首页的「一天一张日卡」），卡头是分类本体、卡内是它的二级分类网格、
/// 卡底是「添加子分类」。阴影用 [AppColors.shadowCard]，与日卡/图表卡同高度浮起；
/// 顶部收支切换用记账页那枚滑块胶囊；二级分类格子沿用记账页分类选择器的
/// 「图标 + 下方小字」，让人在管理页看到的就是记账时会看到的样子。
///
/// ## 交互的三条改动
///
/// 1. **父级由入口决定**。旧版新建分类要在对话框里用下拉选「所属层级」，
///    而人是看着某个一级分类才想加子项的。现在每张卡底部直接有「添加子分类」，
///    页头的「+」只负责新建一级分类，下拉整个消失。
/// 2. **一行一个动作**。旧版每行塞了开关 + 删除按钮，误触率高、也没法改名。
///    现在点卡头/格子即进编辑面板，改名、换图标、停用、删除都在那里。
/// 3. **结果一定有反馈**。旧版切开关、新建成功都是静默的；现在统一走 toast，
///    被拦住的操作（如删不掉、停用会清空一侧）也会说清原因和替代做法。
/// 4. **顺序在管理页改**。一级卡头右侧手柄拖整张卡；二级格子长按拖，
///    单击仍进编辑。记账页选择器走同一条 `watchCategories`，会自己跟上。
class CategoryManagementScreen extends ConsumerStatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends ConsumerState<CategoryManagementScreen>
    with SingleTickerProviderStateMixin {
  int _kind = 0;
  bool _busy = false;
  late final FPopoverController _popoverController;
  late final AppDatabase _database;
  late final ImageStorage _storage;

  /// 拖拽后、库的 Stream 还没推回来之前，用这份 id 顺序顶住画面。
  ///
  /// `SliverReorderableList` 的 `onReorderItem` 要求调用方立刻改列表，
  /// 否则下一帧仍是 Stream 里的旧顺序，卡片会弹回原位。id 集合对不上
  /// （换了收支侧、增删了分类）就丢弃，回到 Stream 的顺序。
  ///
  /// 它会盖住 Stream 推来的顺序，所以写库失败时必须由 [_persistOrder]
  /// 主动清掉——否则画面会一直停在那次没写成的排法上。
  List<String>? _parentOrder;
  final Map<String, List<String>> _childOrder = {};

  @override
  void initState() {
    super.initState();
    _popoverController = FPopoverController(vsync: this);
    // 在 initState 里取：dispose 时要用它们回收图标文件，那时读不了 ref。
    _database = ref.read(databaseProvider);
    _storage = ref.read(imageStorageProvider);
  }

  @override
  void dispose() {
    _popoverController.dispose();
    _pruneIconFiles();
    super.dispose();
  }

  /// 离开分类管理页时，清掉所有已经没人引用的自定义图标文件。
  ///
  /// 为什么用「扫目录对账」而不是在每条路径上顺手删文件：需要删的场景有
  /// 上传后又点了取消、连着换了两张只留后一张、把图片换回内置图标、
  /// 删掉整个分类（还会连带子分类）。这些出口各不相同，逐条去记迟早漏一处，
  /// 而漏掉的文件会一直躺在之后每一个备份包里。
  ///
  /// 为什么是本页的 dispose 而不是编辑面板的：面板可以连开好几次
  /// （编完一个接着编下一个），在面板的 dispose 里扫，有机会把「上一个面板
  /// 正在关、下一个面板刚上传的那张图」当成孤儿删掉——那张图此刻确实还没
  /// 写进库里。等整页退出时库已经是最终状态，不存在这种中间态。
  void _pruneIconFiles() {
    // 不 await：页面已经在拆了。失败最坏是留一张几十 KB 的孤儿图，
    // 下次进出这个页面会再扫一遍。
    _database
        .exportCategories()
        .then(
          (rows) => _storage.pruneCategoryIcons(
            customIconIdsOf(rows.map((row) => row.iconKey)),
          ),
        )
        .ignore();
  }

  void _showMessage(
    String message, {
    AppToastLevel level = AppToastLevel.info,
  }) {
    showAppToast(context, message: message, level: level);
  }

  Future<void> _exportConfig() async {
    setState(() => _busy = true);
    try {
      await ref.read(categoryConfigServiceProvider).exportAndShare();
    } catch (error) {
      if (mounted) _showMessage('导出分类配置失败：$error', level: AppToastLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importConfig() async {
    final service = ref.read(categoryConfigServiceProvider);
    final path = await service.pickConfigFile();
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final preview = await service.inspect(path);
      if (!mounted) return;
      final confirmed = await showAppConfirmDialog(
        context,
        message:
            '导入 ${preview.parentCount} 个一级、${preview.childCount} 个二级分类'
            '${preview.iconImageCount > 0 ? '（含 ${preview.iconImageCount} 张自定义图标）' : ''}？'
            '当前分类将被替换，历史账单用到的旧分类会保留并停用',
        confirmLabel: '导入并替换',
      );
      if (confirmed) {
        await service.importAndReplace(path);
        if (mounted) _showMessage('分类配置已导入', level: AppToastLevel.success);
      }
    } catch (error) {
      if (mounted) _showMessage('导入分类配置失败：$error', level: AppToastLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 打开新建/编辑面板，并把面板返回的文案吐成 toast。
  ///
  /// 写库在面板内部完成（重名校验要查库、失败要留在面板里改），
  /// 这里只负责反馈——列表本身是 StreamBuilder，会自己刷新。
  Future<void> _openEditor({
    CategoryEntry? existing,
    CategoryEntry? parent,
  }) async {
    final result = await showCategoryEditorSheet(
      context,
      kind: _kind,
      existing: existing,
      parent: parent,
    );
    if (result == null || !mounted) return;
    _showMessage(result.message, level: result.level);
  }

  /// 把 [ids] 写成 `0..n-1`。
  ///
  /// 本地顺序是乐观更新，写失败就得撤掉，让 Stream 里的真实顺序重新露出来。
  /// [parentId] 为空表示这次拖的是一级卡片。
  Future<void> _persistOrder(List<String> ids, {String? parentId}) async {
    try {
      await _database.reorderCategories(ids);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (parentId == null) {
          _parentOrder = null;
        } else {
          _childOrder.remove(parentId);
        }
      });
      _showMessage('排序失败：$error', level: AppToastLevel.error);
    }
  }

  void _onReorderParents(
    List<CategoryEntry> parents,
    int oldIndex,
    int newIndex,
  ) {
    final ids = _movedIds(
      parents.map((item) => item.id).toList(),
      oldIndex,
      newIndex,
    );
    if (ids == null) return;
    HapticFeedback.selectionClick();
    setState(() => _parentOrder = ids);
    _persistOrder(ids);
  }

  void _onReorderChildren(
    String parentId,
    List<CategoryEntry> children,
    String fromId,
    String toId,
  ) {
    final ids = children.map((item) => item.id).toList();
    final moved = _movedIds(ids, ids.indexOf(fromId), ids.indexOf(toId));
    if (moved == null) return;
    HapticFeedback.selectionClick();
    setState(() => _childOrder[parentId] = moved);
    _persistOrder(moved, parentId: parentId);
  }

  List<CategoryEntry> _orderedParents(List<CategoryEntry> categories) {
    final parents = categories.where((item) => item.level == 1).toList();
    return _applyOrder(parents, _parentOrder);
  }

  List<CategoryEntry> _orderedChildren(
    String parentId,
    List<CategoryEntry> children,
  ) {
    return _applyOrder(children, _childOrder[parentId]);
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    return Scaffold(
      // 分类流套在页头外面：页头是 pinned sliver，得和内容同处一个
      // CustomScrollView 才能让内容滚到它背后去。
      //
      // activeOnly: false —— 管理页必须能看到停用的分类，
      // 否则停用等于「弄丢了」，用户再也找不回来重新启用。
      body: StreamBuilder<List<CategoryEntry>>(
        stream: database.watchCategories(_kind, activeOnly: false),
        builder: (context, snapshot) {
          final categories = snapshot.data;
          return AppTopBar(
            title: '分类管理',
            actions: [
              // 点击必须由这里主动 toggle：forui 的 FPopoverMenu 只把 child 当锚点，
              // 不像 Material 的 PopupMenuButton 那样帮你把 child 包成按钮
              // （见 FPopover.defaultBuilder，它原样返回 child）。
              // 之前这里传的是 `onTap: null` + 外层 IgnorePointer，
              // 结果整个菜单永远打不开——图标是亮的，但点了没有任何反应。
              FPopoverMenu(
                control: FPopoverControl.managed(
                  controller: _popoverController,
                ),
                menu: [
                  FItemGroup(
                    children: [
                      FItem(
                        title: const Text('导出分类配置'),
                        onPress: _busy
                            ? null
                            : () {
                                _popoverController.hide();
                                _exportConfig();
                              },
                      ),
                      FItem(
                        title: const Text('导入并替换配置'),
                        onPress: _busy
                            ? null
                            : () {
                                _popoverController.hide();
                                _importConfig();
                              },
                      ),
                    ],
                  ),
                ],
                child: AppHeaderAction(
                  icon: FLucideIcons.arrowLeftRight,
                  tooltip: '导出 / 导入分类配置',
                  onTap: _busy ? null : _popoverController.toggle,
                ),
              ),
              AppHeaderAction(
                icon: FLucideIcons.plus,
                tooltip: '新建一级分类',
                onTap: _busy ? null : () => _openEditor(),
              ),
            ],
            slivers: [
              // 收支切换吸顶：滑到下面还能直接换一侧，不用滚回顶部。
              SliverPersistentHeader(
                pinned: true,
                delegate: _KindBarDelegate(
                  kind: _kind,
                  onChanged: (value) => setState(() {
                    _kind = value;
                    _parentOrder = null;
                    _childOrder.clear();
                  }),
                ),
              ),
              if (categories == null)
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
              else
                ..._buildContent(categories),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildContent(List<CategoryEntry> categories) {
    final parents = _orderedParents(categories);
    final childrenOf = <String, List<CategoryEntry>>{};
    for (final category in categories) {
      final parentId = category.parentId;
      if (parentId != null) {
        childrenOf.putIfAbsent(parentId, () => []).add(category);
      }
    }
    for (final parent in parents) {
      final children = childrenOf[parent.id];
      if (children != null) {
        childrenOf[parent.id] = _orderedChildren(parent.id, children);
      }
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        sliver: SliverReorderableList(
          itemCount: parents.length,
          onReorderItem: (oldIndex, newIndex) =>
              _onReorderParents(parents, oldIndex, newIndex),
          itemBuilder: (context, index) {
            final parent = parents[index];
            return Padding(
              key: ValueKey(parent.id),
              padding: const EdgeInsets.only(bottom: 14),
              child: _CategoryCard(
                index: index,
                reorderable: parents.length > 1,
                parent: parent,
                children: childrenOf[parent.id] ?? const [],
                kind: _kind,
                onEditParent: () => _openEditor(existing: parent),
                onEditChild: (child) =>
                    _openEditor(existing: child, parent: parent),
                onAddChild: () => _openEditor(parent: parent),
                onReorderChildren: (fromId, toId) => _onReorderChildren(
                  parent.id,
                  childrenOf[parent.id] ?? const [],
                  fromId,
                  toId,
                ),
              ),
            );
          },
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        sliver: SliverToBoxAdapter(
          child: Column(
            children: [
              _AddParentCard(
                kind: _kind,
                onTap: _busy ? null : () => _openEditor(),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '被账单用过的分类不能删除，可以停用——停用后记账时不再出现，'
                  '历史账单照旧显示。长按子分类可调整顺序。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: context.colors.inactive,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

/// 把 [from] 处的 id 挪到 [to]。非法下标或没动位置时返回 null，
/// 调用方据此跳过 setState，避免空拖也刷一遍页面。
List<String>? _movedIds(List<String> ids, int from, int to) {
  if (from == to ||
      from < 0 ||
      to < 0 ||
      from >= ids.length ||
      to >= ids.length) {
    return null;
  }
  final next = [...ids];
  final id = next.removeAt(from);
  next.insert(to, id);
  return next;
}

/// [order] 恰好是 [items] 的一个排列时按它排，否则退回原列表。
///
/// 排列对不上 = 增删了分类或切了收支侧，本地覆盖已经失效。
List<CategoryEntry> _applyOrder(
  List<CategoryEntry> items,
  List<String>? order,
) {
  if (order == null || order.length != items.length) return items;
  final byId = {for (final item in items) item.id: item};
  if (order.any((id) => !byId.containsKey(id))) return items;
  return [for (final id in order) byId[id]!];
}

/// 一级分类卡：卡头（分类本体）+ 二级分类网格 + 「添加子分类」行。
///
/// 结构刻意与首页日卡同构：白面 Material 提供水波画布、[AppColors.shadowCard]
/// 挂在外层 DecoratedBox 上。白底若用 `Container(color:)` 会把水波盖住，
/// 点击变成毫无反馈（首页踩过这个坑，见 `_DayCard` 注释）。
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.index,
    required this.reorderable,
    required this.parent,
    required this.children,
    required this.kind,
    required this.onEditParent,
    required this.onEditChild,
    required this.onAddChild,
    required this.onReorderChildren,
  });

  /// 在 [SliverReorderableList] 里的位置，手柄用它启动拖拽。
  final int index;
  final bool reorderable;
  final CategoryEntry parent;
  final List<CategoryEntry> children;
  final int kind;
  final VoidCallback onEditParent;
  final ValueChanged<CategoryEntry> onEditChild;
  final VoidCallback onAddChild;
  final void Function(String fromId, String toId) onReorderChildren;

  static const _columns = 5;

  Color _accent(AppColors colors) => kind == 0 ? colors.expense : colors.income;
  Color _accentSoft(AppColors colors) =>
      kind == 0 ? colors.expenseSoft : colors.incomeSoft;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final active = parent.isActive;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radii.cardAll,
        boxShadow: colors.shadowCard,
      ),
      child: Material(
        color: colors.surface,
        borderRadius: radii.cardAll,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onEditParent,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(radii.card),
                      topRight: reorderable
                          ? Radius.zero
                          : Radius.circular(radii.card),
                    ),
                    highlightColor: colors.pressed,
                    splashColor: colors.ripple,
                    hoverColor: colors.ripple,
                    child: Padding(
                      // 有子分类时下内距收窄，让卡头与下方网格成为一组。
                      padding: EdgeInsets.fromLTRB(
                        16,
                        14,
                        reorderable ? 8 : 16,
                        children.isEmpty ? 14 : 10,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              // 停用的分类整体退成灰阶：一眼能从一列卡片里
                              // 认出「这个现在不生效」，不用去读文字徽章。
                              color: active
                                  ? _accentSoft(colors)
                                  : colors.canvasBase,
                              shape: BoxShape.circle,
                            ),
                            child: CategoryIconView(
                              iconKey: parent.iconKey,
                              size: 21,
                              imageSize: 40,
                              color: active ? _accent(colors) : colors.inactive,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        parent.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700,
                                          color: active
                                              ? colors.ink
                                              : colors.inactive,
                                        ),
                                      ),
                                    ),
                                    if (!active) ...[
                                      const SizedBox(width: 8),
                                      const _MutedBadge('已停用'),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  children.isEmpty
                                      ? '暂无子分类'
                                      : '${children.length} 个子分类',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 用铅笔而不是 chevron：这一行的动作是「编辑」，
                          // 不是「进入下一层」——chevron 会让人以为还有个子页面。
                          Icon(
                            FLucideIcons.pencil,
                            size: 16,
                            color: colors.faint,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 手柄放在 InkWell 外面：按住它只启动拖拽，不会误开编辑面板。
                if (reorderable)
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        4,
                        14,
                        12,
                        children.isEmpty ? 14 : 10,
                      ),
                      child: Icon(
                        FLucideIcons.gripVertical,
                        size: 20,
                        color: colors.faint,
                      ),
                    ),
                  ),
              ],
            ),
            if (children.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                child: Column(children: _childRows(colors)),
              ),
            Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: colors.fill,
            ),
            InkWell(
              onTap: onAddChild,
              borderRadius: radii.cardBottom,
              highlightColor: colors.pressed,
              splashColor: colors.ripple,
              hoverColor: colors.ripple,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FLucideIcons.plus, size: 15, color: _accent(colors)),
                    const SizedBox(width: 6),
                    Text(
                      '添加子分类',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _accent(colors),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 二级分类按 5 列铺开，最后一行补空位撑齐——用 Row 而不是 GridView：
  /// 卡片高度必须由内容决定，GridView 在无界高度里没法用。
  List<Widget> _childRows(AppColors colors) {
    final siblingIds = {for (final child in children) child.id};
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += _columns) {
      rows.add(
        Row(
          children: [
            for (var i = start; i < start + _columns; i++)
              Expanded(
                child: i < children.length
                    ? _ChildCell(
                        category: children[i],
                        accent: _accent(colors),
                        siblingIds: siblingIds,
                        onTap: () => onEditChild(children[i]),
                        onMove: children.length > 1 ? onReorderChildren : null,
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

/// 二级分类格子：图标 + 下方小字，与记账页分类选择器同一形态。
///
/// 点它进编辑面板。停用态整体降到 inactive 灰，并在文字前不加任何标记——
/// 二级分类的格子只有 60 多 px 宽，塞徽章会挤掉名字，灰度已经足够表达。
class _ChildCell extends StatelessWidget {
  const _ChildCell({
    required this.category,
    required this.accent,
    required this.siblingIds,
    required this.onTap,
    this.onMove,
  });

  final CategoryEntry category;
  final Color accent;

  /// 同一张卡里的所有二级分类 id。只接同卡的格子——每张卡的
  /// [DragTarget] 收的都是 `String`，不认这一层就会接下别的一级卡拖来的
  /// 格子，然后因为跨父级重排被静默丢掉：高亮亮了，松手却什么也没发生。
  final Set<String> siblingIds;
  final VoidCallback onTap;

  /// 非空时格子可长按拖到另一个格子上。只有一张时没有可交换的位置。
  final void Function(String fromId, String toId)? onMove;

  @override
  Widget build(BuildContext context) {
    final tile = _ChildTile(category: category, accent: accent, onTap: onTap);
    final onMove = this.onMove;
    if (onMove == null) return tile;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data != category.id && siblingIds.contains(details.data),
      onAcceptWithDetails: (details) => onMove(details.data, category.id),
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        return LongPressDraggable<String>(
          data: category.id,
          // 不缩短 delay：长按一到时间就直接夺走手势（见
          // _DelayedPointerState._delayPassed，不需要移动），调短会让「按得
          // 稍久一点的点击」变成原地拖一下，编辑面板反而打不开。
          onDragStarted: () => HapticFeedback.mediumImpact(),
          feedback: _ChildDragFeedback(category: category, accent: accent),
          childWhenDragging: Opacity(opacity: 0.35, child: tile),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: hovering
                  ? accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: context.radii.blockAll,
            ),
            child: tile,
          ),
        );
      },
    );
  }
}

/// 拖起来跟在手指底下的那一格。必须自己定宽高——Overlay 里没有父约束，
/// 不写死会按内容缩成一条，看起来不像格子。
class _ChildDragFeedback extends StatelessWidget {
  const _ChildDragFeedback({required this.category, required this.accent});

  final CategoryEntry category;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      elevation: 8,
      color: colors.surface,
      borderRadius: context.radii.blockAll,
      child: SizedBox(
        width: 72,
        height: 64,
        child: _ChildTile(category: category, accent: accent),
      ),
    );
  }
}

/// 二级分类格子：图标 + 下方小字，与记账页分类选择器同一形态。
///
/// 点它进编辑面板。停用态整体降到 inactive 灰，并在文字前不加任何标记——
/// 二级分类的格子只有 60 多 px 宽，塞徽章会挤掉名字，灰度已经足够表达。
class _ChildTile extends StatelessWidget {
  const _ChildTile({required this.category, required this.accent, this.onTap});

  final CategoryEntry category;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = category.isActive;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CategoryIconView(
            iconKey: category.iconKey,
            size: 24,
            color: active ? accent : colors.inactive,
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
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? colors.ink : colors.inactive,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radii.blockAll,
      highlightColor: colors.pressed,
      splashColor: colors.ripple,
      child: content,
    );
  }
}

/// 「已停用」灰色胶囊。
class _MutedBadge extends StatelessWidget {
  const _MutedBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.canvasBase,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.1,
          color: colors.inactive,
        ),
      ),
    );
  }
}

/// 列表末尾的「新建一级分类」卡：虚线描边 + 无阴影。
///
/// 刻意做成「未填充的空位」而不是实体卡：它不是数据，是个动作。
/// 页头的「+」也能做同一件事，但列表滚到底时那个图标已经在屏幕外了，
/// 这张卡把入口放在用户视线的终点。
class _AddParentCard extends StatelessWidget {
  const _AddParentCard({required this.kind, required this.onTap});

  final int kind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = kind == 0 ? colors.expense : colors.income;
    return Material(
      color: Colors.transparent,
      borderRadius: context.radii.cardAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radii.cardAll,
        highlightColor: colors.pressed,
        splashColor: colors.ripple,
        child: CustomPaint(
          painter: _DashedBorderPainter(colors.line, context.radii.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(FLucideIcons.plus, size: 17, color: accent),
                const SizedBox(width: 7),
                Text(
                  kind == 0 ? '新建支出一级分类' : '新建收入一级分类',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 虚线圆角描边。
///
/// Flutter 的 [Border] 只有实线，虚线得自己按路径切段画。
/// 用 [Path.computeMetrics] 沿圆角矩形均匀取段，四个角上的虚线才不会
/// 因为「按边分别画」而在拐角处断得难看。
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter(this.color, this.radius);

  final Color color;

  /// 虚线框圆角。要和外层 [Material] 的圆角对上，否则四角会露出来一截直线。
  final double radius;

  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + _dash;
        canvas.drawPath(
          metric.extractPath(
            distance,
            end > metric.length ? metric.length : end,
          ),
          paint,
        );
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 吸顶的支出/收入切换条。
///
/// 与首页月份条同一套 [AppChromeGlass]：自身开始滚出时才毛玻璃，静止时不透明。
class _KindBarDelegate extends SliverPersistentHeaderDelegate {
  _KindBarDelegate({required this.kind, required this.onChanged});

  final int kind;
  final ValueChanged<int> onChanged;

  static const double _height = 52;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return AppChromeGlass(
      translucency: (shrinkOffset / _height).clamp(0.0, 1.0),
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          height: _height,
          child: Center(
            child: _KindSwitch(kind: kind, onChanged: onChanged),
          ),
        ),
      ),
    );
  }

  @override
  double get maxExtent => _height;

  @override
  double get minExtent => _height;

  @override
  bool shouldRebuild(covariant _KindBarDelegate oldDelegate) =>
      oldDelegate.kind != kind;
}

/// 支出/收入开关：灰底轨道 + 一块滑动的白色滑块。
///
/// 与记账页 `_KindSwitch` 同一形态（同尺寸、同缓动、同语义色、同圆角档），
/// 这样「切换收支」在全应用是同一个动作，肌肉记忆能迁移。
/// 旧版这里用的是两颗 44px 高的实心分段按钮，视觉重量压过了下面的分类卡片。
class _KindSwitch extends StatelessWidget {
  const _KindSwitch({required this.kind, required this.onChanged});

  final int kind;
  final ValueChanged<int> onChanged;

  static const double _kHeight = 34;
  static const double _kSegmentWidth = 78;
  static const double _kPadding = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedColor = kind == 0 ? colors.expense : colors.income;
    final trackRadius = context.radii.block;
    return SizedBox(
      height: _kHeight,
      width: _kSegmentWidth * 2 + _kPadding * 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.line.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(trackRadius),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: kind == 0
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(_kPadding),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  width: _kSegmentWidth,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(
                      (trackRadius - _kPadding).clamp(0.0, trackRadius),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: selectedColor.withValues(alpha: 0.16),
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _KindSegment(
                  label: '支出分类',
                  color: colors.expense,
                  selected: kind == 0,
                  onTap: () => onChanged(0),
                ),
                _KindSegment(
                  label: '收入分类',
                  color: colors.income,
                  selected: kind == 1,
                  onTap: () => onChanged(1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KindSegment extends StatelessWidget {
  const _KindSegment({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            style: TextStyle(
              fontSize: 13,
              height: 1.1,
              letterSpacing: 0.2,
              color: selected ? color : colors.inactive,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
