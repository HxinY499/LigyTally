import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
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
/// 卡底是「添加子分类」。阴影用 [AppShadows.card]，与日卡/图表卡同高度浮起；
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

  @override
  void initState() {
    super.initState();
    _popoverController = FPopoverController(vsync: this);
  }

  @override
  void dispose() {
    _popoverController.dispose();
    super.dispose();
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
            '导入 ${preview.parentCount} 个一级、${preview.childCount} 个二级分类？'
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

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    return Scaffold(
      body: AppTopBar(
        title: '分类管理',
        actions: [
          IgnorePointer(
            ignoring: _busy,
            child: FPopoverMenu(
              control: FPopoverControl.managed(controller: _popoverController),
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
                onTap: null,
                enabled: !_busy,
              ),
            ),
          ),
          AppHeaderAction(
            icon: FLucideIcons.plus,
            tooltip: '新建一级分类',
            onTap: _busy ? null : () => _openEditor(),
          ),
        ],
        body: StreamBuilder<List<CategoryEntry>>(
          // activeOnly: false —— 管理页必须能看到停用的分类，
          // 否则停用等于「弄丢了」，用户再也找不回来重新启用。
          stream: database.watchCategories(_kind, activeOnly: false),
          builder: (context, snapshot) {
            final categories = snapshot.data;
            return CustomScrollView(
              slivers: [
                // 收支切换吸顶：滑到下面还能直接换一侧，不用滚回顶部。
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _KindBarDelegate(
                    kind: _kind,
                    onChanged: (value) => setState(() => _kind = value),
                  ),
                ),
                if (categories == null)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else
                  ..._buildContent(categories),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildContent(List<CategoryEntry> categories) {
    final parents = categories.where((item) => item.level == 1).toList();
    final childrenOf = <String, List<CategoryEntry>>{};
    for (final category in categories) {
      final parentId = category.parentId;
      if (parentId != null) {
        childrenOf.putIfAbsent(parentId, () => []).add(category);
      }
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        sliver: SliverList.list(
          children: [
            for (final parent in parents)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _CategoryCard(
                  parent: parent,
                  children: childrenOf[parent.id] ?? const [],
                  kind: _kind,
                  onEditParent: () => _openEditor(existing: parent),
                  onEditChild: (child) =>
                      _openEditor(existing: child, parent: parent),
                  onAddChild: () => _openEditor(parent: parent),
                ),
              ),
            _AddParentCard(
              kind: _kind,
              onTap: _busy ? null : () => _openEditor(),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '被账单用过的分类不能删除，可以停用——停用后记账时不再出现，'
                '历史账单照旧显示。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.inactive,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

/// 一级分类卡：卡头（分类本体）+ 二级分类网格 + 「添加子分类」行。
///
/// 结构刻意与首页日卡同构：白面 Material 提供水波画布、[AppShadows.card]
/// 挂在外层 DecoratedBox 上。白底若用 `Container(color:)` 会把水波盖住，
/// 点击变成毫无反馈（首页踩过这个坑，见 `_DayCard` 注释）。
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.parent,
    required this.children,
    required this.kind,
    required this.onEditParent,
    required this.onEditChild,
    required this.onAddChild,
  });

  final CategoryEntry parent;
  final List<CategoryEntry> children;
  final int kind;
  final VoidCallback onEditParent;
  final ValueChanged<CategoryEntry> onEditChild;
  final VoidCallback onAddChild;

  static const _radius = 18.0;
  static const _columns = 5;

  Color get _accent => kind == 0 ? AppColors.expense : AppColors.income;
  Color get _accentSoft =>
      kind == 0 ? AppColors.expenseSoft : AppColors.incomeSoft;

  @override
  Widget build(BuildContext context) {
    final active = parent.isActive;
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(_radius)),
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_radius),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: onEditParent,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(_radius),
              ),
              highlightColor: AppColors.pressed,
              splashColor: AppColors.ripple,
              hoverColor: AppColors.ripple,
              child: Padding
                  // 有子分类时下内距收窄，让卡头与下方网格成为一组。
                  (
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
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
                        color: active ? _accentSoft : AppColors.canvas,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        categoryIcon(parent.iconKey),
                        size: 21,
                        color: active ? _accent : AppColors.inactive,
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
                                        ? AppColors.ink
                                        : AppColors.inactive,
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
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 用铅笔而不是 chevron：这一行的动作是「编辑」，
                    // 不是「进入下一层」——chevron 会让人以为还有个子页面。
                    const Icon(
                      FLucideIcons.pencil,
                      size: 16,
                      color: Color(0xFFC2CBC6),
                    ),
                  ],
                ),
              ),
            ),
            if (children.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                child: Column(children: _childRows()),
              ),
            const Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: Color(0xFFF1F4F2),
            ),
            InkWell(
              onTap: onAddChild,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(_radius),
              ),
              highlightColor: AppColors.pressed,
              splashColor: AppColors.ripple,
              hoverColor: AppColors.ripple,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FLucideIcons.plus, size: 15, color: _accent),
                    const SizedBox(width: 6),
                    Text(
                      '添加子分类',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _accent,
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
  List<Widget> _childRows() {
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
                        accent: _accent,
                        onTap: () => onEditChild(children[i]),
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
    required this.onTap,
  });

  final CategoryEntry category;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = category.isActive;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      highlightColor: AppColors.pressed,
      splashColor: AppColors.ripple,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              categoryIcon(category.iconKey),
              size: 24,
              color: active ? accent : AppColors.inactive,
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
                color: active ? AppColors.ink : AppColors.inactive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「已停用」灰色胶囊。
class _MutedBadge extends StatelessWidget {
  const _MutedBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.1,
          color: AppColors.inactive,
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
    final accent = kind == 0 ? AppColors.expense : AppColors.income;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        highlightColor: AppColors.pressed,
        splashColor: AppColors.ripple,
        child: CustomPaint(
          painter: const _DashedBorderPainter(),
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
  const _DashedBorderPainter();

  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(18),
        ),
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
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}

/// 吸顶的支出/收入切换条。
///
/// 底色沿用页面 canvas、无描边，和页头连成一体（同首页的吸顶月份条）。
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
    return Material(
      color: AppColors.canvas,
      child: SizedBox(
        height: _height,
        child: Center(child: _KindSwitch(kind: kind, onChanged: onChanged)),
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

/// 支出/收入胶囊开关：灰底轨道 + 一块滑动的白色滑块。
///
/// 与记账页 `_KindSwitch` 同一形态（同尺寸、同缓动、同语义色），
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
    final selectedColor = kind == 0 ? AppColors.expense : AppColors.income;
    return SizedBox(
      height: _kHeight,
      width: _kSegmentWidth * 2 + _kPadding * 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.line.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(_kHeight / 2),
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
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(
                      (_kHeight - _kPadding * 2) / 2,
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
                  color: AppColors.expense,
                  selected: kind == 0,
                  onTap: () => onChanged(0),
                ),
                _KindSegment(
                  label: '收入分类',
                  color: AppColors.income,
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
              color: selected ? color : AppColors.inactive,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
