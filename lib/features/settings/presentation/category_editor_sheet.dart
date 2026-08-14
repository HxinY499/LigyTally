import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/media/image_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/providers.dart';

/// 分类新建 / 编辑的底部面板。
///
/// ## 为什么是底部面板而不是对话框
///
/// 旧版新建分类是 [AlertDialog] + 一个「所属层级」下拉：用户得先在下拉里
/// 从十几个一级分类中找到目标，才能建二级分类——而他大多数时候是**看着某个
/// 一级分类**才想给它加个子项的。现在改成：一级分类卡片底部直接点「添加子分类」，
/// 父级由入口决定并显示在标题下方，下拉整个消失。
///
/// 面板还顺手补上了旧版做不到的两件事：**选图标**（旧版新建的分类一律是
/// 「其他」那个省略号图标）和**改名**（旧版只能删了重建）。
///
/// ## 返回值
///
/// 成功写库后 pop 出一条给调用方 toast 的文案；用户取消则返回 null。
/// 数据库写入放在面板内部，是因为「重名校验」需要查库，
/// 而校验失败要留在面板里让用户改，不能先关了再报错。
Future<CategorySheetResult?> showCategoryEditorSheet(
  BuildContext context, {
  required int kind,

  /// 要编辑的分类。为 null 表示新建。
  CategoryEntry? existing,

  /// 新建二级分类时的父级。为 null 表示建一级分类。
  CategoryEntry? parent,
}) {
  return showModalBottomSheet<CategorySheetResult>(
    context: context,
    backgroundColor: Colors.transparent,
    // 键盘弹出时面板要整体上移，否则输入框被系统键盘盖住。
    isScrollControlled: true,
    builder: (_) =>
        _CategoryEditorSheet(kind: kind, existing: existing, parent: parent),
  );
}

/// 面板操作的结果：一条提示文案 + 语气。
typedef CategorySheetResult = ({String message, AppToastLevel level});

class _CategoryEditorSheet extends ConsumerStatefulWidget {
  const _CategoryEditorSheet({
    required this.kind,
    required this.existing,
    required this.parent,
  });

  final int kind;
  final CategoryEntry? existing;
  final CategoryEntry? parent;

  @override
  ConsumerState<_CategoryEditorSheet> createState() =>
      _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<_CategoryEditorSheet> {
  static const _maxNameLength = 12;

  late final TextEditingController _nameController;
  late final ImageStorage _storage;
  late String _iconKey;
  late bool _active;
  bool _busy = false;

  final _picker = ImagePicker();

  /// 名称输入的即时错误提示（空 / 超长 / 重名）。
  String? _error;

  bool get _isEditing => widget.existing != null;

  /// 编辑时父级取自被编辑对象，新建时取自入口。
  String? get _parentId => widget.existing?.parentId ?? widget.parent?.id;

  bool get _isChild => _parentId != null;

  /// 收支语义色：与记账页金额卡、键盘保持一致，让人一眼知道在编哪一侧。
  Color _accent(AppColors colors) =>
      widget.kind == 0 ? colors.expense : colors.income;

  Color _accentSoft(AppColors colors) =>
      widget.kind == 0 ? colors.expenseSoft : colors.incomeSoft;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    // 新建时给个中性默认图标，用户不选也不会拿到空图标。
    _iconKey = existing?.iconKey ?? 'other';
    _active = existing?.isActive ?? true;
    _storage = ref.read(imageStorageProvider);
    _nameController.addListener(() {
      // 名称一改就清掉上一次的报错，不让红字赖在屏幕上。
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 选一张图片作为分类图标。
  ///
  /// 图片当场落盘（而不是攒到点保存时再写）：预览圆片和图标网格都要立刻
  /// 显示它，而这两处都走 [CategoryIconView] 读文件路径。用户最后没采用的
  /// 图由分类管理页离开时的那次回收兜住（见 `_pruneIconFiles`）。
  Future<void> _pickIconImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 100);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final id = const Uuid().v4();
      await _storage.storeCategoryIcon(source: picked, iconId: id);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() {
        _iconKey = customCategoryIconKey(id);
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(
        context,
        message: '图片处理失败：$error',
        level: AppToastLevel.error,
      );
    }
  }

  /// 点「上传图片」格子：先问来源（拍照 / 相册），与记账页加图片同一套问法。
  Future<void> _chooseIconImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(FLucideIcons.camera),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(FLucideIcons.images),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _pickIconImage(source);
  }

