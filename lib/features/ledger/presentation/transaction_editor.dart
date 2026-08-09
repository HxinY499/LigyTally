import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/database/app_database.dart';
import '../../../core/preferences/category_picker_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/local_image.dart';
import '../application/providers.dart';

class TransactionEditor extends ConsumerStatefulWidget {
  const TransactionEditor({super.key, this.existing});

  final LedgerItem? existing;

  @override
  ConsumerState<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends ConsumerState<TransactionEditor> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _pendingImages = [];
  final List<TransactionImageEntry> _existingImages = [];
  final Set<String> _removedImageIds = {};
  late int _kind;
  String? _categoryId;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;

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
    _amountController = TextEditingController(
      text: transaction == null
          ? ''
          : (transaction.amountCents / 100).toStringAsFixed(2),
    );
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
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  int get _visibleImageCount =>
      _existingImages
          .where((image) => !_removedImageIds.contains(image.id))
          .length +
      _pendingImages.length;

  Future<void> _pickImage(ImageSource source) async {
    if (_visibleImageCount >= 3) return;
    final image = await _picker.pickImage(source: source, imageQuality: 100);
    if (image != null && mounted) {
      setState(() => _pendingImages.add(image));
    }
  }

  Future<void> _showImageSource() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(FLucideIcons.camera),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(FLucideIcons.images),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _selectTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null) setState(() => _time = value);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
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
            existing: widget.existing,
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
      if (mounted) Navigator.pop(context);
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? '记一笔' : '编辑账单')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _KindSwitch(
              kind: _kind,
              onChanged: (value) {
                setState(() {
                  _kind = value;
                  _categoryId = null;
                });
              },
            ),
            const SizedBox(height: 14),
            _AmountCard(controller: _amountController, kind: _kind, autofocus: widget.existing == null),
            const SizedBox(height: 22),
            const _SectionTitle(title: '分类'),
            const SizedBox(height: 10),
            StreamBuilder<List<CategoryEntry>>(
              stream: database.watchCategories(_kind),
              builder: (context, snapshot) {
                final categories = snapshot.data ?? const <CategoryEntry>[];
                if (categories.isEmpty) {
                  return const SizedBox(
                    height: 72,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _CategoryPicker(
                  categories: categories,
                  selectedId: _categoryId,
                  onSelected: (id) => setState(() => _categoryId = id),
                );
              },
            ),
            const SizedBox(height: 24),
            const _SectionTitle(title: '时间'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PickerTile(
                    icon: FLucideIcons.calendar,
                    label:
                        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                    onTap: _selectDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PickerTile(
                    icon: FLucideIcons.clock,
                    label: _time.format(context),
                    onTap: _selectTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            AppTextField(
              multiline: true,
              controller: _noteController,
              maxLength: 200,
              minLines: 1,
              maxLines: 3,
              label: const Text('备注'),
              hint: '可选',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: _SectionTitle(title: '图片')),
                Text(
                  '$_visibleImageCount / 3',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 88,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final image in _existingImages)
                    if (!_removedImageIds.contains(image.id))
                      _ImageTile(
                        child: LocalImage(
                          storage: storage,
                          relativePath: image.thumbnailPath,
                        ),
                        onRemove: () =>
                            setState(() => _removedImageIds.add(image.id)),
                      ),
                  for (var index = 0; index < _pendingImages.length; index++)
                    _ImageTile(
                      child: Image.file(
                        File(_pendingImages[index].path),
                        fit: BoxFit.cover,
                      ),
                      onRemove: () =>
                          setState(() => _pendingImages.removeAt(index)),
                    ),
                  if (_visibleImageCount < 3)
                    _AddImageTile(onTap: _showImageSource),
                ],
              ),
            ),
            const SizedBox(height: 28),
            AppButton(
              onPress: _saving ? null : _save,
              prefix: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(FLucideIcons.check),
              child: Text(_saving ? '保存中' : '保存'),
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

class _ExpandableChildren extends StatelessWidget {
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

  static const _columns = 5;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: !visible || children.isEmpty
          ? const SizedBox(width: double.infinity, height: 0)
          : Container(
              width: double.infinity,
              margin: EdgeInsets.only(top: 6, left: indent),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(14),
              ),
              // 每行固定 5 个等宽格子，大小不受文字长短影响。
              child: Column(
                children: [
                  for (var start = 0; start < children.length; start += _columns)
                    Padding(
                      padding: EdgeInsets.only(top: start == 0 ? 0 : 6),
                      child: Row(
                        children: [
                          for (
                            var i = start;
                            i < start + _columns && i < children.length;
                            i++
                          ) ...[
                            if (i > start) const SizedBox(width: 6),
                            Expanded(
                              child: _CategoryChip(
                                iconKey: children[i].iconKey,
                                name: children[i].name,
                                selected: selectedId == children[i].id,
                                onTap: () => onSelected(children[i].id),
                              ),
                            ),
                          ],
                          // 不足 5 个补空位，保持等宽。
                          for (var i = (children.length - start) > _columns
                                  ? _columns
                                  : (children.length - start);
                              i < _columns;
                              i++) ...[
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

/// hero 金额卡片：大号数字 + ¥ 前缀，数字颜色随收支变化。
class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.controller,
    required this.kind,
    required this.autofocus,
  });

  final TextEditingController controller;
  final int kind;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final amountColor = kind == 0 ? AppColors.expense : AppColors.income;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '¥',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,9}(\.\d{0,2})?'),
                ),
              ],
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: amountColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: '0.00',
                hintStyle: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(
                      color: AppColors.line,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 柔和瓷贴：日期/时间选择等次级操作。
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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

/// 添加图片占位瓷贴。
class _AddImageTile extends StatelessWidget {
  const _AddImageTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 88,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: const Center(
          child: Icon(FLucideIcons.camera, size: 22, color: AppColors.muted),
        ),
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 88,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
            Positioned(
              top: 2,
              right: 2,
              child: IconButton.filled(
                onPressed: onRemove,
                tooltip: '移除图片',
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                icon: const Icon(FLucideIcons.x),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
