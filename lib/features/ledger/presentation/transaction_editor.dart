import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/database/app_database.dart';
import '../../../core/preferences/category_picker_layout.dart';
import '../../../core/preferences/last_category.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/local_image.dart';
import '../application/amount_expression.dart';
import '../application/providers.dart';

class TransactionEditor extends ConsumerStatefulWidget {
  const TransactionEditor({super.key, this.existing});

  final LedgerItem? existing;

  @override
  ConsumerState<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends ConsumerState<TransactionEditor> {
  late final TextEditingController _noteController;
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _pendingImages = [];
  final List<TransactionImageEntry> _existingImages = [];
  final Set<String> _removedImageIds = {};
  final ScrollController _scrollController = ScrollController();

  /// 金额表达式（可含+ −），例如 "3.5+7"。展示与计算都基于它。
  String _amountExpr = '';
  late int _kind;
  String? _categoryId;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  bool _prefilledCategory = false;

  bool get _isEditing => widget.existing != null;

  double get _amountValue => AmountExpression.evaluate(_amountExpr);

  bool get _canSave => _amountValue > 0 && _categoryId != null;

  @override
  void initState() {
    super.initState();
    final transaction = widget.existing?.transaction;
    _kind = transaction?.kind ?? 0;
    _categoryId = transaction?.categoryId;
    _date = transaction == null
        ? dateOnly(DateTime.now())
        : dateFromKey(transaction.accountingDate);
    final occurred = transaction == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(transaction.occurredAt);
    _time = TimeOfDay.fromDateTime(occurred);
    _amountExpr = transaction == null
        ?''
        : (transaction.amountCents / 100).toStringAsFixed(2);
    _noteController = TextEditingController(text: transaction?.note ?? '');
    if (transaction != null) {
      Future<void>(() async {
        final images = await ref
            .read(databaseProvider)
            .imagesFor(transaction.id);
        if (mounted) setState(() => _existingImages.addAll(images));
      });
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int get _visibleImageCount =>
      _existingImages
          .where((image) => !_removedImageIds.contains(image.id))
          .length +
      _pendingImages.length;

  /// 新建账单时预选「上次在该收支类型下选的分类」。
  void _prefillLastCategory(List<CategoryEntry> categories) {
    if (_prefilledCategory || _isEditing || _categoryId != null) return;
    _prefilledCategory = true;
    final lastId = ref.read(lastCategoryProvider)[_kind];
    if (lastId == null) return;
    final exists = categories.any((c) => c.id == lastId && c.kind == _kind);
    if (exists) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _categoryId = lastId);
      });
    }
  }

  void _onCategorySelected(String id) {
    HapticFeedback.selectionClick();
    setState(() => _categoryId = id);
  }

  void _onKeypadInput(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (key) {
        case 'back':
          if (_amountExpr.isNotEmpty) {
            _amountExpr = _amountExpr.substring(0, _amountExpr.length - 1);
          }
        case '+':
        case '-':
          if (_amountExpr.isEmpty) return;
          final last = _amountExpr[_amountExpr.length - 1];
          if (last == '+' || last == '-') {
            _amountExpr = _amountExpr.substring(0, _amountExpr.length - 1) + key;
          } else {
            _amountExpr += key;
          }
        case '.':
          // 当前数字段已有小数点则忽略。
          final seg = _currentSegment();
          if (!seg.contains('.')) {
            _amountExpr += _amountExpr.isEmpty ? '0.' : '.';
          }
        default:
          // 限制单段整数位与小数位。
          final seg = _currentSegment();
          if (seg.contains('.')) {
            final decimals = seg.split('.').last;
            if (decimals.length >= 2) return;
          } else if (seg.replaceAll('-', '').length >= 9) {
            return;
          }
          _amountExpr += key;
      }
    });
  }

  /// 当前正在输入的数字段（最后一个运算符之后的部分）。
  String _currentSegment() {
    var idx = -1;
    for (var i = _amountExpr.length - 1; i >= 0; i--) {
      if (_amountExpr[i] == '+' || _amountExpr[i] == '-') {
        idx = i;
        break;
      }
    }
    return _amountExpr.substring(idx + 1);
  }

  /// 选图并加入待上传列表。不触发 setState——调用方决定刷新
  /// 编辑器整体还是图片面板的局部状态。
  Future<void> _pickImage(ImageSource source) async {
    if (_visibleImageCount >= 3) return;
    final image = await _picker.pickImage(source: source, imageQuality: 100);
    if (image != null && mounted) {
      _pendingImages.add(image);
    }
  }

  /// 图片面板里点「添加」：先选来源（拍照/相册），选完刷新面板。
  Future<void> _addImageFromSheet(StateSetter refreshSheet) async {
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
    await _pickImage(source);
    refreshSheet(() {});
  }

  /// 键盘顶栏的图片入口：底部弹出图片管理面板（增删图片）。
  /// 面板直接操作共享的 [_pendingImages] / [_removedImageIds]，
  /// 关闭后再刷新编辑器，更新顶栏缩略图与角标。
  Future<void> _showImageSheet() async {
    final storage = ref.read(imageStorageProvider);
    final accent = _kind == 0 ? AppColors.expense : AppColors.income;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final visibleExisting = [
            for (final image in _existingImages)
              if (!_removedImageIds.contains(image.id)) image,
          ];
          final count = visibleExisting.length + _pendingImages.length;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题栏：居中标题 + 右侧关闭。
                  SizedBox(
                    height: 32,
                    child: Stack(
                      children: [
                        const Center(
                          child: Text(
                            '添加图片',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.pop(context),
                            child: const Icon(
                              FLucideIcons.x,
                              size: 22,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final image in visibleExisting)
                        _SheetImageTile(
                          child: LocalImage(
                            storage: storage,
                            relativePath: image.thumbnailPath,
                          ),
                          onRemove: () => setSheetState(
                            () => _removedImageIds.add(image.id),
                          ),
                        ),
                      for (var i = 0; i < _pendingImages.length; i++)
                        _SheetImageTile(
                          child: Image.file(
                            File(_pendingImages[i].path),
                            fit: BoxFit.cover,
                          ),
                          onRemove: () =>
                              setSheetState(() => _pendingImages.removeAt(i)),
                        ),
                      if (count < 3)
                        _SheetAddTile(
                          onTap: () => _addImageFromSheet(setSheetState),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: Text(
                        '确认（$count/3）',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _selectDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _date = dateOnly(value));
  }

  Future<void> _selectTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null) setState(() => _time = value);
  }

  /// 保存。[continueAfter] 为 true 时保存后不关闭页面，清空金额继续记账。
  Future<void> _save({bool continueAfter = false}) async {
    final amount = _amountValue;
    if (amount <= 0) {
      _showError('请输入正确的金额');
      return;
    }
    if (_categoryId == null) {
      _showError('请选择分类');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(ledgerServiceProvider)
          .save(
            existing: continueAfter ? null : widget.existing,
            kind: _kind,
            amountCents: (amount * 100).round(),
            categoryId: _categoryId!,
            accountingDate: _date,
            occurredAt: DateTime(
              _date.year,
              _date.month,
              _date.day,
              _time.hour,
              _time.minute,
            ),
            note: _noteController.text,
            pendingImages: _pendingImages,
            existingImages: _existingImages,
            removedImageIds: _removedImageIds,
          );
      // 记住这次用的分类，下次新建同类账单预选。
      await ref.read(lastCategoryProvider.notifier).remember(_kind, _categoryId!);
      if (!mounted) return;
      if (continueAfter) {
        HapticFeedback.mediumImpact();
        setState(() {
          _saving = false;
          _amountExpr = '';
          _noteController.clear();
          _pendingImages.clear();
          _existingImages.clear();
          _removedImageIds.clear();
        });
        showFToast(
          context: context,
          title: const Text('已保存，继续记下一笔'),
          duration: const Duration(seconds: 2),
        );
      } else {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError('保存失败：$error');
      }
    }
  }

  void _showError(String message) {
    showFToast(
      context: context,
      title: Text(message),
      variant: FToastVariant.destructive,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    final storage = ref.watch(imageStorageProvider);
    // 收支语义色：支出红 / 收入绿，贯穿金额卡与键盘按键。
    final accent = _kind == 0 ? AppColors.expense : AppColors.income;

    // 顶栏图片入口的缩略图：优先最新待上传，其次已有图片。
    Widget? imagePreview;
    if (_pendingImages.isNotEmpty) {
      imagePreview = Image.file(
        File(_pendingImages.last.path),
        fit: BoxFit.cover,
      );
    } else {
      TransactionImageEntry? lastExisting;
      for (final image in _existingImages) {
        if (!_removedImageIds.contains(image.id)) lastExisting = image;
      }
      if (lastExisting != null) {
        imagePreview = LocalImage(
          storage: storage,
          relativePath: lastExisting.thumbnailPath,
        );
      }
    }

    return Scaffold(
      appBar: AppTopBar(title: _isEditing ? '编辑账单' : '记一笔'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  _KindSwitch(
                    kind: _kind,
                    onChanged: (value) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _kind = value;
                        _categoryId = null;
                        _prefilledCategory = false;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  _AmountCard(
                    expression: _amountExpr,
                    amountValue: _amountValue,
                    kind: _kind,
                  ),
                  const SizedBox(height: 22),
                  const _SectionTitle(title: '分类'),
                  const SizedBox(height: 10),
                  StreamBuilder<List<CategoryEntry>>(
                    stream: database.watchCategories(_kind),
                    builder: (context, snapshot) {
                      final categories =
                          snapshot.data ?? const <CategoryEntry>[];
                      if (categories.isEmpty) {
                        return const SizedBox(
                          height: 72,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      _prefillLastCategory(categories);
                      return _CategoryPicker(
                        categories: categories,
                        selectedId: _categoryId,
                        onSelected: _onCategorySelected,
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle(title: '时间'),
                  const SizedBox(height: 10),
                  _DateQuickRow(
                    date: _date,
                    time: _time,
                    onToday: () =>
                        setState(() => _date = dateOnly(DateTime.now())),
                    onYesterday: () => setState(
                      () => _date = dateOnly(
                        DateTime.now().subtract(const Duration(days: 1)),
                      ),
                    ),
                    onPickDate: _selectDate,
                    onPickTime: _selectTime,
                  ),
                ],
              ),
            ),
            // 备注/图片条 + 自定义键盘常驻底部，不随焦点消失；
            // 备注框聚焦时系统键盘会把整个面板顶上去。
            _NumericKeypad(
              accent: accent,
              canSave: _canSave,
              saving: _saving,
              noteController: _noteController,
              imageCount: _visibleImageCount,
              imagePreview: imagePreview,
              onImageTap: _showImageSheet,
              onInput: _onKeypadInput,
              onSave: _canSave && !_saving ? () => _save() : null,
              onSaveContinue: _canSave && !_saving && !_isEditing
                  ? () => _save(continueAfter: true)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPicker extends ConsumerStatefulWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<CategoryEntry> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  ConsumerState<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends ConsumerState<_CategoryPicker> {
  /// 手风琴模式：同一时间只允许一个一级分类展开。
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _expandedId = _parentIdOf(widget.selectedId);
  }

  @override
  void didUpdateWidget(covariant _CategoryPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换收支类型后选中项被清空，同时收起展开的一级分类。
    if (widget.selectedId == null && _expandedId != null) {
      _expandedId = null;
    }
  }

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

  void _onParentTap(CategoryEntry parent, bool hasChildren) {
    // 一级分类本身就是可选中的：点击即选中；
    // 有二级分类时同时展开/收起，二级只是进一步的细选，可以不选。
    widget.onSelected(parent.id);
    if (!hasChildren) return;
    setState(() {
      _expandedId = _expandedId == parent.id ? null : parent.id;
    });
  }

  Widget _expandedPanel(CategoryEntry parent, {double indent = 18}) {
    return _ExpandableChildren(
      visible: _expandedId == parent.id,
      children: _childrenOf(parent.id),
      selectedId: widget.selectedId,
      onSelected: widget.onSelected,
      indent: indent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(categoryPickerLayoutProvider);
    final parents = widget.categories
        .where((item) => item.level == 1)
        .toList();
    final selectedParentId = _parentIdOf(widget.selectedId);

    if (layout == CategoryPickerLayout.grid) {
      return _buildGrid(parents, selectedParentId);
    }
    return _buildList(parents, selectedParentId);
  }

  /// 列表模式：一级分类纵向排列，二级分类在所属一级下方原地展开。
  Widget _buildList(List<CategoryEntry> parents, String? selectedParentId) {
    return Column(
      children: [
        for (final parent in parents) ...[
          _ParentCategoryTile(
            category: parent,
            selected: parent.id == selectedParentId,
            onTap: () =>
                _onParentTap(parent, _childrenOf(parent.id).isNotEmpty),
          ),
          _expandedPanel(parent),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// 网格模式：一级分类 5 列网格，二级分类面板插入在被展开项所在行的下方。
  Widget _buildGrid(List<CategoryEntry> parents, String? selectedParentId) {
    const columns = 5;
    final rows = <Widget>[];
    for (var start = 0; start < parents.length; start += columns) {
      final rowParents = parents.sublist(
        start,
        start + columns > parents.length ? parents.length : start + columns,
      );
      CategoryEntry? expandedInRow;
      for (final parent in rowParents) {
        if (parent.id == _expandedId) expandedInRow = parent;
      }
      rows.add(
        Row(
          children: [
            for (var i = 0; i < rowParents.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _ParentGridCell(
                  category: rowParents[i],
                  selected: rowParents[i].id == selectedParentId,
                  onTap: () => _onParentTap(
                    rowParents[i],
                    _childrenOf(rowParents[i].id).isNotEmpty,
                  ),
                ),
              ),
            ],
            // 补足空位，保证每行 5 格等宽。
            for (var i = rowParents.length; i < columns; i++) ...[
              if (rowParents.isNotEmpty) const SizedBox(width: 6),
              const Spacer(),
            ],
          ],
        ),
      );
      if (expandedInRow != null) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _expandedPanel(expandedInRow, indent: 0),
          ),
        );
      }
      rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }
}

class _ParentCategoryTile extends StatelessWidget {
  const _ParentCategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final CategoryEntry category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.primary : AppColors.canvas,
              ),
              child: Icon(
                categoryIcon(category.iconKey),
                color: selected ? Colors.white : AppColors.muted,
                size: 15,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 网格模式下的一级分类单元格：大图标 + 下方小文字，选中为高亮态。
class _ParentGridCell extends StatelessWidget {
  const _ParentGridCell({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final CategoryEntry category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.primary : AppColors.canvas,
              ),
              child: Icon(
                categoryIcon(category.iconKey),
                color: selected ? Colors.white : AppColors.muted,
                size: 15,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                color: AppColors.ink,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableChildren extends StatefulWidget {
  const _ExpandableChildren({
    required this.visible,
    required this.children,
    required this.selectedId,
    required this.onSelected,
    this.indent = 18,
  });

  final bool visible;
  final List<CategoryEntry> children;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  /// 左侧缩进：列表模式用缩进体现层级；网格模式面板整行宽，不需要缩进。
  final double indent;

  @override
  State<_ExpandableChildren> createState() => _ExpandableChildrenState();
}

class _ExpandableChildrenState extends State<_ExpandableChildren> {
  static const _columns = 5;

  @override
  void didUpdateWidget(covariant _ExpandableChildren oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从收起变为展开时，把展开区滚入可见区域，避免被键盘/底栏遮挡。
    if (widget.visible &&
        !oldWidget.visible &&
        widget.children.isNotEmpty) {
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
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: !widget.visible || widget.children.isEmpty
          ? const SizedBox(width: double.infinity, height: 0)
          : Container(
              width: double.infinity,
              margin: EdgeInsets.only(top: 6, left: widget.indent),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(14),
              ),
              // 每行固定 5 个等宽格子，大小不受文字长短影响。
              child: Column(
                children: [
                  for (
                    var start = 0;
                    start < widget.children.length;
                    start += _columns
                  )
                    Padding(
                      padding: EdgeInsets.only(top: start == 0 ? 0 : 6),
                      child: Row(
                        children: [
                          for (
                            var i = start;
                            i < start + _columns && i < widget.children.length;
                            i++
                          ) ...[
                            if (i > start) const SizedBox(width: 6),
                            Expanded(
                              child: _CategoryChip(
                                iconKey: widget.children[i].iconKey,
                                name: widget.children[i].name,
                                selected:
                                    widget.selectedId == widget.children[i].id,
                                onTap: () =>
                                    widget.onSelected(widget.children[i].id),
                              ),
                            ),
                          ],
                          // 不足 5 个补空位，保持等宽。
                          for (
                            var i = (widget.children.length - start) > _columns
                                ? _columns
                                : (widget.children.length - start);
                            i < _columns;
                            i++
                          ) ...[
                            const SizedBox(width: 6),
                            const Spacer(),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

/// 支出/收入胶囊开关：滑块式白底选中块 + 收支语义色文字。
class _KindSwitch extends StatelessWidget {
  const _KindSwitch({required this.kind, required this.onChanged});

  final int kind;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.line.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _KindSegment(
            label: '支出',
            color: AppColors.expense,
            selected: kind == 0,
            onTap: () => onChanged(0),
          ),
          _KindSegment(
            label: '收入',
            color: AppColors.income,
            selected: kind == 1,
            onTap: () => onChanged(1),
          ),
        ],
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            // 注意：不能用 Colors.transparent（透明黑 0x00000000），
            // 白色 → 透明黑的插值会经过深灰，导致取消选中时闪一下暗色。
            // 用透明白做端点，插值只动 alpha 通道，淡出就是干净的。
            color: AppColors.surface.withValues(alpha: selected ? 1.0 : 0.0),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: selected ? 0.06 : 0.0),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? color : AppColors.muted,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// hero 金额卡片：只读展示，输入通过底部常驻的自定义数字键盘。
///
/// 展示当前表达式（含 + −）；键盘常驻，故描边与光标条常显。
class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.expression,
    required this.amountValue,
    required this.kind,
  });

  final String expression;
  final double amountValue;
  final int kind;

  @override
  Widget build(BuildContext context) {
    final amountColor = kind == 0 ? AppColors.expense : AppColors.income;
    final hasExpr = expression.isNotEmpty;
    final showEquals = AmountExpression.hasOperator(expression);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: amountColor, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '¥',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        hasExpr ? expression : '0.00',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: hasExpr? amountColor : AppColors.line,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                      ),
                    ),
                    // 光标条（用细竖条模拟）。
                    Container(
                      margin: const EdgeInsets.only(left: 2),
                      width: 2,
                      height: 26,
                      color: amountColor,
                    ),
                  ],
                ),
                // 含运算符时下方显示实时合计。
                if (showEquals)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '= ¥${amountValue.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: AppColors.muted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间区：日期快捷（今天/昨天/选日期）+ 时间瓷贴。
class _DateQuickRow extends StatelessWidget {
  const _DateQuickRow({
    required this.date,
    required this.time,
    required this.onToday,
    required this.onYesterday,
    required this.onPickDate,
    required this.onPickTime,
  });

  final DateTime date;
  final TimeOfDay time;
  final VoidCallback onToday;
  final VoidCallback onYesterday;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  bool get _isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool get _isYesterday {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return date.year == y.year && date.month == y.month && date.day == y.day;
  }

  @override
  Widget build(BuildContext context) {
    final custom = !_isToday && !_isYesterday;
    final dateLabel =
        '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _DateChip(
                label: '今天',
                selected: _isToday,
                onTap: onToday,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DateChip(
                label: '昨天',
                selected: _isYesterday,
                onTap: onYesterday,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DateChip(
                icon: FLucideIcons.calendar,
                label: custom ? dateLabel : '其他',
                selected: custom,
                onTap: onPickDate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onPickTime,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  FLucideIcons.clock,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  time.format(context),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.3,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: selected ? AppColors.primary : AppColors.ink,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 二级分类选项：与一级网格一致的「大图标 + 下方小文字」竖向小格子。
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.iconKey,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String iconKey;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        height: 64,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.primary : AppColors.canvas,
              ),
              child: Icon(
                categoryIcon(iconKey),
                size: 13,
                color: selected ? Colors.white : AppColors.muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                color: selected ? AppColors.primary : AppColors.ink,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 图片面板里的已选图片瓷贴：88x88 圆角图 + 右上角黑色删除钮。
class _SheetImageTile extends StatelessWidget {
  const _SheetImageTile({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                ),
                child: const Icon(FLucideIcons.x, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 图片面板里的「添加」占位瓷贴。
class _SheetAddTile extends StatelessWidget {
  const _SheetAddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(FLucideIcons.camera, size: 26, color: AppColors.muted),
        ),
      ),
    );
  }
}

/// 键盘顶栏的备注输入框：唤起系统键盘，面板整体被顶上去。
class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      maxLength: 200,
      maxLines: 1,
      style: const TextStyle(fontSize: 14, color: AppColors.ink),
      decoration: const InputDecoration(
        hintText: '点击填写备注',
        hintStyle: TextStyle(fontSize: 14, color: AppColors.muted),
        filled: true,
        fillColor: AppColors.surface,
        counterText: '',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: border,
        enabledBorder: border,
        focusedBorder: border,
      ),
    );
  }
}

/// 键盘顶栏的图片入口：无图显示相机图标，有图显示最新缩略图 + 张数角标。
class _ImageEntry extends StatelessWidget {
  const _ImageEntry({
    required this.count,
    required this.preview,
    required this.onTap,
  });

  final int count;
  final Widget? preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: 46,
        child: preview == null
            ? Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  FLucideIcons.camera,
                  size: 20,
                  color: AppColors.muted,
                ),
              )
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: preview,
                    ),
                  ),
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 底部常驻面板：备注/图片条 + 自定义数字键盘。
///
/// 固定高度布局（不用纵向 Expanded）——它被放在 Column 里、高度约束无界，
/// 用 Expanded 会因无法确定高度而崩溃。每行固定 [_keyHeight]。
/// 键盘始终显示、不会消失；记账场景常见「多笔相加」，加减直接在键盘算，
/// 金额卡实时显示合计。按键强调色跟随收支类型（支出红 / 收入绿）。
class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({
    required this.accent,
    required this.canSave,
    required this.saving,
    required this.noteController,
    required this.imageCount,
    required this.imagePreview,
    required this.onImageTap,
    required this.onInput,
    required this.onSave,
    required this.onSaveContinue,
  });

  /// 收支语义色：支出红 / 收入绿，用于符号键与保存键。
  final Color accent;
  final bool canSave;
  final bool saving;
  final TextEditingController noteController;
  final int imageCount;

  /// 顶栏图片入口的缩略图（无图时为 null，显示相机图标）。
  final Widget? imagePreview;
  final VoidCallback onImageTap;
  final ValueChanged<String> onInput;
  final VoidCallback? onSave;
  final VoidCallback? onSaveContinue;

  static const double _keyHeight = 52;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 备注输入 + 图片入口。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(child: _NoteField(controller: noteController)),
                const SizedBox(width: 10),
                _ImageEntry(
                  count: imageCount,
                  preview: imagePreview,
                  onTap: onImageTap,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _keyRow(const ['7', '8', '9', 'back']),
                const SizedBox(height: _gap),
                _keyRow(const ['4', '5', '6', '-']),
                const SizedBox(height: _gap),
                _keyRow(const ['1', '2', '3', '+']),
                const SizedBox(height: _gap),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: _keyHeight,
                        child: _AgainKey(onTap: onSaveContinue),
                      ),
                    ),
                    const SizedBox(width: _gap),
                    Expanded(
                      child: SizedBox(
                        height: _keyHeight,
                        child: _NumKey(
                          value: '0',
                          onTap: () => onInput('0'),
                        ),
                      ),
                    ),
                    const SizedBox(width: _gap),
                    Expanded(
                      child: SizedBox(
                        height: _keyHeight,
                        child: _NumKey(
                          value: '.',
                          onTap: () => onInput('.'),
                        ),
                      ),
                    ),
                    const SizedBox(width: _gap),
                    Expanded(
                      child: SizedBox(
                        height: _keyHeight,
                        child: _SaveKey(
                          accent: accent,
                          enabled: canSave,
                          loading: saving,
                          onTap: onSave,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyRow(List<String> keys) {
    return Row(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          Expanded(
            child: SizedBox(
              height: _keyHeight,
              child: _NumKey(
                value: keys[i],
                symbolColor: accent,
                onTap: () => onInput(keys[i]),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 单个数字/符号/退格键（白底瓷键）。填满父级给定的固定高度。
class _NumKey extends StatelessWidget {
  const _NumKey({required this.value, required this.onTap, this.symbolColor});

  final String value;
  final VoidCallback onTap;

  /// 符号键（+ −）文字色：跟随收支语义色。
  final Color? symbolColor;

  @override
  Widget build(BuildContext context) {
    final isBack = value == 'back';
    final isSymbol = value == '+' || value == '-';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: isBack
              ? const Icon(FLucideIcons.delete, size: 22, color: AppColors.ink)
              : Text(
                  value == '-' ? '−' : value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isSymbol
                        ? (symbolColor ?? AppColors.primary)
                        : AppColors.ink,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 左下「再记一笔」键：保存后不关页面，清空继续记。不可用时置灰。
class _AgainKey extends StatelessWidget {
  const _AgainKey({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Text(
            '再记一笔',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: enabled ? AppColors.muted : AppColors.line,
            ),
          ),
        ),
      ),
    );
  }
}

/// 右下「保存」键：可用时收支语义色填充，不可用置灰。填满父级固定高度。
class _SaveKey extends StatelessWidget {
  const _SaveKey({
    required this.accent,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final Color accent;
  final bool enabled;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? accent : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  '保存',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: enabled ? Colors.white : AppColors.muted,
                  ),
                ),
        ),
      ),
    );
  }
}