  String get _title {
    if (_isEditing) return '编辑分类';
    return _isChild ? '新建子分类' : '新建一级分类';
  }

  String? get _subtitle {
    final parentName = widget.parent?.name;
    if (parentName != null) return '归属「$parentName」';
    if (_isChild) return '二级分类';
    return widget.kind == 0 ? '支出的一级分类' : '收入的一级分类';
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入分类名称');
      return;
    }
    final database = ref.read(databaseProvider);
    setState(() => _busy = true);
    final duplicated = await database.categoryNameExists(
      kind: widget.kind,
      name: name,
      parentId: _parentId,
      excludeId: widget.existing?.id,
    );
    if (!mounted) return;
    if (duplicated) {
      setState(() {
        _busy = false;
        _error = _isChild ? '同一分类下已有「$name」' : '已经有叫「$name」的分类了';
      });
      return;
    }

    final existing = widget.existing;
    if (existing == null) {
      await database.addCategory(
        id: const Uuid().v4(),
        kind: widget.kind,
        name: name,
        iconKey: _iconKey,
        parentId: _parentId,
      );
    } else {
      await database.updateCategory(
        id: existing.id,
        name: name,
        iconKey: _iconKey,
      );
      if (_active != existing.isActive) {
        final result = await database.setCategoryActive(existing.id, _active);
        if (result == CategoryToggleResult.lastRoot) {
          if (!mounted) return;
          // 名称/图标已经存下了，只有停用被拦住，说清楚是哪一半没生效。
          Navigator.pop(context, (
            message: '已保存，但收入和支出至少各要留一个可用的一级分类，未停用',
            level: AppToastLevel.error,
          ));
          return;
        }
      }
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, (
      message: existing == null ? '「$name」已创建' : '「$name」已保存',
      level: AppToastLevel.success,
    ));
  }

  Future<void> _delete() async {
    final category = widget.existing!;
    final confirmed = await showAppConfirmDialog(
      context,
      message: category.level == 1
          ? '确定删除「${category.name}」及其全部子分类吗？'
          : '确定删除「${category.name}」吗？',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final result = await ref.read(databaseProvider).deleteCategory(category.id);
    if (!mounted) return;
    switch (result) {
      case CategoryDeleteResult.deleted:
        Navigator.pop(context, (
          message: '「${category.name}」已删除',
          level: AppToastLevel.success,
        ));
      case CategoryDeleteResult.inUse:
        // 留在面板里：紧挨着的「停用」开关就是用户此刻该走的那条路。
        setState(() => _busy = false);
        showAppToast(
          context,
          message: '这个分类已被历史账单使用，不能删除，可以改成停用',
          level: AppToastLevel.error,
        );
      case CategoryDeleteResult.lastRoot:
        setState(() => _busy = false);
        showAppToast(
          context,
          message: '收入和支出至少各要保留一个可用的一级分类',
          level: AppToastLevel.error,
        );
    }
  }

  /// 面板里除图标区之外的固定高度合计（抓手 + 标题 + 副标题 + 名称行 + 按钮行）。
  ///
  /// 8 抓手上距 + 4 抓手 + 12 + 20 标题 + 18 副标题 + 18 +
  /// 70 名称行（46 预览圆片 + 20 恒定报错位 + 4） + 16 + 68 按钮行（12+48+8）。
  static const _chromeHeight = 234.0;

  /// 编辑态额外多出的「在记账时可选」开关行 + 分隔线。
  static const _activeRowHeight = 57.0;

  /// 面板最多占屏幕的比例。
  ///
  /// 留 15% 给上方背景：底部面板得让人看见「后面还有页面」，
  /// 铺满整屏就变成一个全屏页了，下滑关闭的手势也失去了落点。
  static const _maxHeightRatio = 0.85;

  /// 图标区的理想下限（约四行格子）。空间不够时会被牺牲，见 [_pickerHeight]。
  static const _preferredMinPickerHeight = 208.0;

  /// 图标区的绝对下限：一行格子。再小就不是「选择器」了。
  static const _hardMinPickerHeight = 56.0;

  /// 图标区高度：按当前可用空间算，而不是写死。
  ///
  /// 原来固定 208（约三行半），120 个图标要翻七八屏。改成吃满可用空间后，
  /// 常见手机上能一次看到七八行。
  ///
  /// 三条约束，**优先级从高到低**：
  /// 1. **不能溢出**。上限恒为「可用高度 − 面板其余部分」。这条压倒一切：
  ///    小屏 + 键盘弹起（名称框 autofocus，一打开就是这个状态）时可用空间
  ///    可能只剩三百多，硬守 208 的下限会让 Column 溢出 —— 底部的「创建」
  ///    按钮被挤出屏幕，用户根本没法提交。
  /// 2. 上限也不超过「全部图标的总高度」——再高只是在底下拖出一片空白。
  /// 3. 空间宽裕时至少给 [_preferredMinPickerHeight]，别压成一条缝。
  double _pickerHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final available =
        media.size.height - media.viewInsets.bottom - media.padding.top;
    final chrome = _chromeHeight + (_isEditing ? _activeRowHeight : 0);
    // 硬上限：面板整体（chrome + 图标区）不得超过可用高度。
    // 这里不打 _maxHeightRatio 的折扣——空间紧张时「留白给背景」是奢侈品，
    // 「按钮还在屏幕里」才是必需品。
    final ceiling = available - chrome;
    if (ceiling <= _hardMinPickerHeight) return _hardMinPickerHeight;
    final ideal = (available * _maxHeightRatio - chrome).clamp(
      _preferredMinPickerHeight,
      _IconPickerState.contentHeight,
    );
    return ideal.clamp(_hardMinPickerHeight, ceiling);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // viewInsets：键盘高度。加在底部让整块面板浮在键盘之上。
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Material(
        color: colors.surface,
        borderRadius: context.radii.sheetTop,
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
              const SizedBox(height: 12),
              Text(
                _title,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
              if (_subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  _subtitle!,
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
              ],
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: _NameRow(
                  controller: _nameController,
                  iconKey: _iconKey,
                  accent: _accent(colors),
                  accentSoft: _accentSoft(colors),
                  maxLength: _maxNameLength,
                  error: _error,
                  onSubmitted: _busy ? null : _submit,
                ),
              ),
              const SizedBox(height: 16),
              // 图标区吃满可用空间（见 _pickerHeight）：面板整体高度仍然可控，
              // 但能一次看到尽可能多的图标，不用为了找一个图标翻七八屏。
              _IconPicker(
                selected: _iconKey,
                accent: _accent(colors),
                accentSoft: _accentSoft(colors),
                onSelected: (key) {
                  HapticFeedback.selectionClick();
                  setState(() => _iconKey = key);
                },
                onUpload: _busy ? null : _chooseIconImageSource,
                revealSelected: _isEditing,
                height: _pickerHeight(context),
              ),
              if (_isEditing) ...[
                const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 20,
                  endIndent: 20,
                ),
                _ActiveRow(
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    if (_isEditing) ...[
                      _DeleteButton(onTap: _busy ? null : _delete),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: _ConfirmButton(
                        label: _isEditing ? '保存' : '创建',
                        accent: _accent(colors),
                        busy: _busy,
                        onTap: _busy ? null : _submit,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 名称输入行：左侧是「当前图标 + 收支色」的实时预览，右侧是输入框。
///
/// 预览圆片不只是装饰——它让「选图标」这件事有了落点：用户点下方网格时，
/// 能立刻在这里看到分类将来在记账页长什么样。
class _NameRow extends StatelessWidget {
  const _NameRow({
    required this.controller,
    required this.iconKey,
    required this.accent,
    required this.accentSoft,
    required this.maxLength,
    required this.error,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String iconKey;
  final Color accent;
  final Color accentSoft;
  final int maxLength;
  final String? error;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = context.radii.blockAll;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: color),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accentSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              // 上传的图片铺满整个 46 圆片，内置图标仍是 24 的字形。
              // 图片在 46 的圆里只画 24，中间那圈底色会让它看起来像
              // 「贴了张小照片」，而分类图标本身就是个圆——满格才对。
              child: CategoryIconView(
                iconKey: iconKey,
                size: 24,
                imageSize: 46,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLength: maxLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmitted?.call(),
                style: TextStyle(fontSize: 15, color: colors.ink),
                cursorColor: accent,
                decoration: InputDecoration(
                  hintText: '分类名称',
                  hintStyle: TextStyle(fontSize: 15, color: colors.inactive),
                  filled: true,
                  fillColor: colors.canvas,
                  // 计数器占一整行高度却只说「3/12」，把面板撑高不值得；
                  // 超长由提交时的报错兜住。
                  counterText: '',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: border(Colors.transparent),
                  enabledBorder: border(
                    error == null ? Colors.transparent : colors.expense,
                  ),
                  focusedBorder: border(
                    error == null ? accent : colors.expense,
                  ),
                ),
              ),
            ),
          ],
        ),
        // 高度恒定：报错出现/消失时面板不跳动。
        SizedBox(
          height: 20,
          child: error == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 58, top: 4),
                  child: Text(
                    error!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: colors.expense,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// 图标选择器：分组标题分段 + 6 列网格，定高滚动。
///
/// 用 [CustomScrollView] 而不是单个 [GridView]：需要「标题 + 该组网格」
/// 交替排布。滚过 120 个图标时，用户随时知道自己在「出行」还是「居家」——
/// 一片连续网格是做不到这件事的。
///
/// ## 分组标题不吸顶
///
/// 曾经每个标题都是 `SliverPersistentHeader(pinned: true)`。**一个滚动区里
/// 有十一个 pinned header，它们会一个个堆起来**：往下滚时前面的标题全都赖在
/// 顶上不走，十行文字压掉整个视口，图标反而被挤得看不见（那时视口只有 208）。
/// pinned 适合「一屏只有一个吸顶标题」的长列表，不适合这种十几组挤在小视口里
/// 的场景。现在标题就是普通的一行，跟着内容滚出去。
///
/// 第一组固定是「自己的图片」：上传入口必须在面板打开时就能看到，
/// 放在末尾等于藏起来（下面还有 120 个格子要滚）。这一组只有一到两个格子，
/// 占不到半行，成本极低。
class _IconPicker extends StatefulWidget {
  const _IconPicker({
    required this.selected,
    required this.accent,
    required this.accentSoft,
    required this.onSelected,
    required this.onUpload,
    required this.revealSelected,
    required this.height,
  });

  final String selected;
  final Color accent;
  final Color accentSoft;
  final ValueChanged<String> onSelected;

  /// 点上传格子。null 时（正在处理图片）不响应。
  final VoidCallback? onUpload;

  /// 打开时是否滚到当前选中项。
  ///
  /// 只有编辑已有分类时才需要——那时 [selected] 是用户当初的选择，藏在第八组
  /// 也得让他看见。新建时 [selected] 是代码给的默认值 `other`，而它恰好在
  /// 最后一组：真去滚就等于一打开就停在列表底部，用户既看不到上传入口，
  /// 也会误以为「其他」是自己选的。
  final bool revealSelected;

  /// 滚动区高度。由面板按可用空间算出（见 `_pickerHeight`）。
  final double height;

  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  late final ScrollController _controller;

  /// 一行 6 个，格子高 48（42 图标 + 6 行距）。
  static const _columns = 6;
  static const _cellExtent = 48.0;
  static const _headerExtent = 30.0;
  static const _inset = 16.0;

  /// 「自己的图片」组的高度：标题 + 一行格子。
  static const _customGroupExtent = _headerExtent + _cellExtent;

  /// 全部内容的总高度（含「自己的图片」组与末尾留白）。
  ///
  /// 面板拿它当图标区高度的**上限**：再高也只是在底下拖出一片空白。
  static final double contentHeight = () {
    var total = _customGroupExtent + 8;
    for (final group in categoryIconGroups) {
      total +=
          _headerExtent + (group.keys.length / _columns).ceil() * _cellExtent;
    }
    return total;
  }();

  @override
  void initState() {
    super.initState();
    // 编辑已有分类时，它的图标可能在第 8 组——面板一打开就该滚到那儿，
    // 否则用户看不到当前选中项，会以为「没选过图标」。
    _controller = ScrollController(
      initialScrollOffset: widget.revealSelected
          ? _offsetOf(widget.selected)
          : 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 估算 [key] 所在组的滚动偏移。
  ///
  /// 逐组累加「标题高 + 该组行数 × 行高」即可精确算出，
  /// 因为两者都是固定值（不像可变高度列表那样只能靠 key 定位）。
  /// 命中后回退半个格子，让目标行不贴着上一组的内容。
  ///
  /// 目标本来就在首屏内时**返回 0，一格都不滚**：滚动的目的只是「让用户
  /// 看见自己选的那个」，目标已经看得见就没有理由动。硬滚会把顶上的
  /// 「自己的图片」上传入口推出视口——为了露出一个本来就露着的格子，
  /// 反而藏掉一个功能入口。
  double _offsetOf(String key) {
    // 自定义图片就在最顶上，不用滚。
    if (isCustomCategoryIcon(key)) return 0;
    var offset = _customGroupExtent;
    for (final group in categoryIconGroups) {
      if (group.keys.contains(key)) {
        final row = offset + _headerExtent;
        if (row + _cellExtent <= widget.height) return 0;
        return (offset - _cellExtent / 2).clamp(0.0, double.infinity);
      }
      final rows = (group.keys.length / _columns).ceil();
      offset += _headerExtent + rows * _cellExtent;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final custom = widget.selected;
    return SizedBox(
      height: widget.height,
      child: CustomScrollView(
        controller: _controller,
        slivers: [
          const SliverToBoxAdapter(
            child: _IconGroupLabel('自己的图片', extent: _headerExtent),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columns,
                mainAxisExtent: _cellExtent,
              ),
              delegate: SliverChildListDelegate([
                // 已选中的自定义图片也占一格并显示选中态：否则用户上传完，
                // 网格里没有任何一格是亮的，会以为图没选上。
                if (isCustomCategoryIcon(custom))
                  _IconCell(
                    key: const ValueKey('icon-cell-custom'),
                    iconKey: custom,
                    selected: true,
                    accent: widget.accent,
                    accentSoft: widget.accentSoft,
                    onTap: () => widget.onSelected(custom),
                  ),
                _UploadIconCell(
                  accent: widget.accent,
                  accentSoft: widget.accentSoft,
                  onTap: widget.onUpload,
                ),
              ]),
            ),
          ),
          for (final group in categoryIconGroups) ...[
            SliverToBoxAdapter(
              child: _IconGroupLabel(group.label, extent: _headerExtent),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: _inset),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  mainAxisExtent: _cellExtent,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: group.keys.length,
                  (context, index) {
                    final key = group.keys[index];
                    return _IconCell(
                      // key 里带上图标 key：既让 Flutter 在滚动时正确复用格子，
                      // 也让测试能精确定位到「网格里的某个图标」——
                      // 只按图形找会撞上页面上别处的同一个图标。
                      key: ValueKey('icon-cell-$key'),
                      iconKey: key,
                      selected: key == widget.selected,
                      accent: widget.accent,
                      accentSoft: widget.accentSoft,
                      onTap: () => widget.onSelected(key),
                    );
                  },
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      ),
    );
  }
}

/// 单个图标格子。
class _IconCell extends StatelessWidget {
  const _IconCell({
    super.key,
    required this.iconKey,
    required this.selected,
    required this.accent,
    required this.accentSoft,
    required this.onTap,
  });

  final String iconKey;
  final bool selected;
  final Color accent;
  final Color accentSoft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final custom = isCustomCategoryIcon(iconKey);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            // 选中态直接填成语义色 + 白图标，是这块区域里最强的一个色块，
            // 在上百个格子里一眼能找到「我选的是哪个」。
            color: selected ? accent : accentSoft.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            // 图片铺满格子后底色被完全盖住，选中态就没了着力点，
            // 改用一圈语义色描边来表达（与图片本身的颜色也不会打架）。
            border: custom && selected
                ? Border.all(color: accent, width: 2.5)
                : null,
          ),
          alignment: Alignment.center,
          child: CategoryIconView(
            iconKey: iconKey,
            size: 21,
            imageSize: 42,
            color: selected ? Colors.white : colors.muted,
          ),
        ),
      ),
    );
  }
}

/// 「上传图片」格子：虚线圈 + 加号，形态上就是个空位。
///
/// 刻意不做成实心圆片：它不是一个可选的图标，而是一个动作。
/// 与分类管理页末尾那张虚线「新建一级分类」卡是同一套语言。
class _UploadIconCell extends StatelessWidget {
  const _UploadIconCell({
    required this.accent,
    required this.accentSoft,
    required this.onTap,
  });

  final Color accent;
  final Color accentSoft;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Tooltip(
      message: '上传图片作为图标',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Center(
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accentSoft.withValues(alpha: 0.25),
              shape: BoxShape.circle,
              border: Border.all(
                color: enabled ? accent : colors.line,
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              FLucideIcons.imagePlus,
              size: 19,
              color: enabled ? accent : colors.inactive,
            ),
          ),
        ),
      ),
    );
  }
}

