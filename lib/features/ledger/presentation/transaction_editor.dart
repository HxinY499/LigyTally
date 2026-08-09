import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/database/app_database.dart';
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
            AppSegmentedControl<int>(
              selected: _kind,
              onChanged: (value) {
                setState(() {
                  _kind = value;
                  _categoryId = null;
                });
              },
              segments: const [
                AppSegment(value: 0, label: '支出'),
                AppSegment(value: 1, label: '收入'),
              ],
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _amountController,
              autofocus: widget.existing == null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,9}(\.\d{0,2})?'),
                ),
              ],
              label: const Text('金额'),
              hint: '0.00',
              prefixBuilder: (context, style, variants) => const Padding(
                padding: EdgeInsets.only(left: 12, right: 4),
                child: Text('¥'),
              ),
            ),
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
            const SizedBox(height: 22),
            const _SectionTitle(title: '时间'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    onPress: _selectDate,
                    variant: AppButtonVariant.outline,
                    prefix: const Icon(FLucideIcons.calendar, size: 18),
                    child: Text(
                      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    onPress: _selectTime,
                    variant: AppButtonVariant.outline,
                    prefix: const Icon(FLucideIcons.clock, size: 18),
                    child: Text(_time.format(context)),
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
                    SizedBox(
                      width: 88,
                      child: AppIconButton(
                        onPress: _showImageSource,
                        icon: const Icon(FLucideIcons.camera),
                      ),
                    ),
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

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<CategoryEntry> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final parents = categories.where((item) => item.level == 1).toList();
    CategoryEntry? selectedCategory;
    for (final category in categories) {
      if (category.id == selectedId) selectedCategory = category;
    }
    final selectedParentId = selectedCategory?.parentId ?? selectedCategory?.id;
    CategoryEntry? selectedParent;
    for (final parent in parents) {
      if (parent.id == selectedParentId) selectedParent = parent;
    }
    final children = selectedParent == null
        ? const <CategoryEntry>[]
        : categories
              .where((item) => item.parentId == selectedParent!.id)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (children.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${selectedParent!.name}的二级分类',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(selectedParent.name),
                      selected: selectedId == selectedParent.id,
                      onSelected: (_) => onSelected(selectedParent!.id),
                    ),
                    for (final child in children)
                      ChoiceChip(
                        avatar: Icon(categoryIcon(child.iconKey), size: 16),
                        label: Text(child.name),
                        selected: selectedId == child.id,
                        onSelected: (_) => onSelected(child.id),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.05,
          ),
          itemCount: parents.length,
          itemBuilder: (context, index) {
            final category = parents[index];
            final selected = category.id == selectedParentId;
            return InkWell(
              onTap: () => onSelected(category.id),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primarySoft : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.line,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      categoryIcon(category.iconKey),
                      color: selected ? AppColors.primary : AppColors.muted,
                      size: 23,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
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
            ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
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
