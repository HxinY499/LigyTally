import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
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
  late String _iconKey;
  late bool _active;
  bool _busy = false;

  /// 名称输入的即时错误提示（空 / 超长 / 重名）。
  String? _error;

  bool get _isEditing => widget.existing != null;

  /// 编辑时父级取自被编辑对象，新建时取自入口。
  String? get _parentId => widget.existing?.parentId ?? widget.parent?.id;

  bool get _isChild => _parentId != null;

  /// 收支语义色：与记账页金额卡、键盘保持一致，让人一眼知道在编哪一侧。
  Color get _accent =>
      widget.kind == 0 ? AppColors.expense : AppColors.income;

  Color get _accentSoft =>
      widget.kind == 0 ? AppColors.expenseSoft : AppColors.incomeSoft;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    // 新建时给个中性默认图标，用户不选也不会拿到空图标。
    _iconKey = existing?.iconKey ?? 'other';
    _active = existing?.isActive ?? true;
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
    final result = await ref
        .read(databaseProvider)
        .deleteCategory(category.id);
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

  @override
  Widget build(BuildContext context) {
    // viewInsets：键盘高度。加在底部让整块面板浮在键盘之上。
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Material(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              if (_subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  _subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: _NameRow(
                  controller: _nameController,
                  iconKey: _iconKey,
                  accent: _accent,
                  accentSoft: _accentSoft,
                  maxLength: _maxNameLength,
                  error: _error,
                  onSubmitted: _busy ? null : _submit,
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择图标',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inactive,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              // 图标很多，给一块定高滚动区：面板整体高度稳定，
              // 不会因为图标表变长就顶到屏幕顶部。
              _IconGrid(
                selected: _iconKey,
                accent: _accent,
                accentSoft: _accentSoft,
                onSelected: (key) {
                  HapticFeedback.selectionClick();
                  setState(() => _iconKey = key);
                },
              ),
              if (_isEditing) ...[
                const Divider(height: 1, thickness: 1, indent: 20, endIndent: 20),
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
                        accent: _accent,
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
    const radius = BorderRadius.all(Radius.circular(12));
    OutlineInputBorder border(Color color) => const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ).copyWith(borderSide: BorderSide(color: color));
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
              child: Icon(categoryIcon(iconKey), size: 24, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLength: maxLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmitted?.call(),
                style: const TextStyle(fontSize: 15, color: AppColors.ink),
                cursorColor: accent,
                decoration: InputDecoration(
                  hintText: '分类名称',
                  hintStyle: const TextStyle(
                    fontSize: 15,
                    color: AppColors.inactive,
                  ),
                  filled: true,
                  fillColor: AppColors.canvas,
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
                    error == null ? Colors.transparent : AppColors.expense,
                  ),
                  focusedBorder: border(
                    error == null ? accent : AppColors.expense,
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
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: AppColors.expense,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// 图标选择网格：6 列，定高滚动。
class _IconGrid extends StatelessWidget {
  const _IconGrid({
    required this.selected,
    required this.accent,
    required this.accentSoft,
    required this.onSelected,
  });

  final String selected;
  final Color accent;
  final Color accentSoft;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: categoryIconChoices.length,
        itemBuilder: (context, index) {
          final key = categoryIconChoices[index];
          final isSelected = key == selected;
          return InkWell(
            onTap: () => onSelected(key),
            customBorder: const CircleBorder(),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  // 选中态直接填成语义色 + 白图标，是全屏最强的一个色块，
                  // 在 60 个格子里一眼能找到「我选的是哪个」。
                  color: isSelected ? accent : accentSoft.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  categoryIcon(key),
                  size: 21,
                  color: isSelected ? Colors.white : AppColors.muted,
                ),
              ),
            ),
          );
        },
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '在记账时可选',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value ? '关闭后不影响历史账单' : '已停用，记账时不再出现',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
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
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          disabledBackgroundColor: AppColors.line,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
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
    final enabled = onTap != null;
    return Material(
      color: AppColors.expenseSoft,
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
              color: enabled ? AppColors.expense : AppColors.inactive,
            ),
          ),
        ),
      ),
    );
  }
}