/// 分组标题。
///
/// 普通一行文字，跟着内容滚出视口——**刻意不吸顶**。
/// 这里有十一个分组，若每个都做成 `SliverPersistentHeader(pinned: true)`，
/// 往下滚时它们会一个个堆在顶上不走，十来行文字压掉整个视口，
/// 图标反被挤得看不见。pinned 只适合「一屏最多一个吸顶标题」的长列表。
class _IconGroupLabel extends StatelessWidget {
  const _IconGroupLabel(this.label, {required this.extent});

  final String label;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: extent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.inactive,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

/// 编辑态的「启用」开关行。
///
/// 停用是记账语义里的软删除：分类从记账页的选择器消失，但历史账单照旧显示。
/// 副标题把这层含义写出来——只写「启用」用户会以为停用等于删除。
class _ActiveRow extends StatelessWidget {
  const _ActiveRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '在记账时可选',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value ? '关闭后不影响历史账单' : '已停用，记账时不再出现',
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
              ],
            ),
          ),
          // AppSwitch 内部左右各有 8 的隐形留白，右移把轨道右缘拉回 20 那条线。
          Transform.translate(
            offset: const Offset(12, 0),
            child: AppSwitch(value: value, onChange: onChanged),
          ),
        ],
      ),
    );
  }
}

/// 主操作按钮：语义色描边胶囊，与首页确认弹窗、记账页保存键同一语言。
class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.label,
    required this.accent,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          disabledBackgroundColor: colors.line,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: context.radii.sheetAll),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

/// 删除按钮：只有图标的方形钮，视觉重量刻意低于「保存」。
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Material(
      color: colors.expenseSoft,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: Icon(
              FLucideIcons.trash2,
              size: 20,
              color: enabled ? colors.expense : colors.inactive,
            ),
          ),
        ),
      ),
    );
  }
}
