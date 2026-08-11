import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/database/app_database.dart';
import '../../../core/media/image_storage.dart';
import '../../../core/preferences/backdrop_blur.dart';
import '../../../core/preferences/category_picker_layout.dart';
import '../../../core/preferences/last_category.dart';
import '../../../core/preferences/money_grouped.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/image_backdrop.dart';
import '../../../shared/widgets/local_image.dart';
import '../application/amount_expression.dart';
import '../application/providers.dart';

class TransactionEditor extends ConsumerStatefulWidget {
  const TransactionEditor({super.key, this.existing, this.initialDate});

  final LedgerItem? existing;

  /// 新建时的预设记账日期。
  ///
  /// 从明细页某天的日卡头部点「+」进来时带上那一天，省得用户再选一次日期。
  /// 为 null 走「今天」。编辑已有账单时本参数无效——账单自身的日期才是准的。
  final DateTime? initialDate;

  @override
  ConsumerState<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends ConsumerState<TransactionEditor> {
  late final TextEditingController _noteController;

  /// 备注框焦点。聚焦 = 系统键盘接管输入，数字键盘该主动让位。
  final FocusNode _noteFocus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _pendingImages = [];
  final List<TransactionImageEntry> _existingImages = [];
  final Set<String> _removedImageIds = {};
  final ScrollController _scrollController = ScrollController();

  /// 背板当前展示第几张图（多图时由 [_backdropTimer] 推着走）。
  int _backdropIndex = 0;
  Timer? _backdropTimer;

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
        ? dateOnly(widget.initialDate ?? DateTime.now())
        : dateFromKey(transaction.accountingDate);
    final occurred = transaction == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(transaction.occurredAt);
    _time = TimeOfDay.fromDateTime(occurred);
    _amountExpr = transaction == null
        ? ''
        : (transaction.amountCents / 100).toStringAsFixed(2);
    _noteController = TextEditingController(text: transaction?.note ?? '');
    _noteFocus.addListener(() {
      if (mounted) setState(() {});
    });
    if (transaction != null) {
      Future<void>(() async {
        final images = await ref
            .read(databaseProvider)
            .imagesFor(transaction.id);
        if (mounted) {
          setState(() {
            _existingImages.addAll(images);
            _restartBackdropRotation();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _backdropTimer?.cancel();
    _noteController.dispose();
    _noteFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int get _visibleImageCount =>
      _existingImages
          .where((image) => !_removedImageIds.contains(image.id))
          .length +
      _pendingImages.length;

  /// 可以铺到页面背板上的图，顺序与图片面板一致（已有图在前，新选的在后）。
  ///
  /// 解码宽度压到 [_kBackdropDecodeWidth]：这一层会被高斯模糊 + 渐隐吃掉细节，
  /// 按原始分辨率解码只是白白占内存。已有图片走 [ImageStorage.resolveSyncPath]
  /// 的同步缓存，避免异步 resolve 让背板晚一帧闪进来。
  List<ImageProvider> get _backdropImages {
    final images = <ImageProvider>[];
    for (final image in _existingImages) {
      if (_removedImageIds.contains(image.id)) continue;
      final path = ImageStorage.resolveSyncPath(image.thumbnailPath);
      if (path != null) images.add(_resized(File(path)));
    }
    for (final image in _pendingImages) {
      images.add(_resized(File(image.path)));
    }
    return images;
  }

  ImageProvider _resized(File file) => ResizeImage(
    FileImage(file),
    width: _kBackdropDecodeWidth,
    allowUpscaling: false,
  );

  /// 图片增删后重排背板轮播：只有一张不转，多张从第一张重新开始。
  ///
  /// 索引只增不回绕，取图时再对当前张数取模——这样删图导致张数变化时
  /// 也不会越界，不用在每个增删入口同步维护索引。
  void _restartBackdropRotation() {
    _backdropTimer?.cancel();
    _backdropTimer = null;
    _backdropIndex = 0;
    if (_visibleImageCount < 2) return;
    _backdropTimer = Timer.periodic(_kBackdropRotateInterval, (_) {
      if (mounted) setState(() => _backdropIndex++);
    });
  }

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
            _amountExpr =
                _amountExpr.substring(0, _amountExpr.length - 1) + key;
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

  /// 长按退格：一次清空整个表达式。
  ///
  /// 输错一长串（`128.5+66`）时逐位点退格很折磨。用重一档的震动反馈
  /// 与单击区分开，让用户知道「这下是全清，不是删一位」。
  void _clearAmount() {
    if (_amountExpr.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _amountExpr = '');
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
    if (mounted) setState(_restartBackdropRotation);
  }

  Future<void> _selectDate() async {
    final value = await showAppDatePicker(context, initial: _date);
    if (value != null) setState(() => _date = dateOnly(value));
  }

  Future<void> _selectTime() async {
    final value = await showAppTimePicker(context, initial: _time);
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
      await ref
          .read(lastCategoryProvider.notifier)
          .remember(_kind, _categoryId!);
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
          _restartBackdropRotation();
        });
        showAppToast(
          context,
          message: '已保存，继续记下一笔',
          level: AppToastLevel.success,
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
    showAppToast(context, message: message, level: AppToastLevel.error);
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    final storage = ref.watch(imageStorageProvider);
    // 收支语义色：支出红 / 收入绿，贯穿金额卡与键盘按键。
    final accent = _kind == 0 ? AppColors.expense : AppColors.income;
    // 金额卡的千分位跟随全局偏好，与明细页 / 统计页的 formatMoney 保持一致。
    final grouped = ref.watch(moneyGroupedProvider);
    // 多图时轮流当背板：索引由定时器推进，这里对当前张数取模。
    final backdrops = _backdropImages;
    final backdrop = backdrops.isEmpty
        ? null
        : backdrops[_backdropIndex % backdrops.length];

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          ImageBackdrop(
            image: backdrop,
            blurSigma: ref.watch(backdropBlurProvider),
          ),
          AppTopBar(
            backgroundColor: Colors.transparent,
            title: _isEditing ? '编辑账单' : '记一笔',
            body: SafeArea(
              top: false,
              // 键盘区显示与否由两个条件把关，各管一头，见 _NumericKeypad 类文档：
              // 备注没聚焦（要不要留）、剩余高度够不够（能不能留）。
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  children: [
                    Expanded(
                      child: ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          // 收支开关与「分类」同行：它切的就是下面这张网格，
                          // 摆在一起从属关系自明，也省下独占一行的高度。
                          Row(
                            children: [
                              const _SectionTitle(title: '分类'),
                              const Spacer(),
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
                            ],
                          ),
                          const SizedBox(height: 10),
                          StreamBuilder<List<CategoryEntry>>(
                            stream: database.watchCategories(_kind),
                            builder: (context, snapshot) {
                              final categories =
                                  snapshot.data ?? const <CategoryEntry>[];
                              if (categories.isEmpty) {
                                return const SizedBox(
                                  height: 72,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              _prefillLastCategory(categories);
                              return _CategoryPicker(
                                categories: categories,
                                selectedId: _categoryId,
                                accent: accent,
                                onSelected: _onCategorySelected,
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    // 金额显示 + 日期/时刻 + 备注/图片条 + 数字键盘合成一块常驻输入面板。
                    _NumericKeypad(
                      showKeys:
                          !_noteFocus.hasFocus &&
                          constraints.maxHeight >=
                              _NumericKeypad.heightWithKeys,
                      expression: _amountExpr,
                      noteFocus: _noteFocus,
                      amountValue: _amountValue,
                      kind: _kind,
                      grouped: grouped,
                      accent: accent,
                      canSave: _canSave,
                      saving: _saving,
                      noteController: _noteController,
                      date: _date,
                      time: _time,
                      onPickDate: _selectDate,
                      onPickTime: _selectTime,
                      imageCount: _visibleImageCount,
                      imagePreview: imagePreview,
                      onImageTap: _showImageSheet,
                      onInput: _onKeypadInput,
                      onClear: _clearAmount,
                      onSave: _canSave && !_saving ? () => _save() : null,
                      onSaveContinue: _canSave && !_saving && !_isEditing
                          ? () => _save(continueAfter: true)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 背板图的解码宽度。模糊后细节全丢，再高只是多占内存。
const int _kBackdropDecodeWidth = 480;

/// 多图时每张背板停留的时长。
const _kBackdropRotateInterval = Duration(seconds: 4);

class _CategoryPicker extends ConsumerStatefulWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.accent,
    required this.onSelected,
  });

  final List<CategoryEntry> categories;
  final String? selectedId;

  /// 收支语义色：选中态的图标/文字用它，和金额卡、键盘保持一致。
  final Color accent;
  final ValueChanged<String> onSelected;

  @override
  ConsumerState<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends ConsumerState<_CategoryPicker> {
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
    _expandedId = _parentIdOf(widget.selectedId);
  }

  @override
  void didUpdateWidget(covariant _CategoryPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换收支类型后选中项被清空，同时收起展开的一级分类。
    if (widget.selectedId == null && _expandedId != null) {
      _expandedId = null;
      _rowPanelOwner.clear();
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

  void _onParentTap(CategoryEntry parent, bool hasChildren, {int? rowIndex}) {
    // 一级分类本身就是可选中的：点击即选中；
    // 有二级分类时同时展开/收起，二级只是进一步的细选，可以不选。
    widget.onSelected(parent.id);
    if (!hasChildren) return;
    setState(() {
      _expandedId = _expandedId == parent.id ? null : parent.id;
      // 收起时也要记下来，面板才有数据播收起动画。
      if (rowIndex != null) _rowPanelOwner[rowIndex] = parent.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(categoryPickerLayoutProvider);
    final parents = widget.categories.where((item) => item.level == 1).toList();
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
            key: ValueKey('cat-tile-${parent.id}'),
            category: parent,
            selected: parent.id == selectedParentId,
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
            selectedId: widget.selectedId,
            accent: widget.accent,
            columns: _columns,
            indent: 16,
            onSelected: widget.onSelected,
          ),
        ],
      ],
    );
  }

  /// 网格模式：一级分类 5 列网格，二级分类面板插入在被展开项所在行的下方。
  ///
  /// 每行都固定挂一个面板槽（没有展开项时高度为 0），这样 [Column] 的孩子结构
  /// 不会随展开状态增删——否则后续孩子的位置整体偏移，Flutter 按下标复用
  /// Element 时会给面板重建State，展开动画会被跳过（直接就是展开态）。
  Widget _buildGrid(List<CategoryEntry> parents, String? selectedParentId) {
    final rows = <Widget>[];
    for (var rowIndex = 0; rowIndex * _columns < parents.length; rowIndex++) {
      final start = rowIndex * _columns;
      final rowParents = parents.sublist(
        start,
        start + _columns > parents.length ? parents.length : start + _columns,
      );
      // 该行要挂面板的一级分类：优先当前展开项，否则是刚被收起、正在播动画的那个。
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
                        category: rowParents[i],
                        selected: rowParents[i].id == selectedParentId,
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
          selectedId: widget.selectedId,
          accent: widget.accent,
          columns: _columns,
          onSelected: widget.onSelected,
        ),
      );
    }
    return Column(children: rows);
  }
}

/// 列表模式的一级分类行：无卡片，扁平的图标 + 名称，右侧箭头随展开旋转。
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
    final color = selected ? accent : AppColors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            CategoryIconView(iconKey: category.iconKey, color: color, size: 24),

            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? AppColors.ink : AppColors.muted,
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
                  color: selected ? accent : AppColors.line,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 网格模式下的一级分类单元格：扁平图标 + 下方文字，无卡片；
/// 有二级分类时，图标右下角挂一个展开/收起的小角标。
class _ParentGridCell extends StatelessWidget {
  const _ParentGridCell({
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
    final color = selected ? accent : AppColors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
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
                            color: selected ? accent : AppColors.line,
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
                color: selected ? AppColors.ink : AppColors.muted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 二级分类面板：白色圆角底+ 顶部指向所属一级分类的小尖角，
/// 展开/收起走高度 + 淡入的组合动画。
/// 二级分类面板：白色圆角底，展开/收起走高度 + 淡入的组合动画。
class _ChildrenPanel extends StatefulWidget {
  const _ChildrenPanel({
    super.key,
    required this.ownerId,
    required this.visible,
    required this.children,
    required this.selectedId,
    required this.accent,
    required this.columns,
    required this.onSelected,
    this.indent = 0,
  });

  /// 当前面板归属的一级分类 id。同一个面板槽换了归属时要重播展开动画。
  final String? ownerId;
  final bool visible;
  final List<CategoryEntry> children;
  final String? selectedId;
  final Color accent;
  final int columns;
  final ValueChanged<String> onSelected;

  /// 左侧缩进：列表模式用缩进体现层级。
  final double indent;

  @override
  State<_ChildrenPanel> createState() => _ChildrenPanelState();
}

class _ChildrenPanelState extends State<_ChildrenPanel>
    with SingleTickerProviderStateMixin {
  /// 必须在 [initState] 里建，不能靠 `late final` 的惰性初始化。
  ///
  /// 网格模式下每行都常挂一个面板槽，没展开的那些行 [build] 会因 children 为空
  /// 提前返回，`_controller` 一次都不会被读到。等页面销毁时 [dispose] 里那句
  /// `_controller.dispose()` 成了首次访问，才去构造 [AnimationController] ——
  /// 而它要通过 context 查 [TickerMode]，此时 element 已经 deactivate，直接断言失败。
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
    // 同一行内从A 换成 B：内容整块换掉，从 0 重新长出来才不会显得是硬切。
    if (ownerChanged) _controller.value = 0;
    _controller.forward();
    // 展开时把面板滚入可见区域，避免被键盘/底栏遮挡。
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
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
                        iconKey: widget.children[i].iconKey,
                        name: widget.children[i].name,
                        selected: widget.selectedId == widget.children[i].id,
                        accent: widget.accent,
                        onTap: () => widget.onSelected(widget.children[i].id),
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
///
/// 刻意**不撑满一行**：它只是个二选一的类型开关，信息量远小于金额与分类网格。
/// 之前满宽 + 10px 竖向内距，视觉重量压过了真正的主角（金额），一进页面眼睛
/// 先被它抓住。改成 [_kHeight] 高、内容宽度的小胶囊，层级才回到
/// 「金额 > 分类 > 类型开关」。
///
/// 宽度由 [_kSegmentWidth] 定死、不做居中或拉伸 —— 摆在哪由调用方决定
/// （现在是「分类」标题行的右端）。自带 [Center] 会在 Row 里撑满剩余宽度。
class _KindSwitch extends StatelessWidget {
  const _KindSwitch({required this.kind, required this.onChanged});

  final int kind;
  final ValueChanged<int> onChanged;

  /// 胶囊总高。32 是「拇指还够点、又不抢戏」的平衡点；
  /// 配合 [_kSegmentWidth] 得到两枚 62x26 的小段。
  static const double _kHeight = 32;

  /// 单段宽度。两个中文字 + 呼吸空间，固定宽度让滑块位移距离恒定。
  static const double _kSegmentWidth = 62;

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
            // 滑块：一块白底在两段之间滑动。用位移而不是「两个段各自淡入淡出
            // 背景」，切换才有连贯的运动感，也不会在中途出现两块白。
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
          ],
        ),
      ),
    );
  }
}

/// 胶囊里的一段：只负责文字与点击，选中态的白底由 [_KindSwitch] 的滑块提供。
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

/// 金额卡的测试入口。
///
/// [_AmountCard] 是私有的（不希望被别的页面误用），但它承载了几条容易回归的
/// 硬性行为——溢出往左裁、高度不随运算符变化、负数要有文字解释。
/// 这层薄壳只为 test/amount_card_test.dart 打开访问，不参与业务渲染。
@visibleForTesting
class AmountCardForTest extends StatelessWidget {
  const AmountCardForTest({
    super.key,
    required this.expression,
    required this.amountValue,
    required this.kind,
    this.grouped = true,
  });

  final String expression;
  final double amountValue;
  final int kind;
  final bool grouped;

  @override
  Widget build(BuildContext context) => _AmountCard(
    expression: expression,
    amountValue: amountValue,
    kind: kind,
    grouped: grouped,
  );
}

/// 输入面板顶部的金额显示条：只读展示，输入来自同一面板下方的数字键盘。
///
/// ## 形态：显示屏，不是卡片
///
/// 它曾是滚动区里一张独立的白底圆角卡（带语义色描边），因为孤悬在内容流中
/// 需要自证边界。现在它和日期条、备注、按键同属一块 [_NumericKeypad] 面板，
/// 再留圆角描边就成了「面板里套卡片」，视觉更碎。所以改成**通栏白条**：
/// 无圆角无描边，靠与下方 [AppColors.canvas] 灰底的色差自然分区，
/// 就是计算器「上显示屏、下键盘」的经典关系。
///
/// 描边原先还兼职「有值时点亮语义色」的反馈，去掉后由大数字本身和光标承担
/// ——它们本来就是语义色，反馈没有丢。
///
/// ## 层级：结果是主角，过程是配角
///
/// 旧版把 28px 大字给了**表达式**（过程）、12px 灰字给了**合计**（结果），
/// 而记账真正要确认的是「这笔到底多少钱」——重量分配是反的。
/// 现在含运算符时：表达式退到上方一行小字，合计升为大字主角；
/// 不含运算符时（绝大多数场景）仍是单行大字，**且总高与含运算符时一致**，
/// 靠固定 [_kBodyHeight] 撑住。高度一变，整块输入面板会随按键上下跳
/// （搬进面板前的后果是下面的分类网格跳，约束没变，只是代价更大了）。
///
/// ## 溢出：截头留尾，而不是省略号截尾
///
/// 金额从左往右输入，尾部是刚按下的那一位。旧版用 `TextOverflow.ellipsis`
/// 从尾部截，一长就变 `3.5+7+12+8…`——**新按的数字看不见了，光标还亮着**，
/// 输入反馈直接断掉。这里改用右对齐 + 单行 [SingleChildScrollView] 反向裁剪：
/// 超长时自然把左边挤出可视区，尾部与光标永远可见（同计算器的行为）。
class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.expression,
    required this.amountValue,
    required this.kind,
    required this.grouped,
  });

  final String expression;
  final double amountValue;
  final int kind;

  /// 是否千分位分组，跟随全局 `moneyGrouped` 偏好。
  final bool grouped;

  /// 主数字行的固定高度。锁死它，切换「有无运算符」时总高不变。
  /// 40 是 28px 大字（headlineMedium）加行高后的下限，不能再压。
  static const double _kBodyHeight = 40;

  /// 辅助行（表达式 / 提示语）固定高度，同样为了稳定总高。
  static const double _kHintHeight = 16;

  @override
  Widget build(BuildContext context) {
    final amountColor = kind == 0 ? AppColors.expense : AppColors.income;
    final hasExpr = expression.isNotEmpty;
    final showEquals = AmountExpression.hasOperator(expression);
    // 负数（如 `5-8`）保存按钮本来就是灰的，但旧版界面不解释为什么。
    final isNegative = amountValue < 0;

    // 主行显示什么：有运算符时显示合计（结果），否则显示正在输入的数字。
    final mainText = showEquals
        ? _formatValue(amountValue)
        : (hasExpr
              ? AmountExpression.format(expression, grouped: grouped)
              : '');
    final mainColor = isNegative
        ? AppColors.expense
        : (hasExpr ? amountColor : AppColors.line);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 辅助行：表达式过程 / 负数提示 ──
          SizedBox(
            height: _kHintHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: isNegative
                  ? Text(
                      '金额需大于 0',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: AppColors.expense.withValues(alpha: 0.85),
                      ),
                    )
                  : (showEquals
                        ? Text(
                            AmountExpression.format(
                              expression,
                              grouped: grouped,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.1,
                              color: AppColors.muted,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          )
                        : const SizedBox.shrink()),
            ),
          ),
          // ── 主行：¥ + 大数字 + 光标 ──
          SizedBox(
            height: _kBodyHeight,
            child: Row(
              children: [
                Text(
                  '¥',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ScrollingAmount(
                    text: mainText,
                    placeholder: '0.00',
                    color: mainColor,
                    caretColor: amountColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 合计的展示格式：固定两位小数 + 千分位。
  String _formatValue(double value) {
    final fixed = value.toStringAsFixed(2);
    if (!grouped) return fixed;
    final negative = fixed.startsWith('-');
    final body = negative ? fixed.substring(1) : fixed;
    return '${negative ? '-' : ''}${AmountExpression.format(body)}';
  }
}

/// 金额主数字 + 紧跟其后的光标条，超长时向左溢出（尾部始终可见）。
///
/// 实现要点：外层 [SingleChildScrollView] 只用来做「反向裁剪」——
/// `reverse: true` 让滚动位置默认停在末尾，
/// `physics: NeverScrollableScrollPhysics` 禁掉手动滚动（金额不该被划走）。
/// 这样内容超宽时被裁掉的是**左边**，而不是尾部加省略号。
class _ScrollingAmount extends StatelessWidget {
  const _ScrollingAmount({
    required this.text,
    required this.placeholder,
    required this.color,
    required this.caretColor,
  });

  final String text;

  /// 空值时的占位数字（灰色）。
  final String placeholder;
  final Color color;
  final Color caretColor;

  @override
  Widget build(BuildContext context) {
    final isEmpty = text.isEmpty;
    final caret = Container(
      margin: const EdgeInsets.only(left: 3),
      width: 2,
      height: 26,
      decoration: BoxDecoration(
        color: caretColor,
        borderRadius: BorderRadius.circular(1),
      ),
    );
    final number = Text(
      isEmpty ? placeholder : text,
      maxLines: 1,
      softWrap: false,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
        // 等宽数字 + 零字距：位数变化时数字不左右抖，也不显松散。
        letterSpacing: 0,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    // 空态：光标贴在 ¥ 之后（即占位数字之前）。
    // 旧版把光标放在灰色 `0.00` 右侧，暗示下一位落在 `0.00` 后面，
    // 但实际按 5 得到的是 `5` 而不是 `0.005`，位置与行为不符。
    if (isEmpty) {
      return Row(
        children: [
          caret,
          Flexible(child: number),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(children: [number, caret]),
    );
  }
}

/// 键盘上方的日期/时刻条：两枚并排的小胶囊，点击各自唤起选择器。
///
/// 原先它是滚动区里的「时间」卡片 + 今天/昨天快捷键，占掉近三行高度，
/// 而实际改动频率远低于金额和分类。现在挪到备注同一层的常驻面板顶部：
/// 日期始终可见、随手可改，又不再和分类网格争夺竖向空间。
/// 快捷键去掉了——默认就是今天，选别的日子走日历更直接。
class _DateTimeBar extends StatelessWidget {
  const _DateTimeBar({
    required this.date,
    required this.time,
    required this.onPickDate,
    required this.onPickTime,
  });

  final DateTime date;
  final TimeOfDay time;
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

  /// 日期文案：今天/昨天直接说人话，其余显示「x 月 x 日 周x」，
  /// 跨年再补上年份，避免把上一年的账记到今年而不自知。
  String get _dateLabel {
    if (_isToday) return '今天';
    if (_isYesterday) return '昨天';
    final day = formatDay(date);
    if (date.year != DateTime.now().year) return '${date.year} 年 $day';
    return '$day ${formatWeekday(date)}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DateTimeChip(
          icon: FLucideIcons.calendarDays,
          label: _dateLabel,
          onTap: onPickDate,
        ),
        const SizedBox(width: 8),
        _DateTimeChip(
          icon: FLucideIcons.clock,
          label: _clock(time),
          onTap: onPickTime,
        ),
      ],
    );
  }

  /// 固定 24 小时制，与时间选择器保持一致，避免跟随系统出现「下午 8:46」。
  static String _clock(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

/// 日期/时刻胶囊：白底小药丸，图标 + 一行文字，整块可点。
class _DateTimeChip extends StatelessWidget {
  const _DateTimeChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 二级分类选项：与一级网格一致的「大图标 + 下方小文字」竖向小格子。
/// 二级分类单元格：扁平图标 + 文字，选中用语义色，不用卡片/描边。
class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
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
    final color = selected ? accent : AppColors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryIconView(iconKey: iconKey, size: 24, color: color),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                color: selected ? AppColors.ink : AppColors.muted,
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
                child: const Icon(
                  FLucideIcons.x,
                  size: 14,
                  color: Colors.white,
                ),
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

/// 面板中部的备注输入框：唤起系统键盘，面板整体被顶上去，数字键盘同时收起。
///
/// 键盘右下角固定为「完成」（[TextInputAction.done]）而不是换行——备注是单行，
/// 且这是收起系统键盘、让数字键盘和保存键回来的主出口。次出口是点金额显示条。
/// 没有出口的话，用户打完备注得先在面板外找地方点一下才能保存。
class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
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

/// 底部常驻输入面板：金额显示条 + 日期/时刻条 + 备注/图片条 + 数字键盘。
///
/// 金额显示与键盘本是一个逻辑控件，早期却被拆在页面两端（金额卡在滚动区顶部、
/// 键盘钉在底部），眼睛要在屏幕上下两头来回跑才能确认「按下去的数字进了哪」。
/// 现在合成一块：显示条通栏白底当「显示屏」，其余部分灰底当「键盘」，
/// 输入与反馈落在同一个拇指可达的区域内。
///
/// 固定高度布局（不用纵向 Expanded）——它被放在 Column 里、高度约束无界，
/// 用 Expanded 会因无法确定高度而崩溃。每行固定 [_keyHeight]。
/// 数字键盘常驻、不随金额输入消失；记账场景常见「多笔相加」，加减直接在键盘算，
/// 显示条实时给出合计。按键强调色跟随收支类型（支出红 / 收入绿）。
///
/// 键盘区（[showKeys]）由调用方用两个条件把关，缺一不可：
///
/// 1. **备注没聚焦**——聚焦时输入已被系统键盘接管，数字键盘不但用不上，
///    还会把分类网格挤没。这条管「要不要留」，是体验。
/// 2. **剩余高度 >= [heightWithKeys]**——面板在 Column 里是固定高度，
///    上方 `Expanded` 收缩到 0 之后无处可让，装不下就是 RenderFlex overflow。
///    这条管「能不能留」，是正确性。
///
/// 少了第 1 条，大屏上（系统键盘吃掉 300 后仍然装得下）两套键盘会同时堆在
/// 屏幕上。少了第 2 条，失焦的瞬间键盘区会立刻装回来，而此时系统键盘还在
/// 下滑、空间尚未归还，小屏上那一帧就是黄黑条。
///
/// 高度判断刻意落在「装不装得下」而不是「系统键盘是否弹起」：前者与布局同帧
/// 成立，后者要追 viewInsets 的变化时序，中间必然出现「空间已经变小、键盘区
/// 还没撤」的帧。也因此收起过程不能加高度动画——动画的中间高度同样会撞上限。
class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({
    required this.showKeys,
    required this.noteFocus,
    required this.expression,
    required this.amountValue,
    required this.kind,
    required this.grouped,
    required this.accent,
    required this.canSave,
    required this.saving,
    required this.noteController,
    required this.date,
    required this.time,
    required this.onPickDate,
    required this.onPickTime,
    required this.imageCount,
    required this.imagePreview,
    required this.onImageTap,
    required this.onInput,
    required this.onClear,
    required this.onSave,
    required this.onSaveContinue,
  });

  /// 是否渲染数字键盘区。见类文档里的两个把关条件。
  final bool showKeys;

  /// 备注框的焦点。挂到 [_NoteField] 上，供上层判断是否该收起键盘区。
  final FocusNode noteFocus;

  /// 金额表达式原文（可含 + −），交给显示条排版。
  final String expression;

  /// 表达式求值结果，含运算符时作为主数字显示。
  final double amountValue;

  /// 收支类型：0 支出 / 1 收入。显示条按它取语义色。
  final int kind;

  /// 是否千分位分组，跟随全局 `moneyGrouped` 偏好。
  final bool grouped;

  /// 收支语义色：支出红 / 收入绿，用于符号键与保存键。
  final Color accent;
  final bool canSave;
  final bool saving;
  final TextEditingController noteController;
  final DateTime date;
  final TimeOfDay time;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final int imageCount;

  /// 顶栏图片入口的缩略图（无图时为 null，显示相机图标）。
  final Widget? imagePreview;
  final VoidCallback onImageTap;
  final ValueChanged<String> onInput;

  /// 长按退格键：清空整个金额表达式。
  final VoidCallback onClear;
  final VoidCallback? onSave;
  final VoidCallback? onSaveContinue;

  static const double _keyHeight = 52;
  static const double _gap = 6;

  /// 键盘区自身的高度：4 行按键 + 3 道行距 + 底部留白。
  static const double _keysHeight = _keyHeight * 4 + _gap * 3 + 10;

  /// 面板去掉键盘区后的高度：显示条 72 + 日期条约 38 + 备注行 62。
  ///
  /// 日期胶囊的高度由文字度量决定、不是写死的，所以这里取的是含余量的估值；
  /// 估小了会导致「判断说装得下、实际差几个像素」，因此宁可往大了算。
  static const double _panelBaseHeight = 180;

  /// 完整面板（含键盘区）需要的高度。低于它就必须收起键盘区，
  /// 否则 Column 溢出。test/transaction_editor_test.dart 锁住这条。
  static const double heightWithKeys = _panelBaseHeight + _keysHeight;

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
          // 金额显示屏。整条可点 = 收起系统键盘，让数字键盘回来——
          // 备注打完字后回到记账主流程的最短路径，也强化「显示条属于输入面板」。
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: _AmountCard(
              expression: expression,
              amountValue: amountValue,
              kind: kind,
              grouped: grouped,
            ),
          ),
          // 日期 / 时刻：放在备注上方，与输入区同层，随手可改。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _DateTimeBar(
              date: date,
              time: time,
              onPickDate: onPickDate,
              onPickTime: onPickTime,
            ),
          ),
          // 备注输入 + 图片入口。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: _NoteField(
                    controller: noteController,
                    focusNode: noteFocus,
                  ),
                ),
                const SizedBox(width: 10),
                _ImageEntry(
                  count: imageCount,
                  preview: imagePreview,
                  onTap: onImageTap,
                ),
              ],
            ),
          ),
          if (showKeys) _keys(),
        ],
      ),
    );
  }

  /// 数字键盘区。空间不够时整块从面板里摘掉，理由见类文档。
  Widget _keys() {
    return Padding(
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
                  child: _NumKey(value: '0', onTap: () => onInput('0')),
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: SizedBox(
                  height: _keyHeight,
                  child: _NumKey(value: '.', onTap: () => onInput('.')),
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
                // 只有退格键支持长按全清。
                onLongPress: keys[i] == 'back' ? onClear : null,
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
  const _NumKey({
    required this.value,
    required this.onTap,
    this.symbolColor,
    this.onLongPress,
  });

  final String value;
  final VoidCallback onTap;

  /// 符号键（+ −）文字色：跟随收支语义色。
  final Color? symbolColor;

  /// 长按回调。目前只有退格键用它做「一次清空」。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isBack = value == 'back';
    final isSymbol = value == '+' || value == '-';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
