import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/preferences/app_icon.dart';
import '../../../core/preferences/category_picker_layout.dart';
import '../../../core/preferences/money_grouped.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/update/update_controller.dart';
import '../../../core/utils/category_icons.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/providers.dart';
import 'app_icon_picker_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  Future<String?> _askPassword(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '密码',
            hintText: '留空表示不加密',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _exportBackup() async {
    final password = await _askPassword('导出完整备份');
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(backupServiceProvider).exportAndShare(password: password);
    } catch (error) {
      if (mounted) _showMessage('备份失败：$error', level: AppToastLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final service = ref.read(backupServiceProvider);
    final file = await service.pickBackupFile();
    if (file == null || !mounted) return;
    final password = await _askPassword('打开备份');
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final preview = await service.inspect(file, password: password);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('覆盖当前数据'),
          content: Text(
            '备份包含 ${preview.transactionCount} 笔账单和 '
            '${preview.imageCount} 张图片。恢复后当前数据将被替换。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await service.restore(file, password: password);
        if (mounted) _showMessage('数据恢复完成', level: AppToastLevel.success);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('恢复失败，请检查文件和密码：$error', level: AppToastLevel.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(
    String message, {
    AppToastLevel level = AppToastLevel.info,
  }) {
    showAppToast(context, message: message, level: level);
  }

  Future<void> _pickAppIcon() async {
    final current = ref.read(appIconProvider);
    final picked = await showAppIconPickerSheet(context, current: current);
    if (picked == null || picked == current || !mounted) return;
    try {
      await ref.read(appIconProvider.notifier).setStyle(picked);
      if (mounted) {
        _showMessage('图标已切换，桌面可能需要几秒刷新');
      }
    } catch (error) {
      if (mounted) _showMessage('切换失败：$error', level: AppToastLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: AppPageHeader(
        title: '设置',
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: [
            const _SectionLabel('偏好'),
            _SettingsCard(
              children: [
                _SettingsItem(
                  icon: FLucideIcons.tags,
                  title: '分类管理',
                  subtitle: '新增、停用或删除收支分类',
                  showChevron: true,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const CategoryManagementScreen(),
                    ),
                  ),
                ),
                _SettingsItem(
                  icon: FLucideIcons.layoutGrid,
                  title: '分类选择样式',
                  trailing: _LayoutToggle(
                    value: ref.watch(categoryPickerLayoutProvider),
                    onChanged: (value) => ref
                        .read(categoryPickerLayoutProvider.notifier)
                        .setLayout(value),
                  ),
                ),
                _SettingsItem(
                  icon: FLucideIcons.smartphone,
                  title: '应用图标',
                  trailing: _AppIconPreview(
                    style: ref.watch(appIconProvider),
                  ),
                  showChevron: true,
                  onTap: _pickAppIcon,
                ),
                _SettingsItem(
                  icon: FLucideIcons.hash,
                  title: '金额千分位',
                  trailing: _TrailingSwitch(
                    value: ref.watch(moneyGroupedProvider),
                    onChange: (value) => ref
                        .read(moneyGroupedProvider.notifier)
                        .setGrouped(value),
                  ),
                ),
                const _SettingsItem(
                  icon: FLucideIcons.banknote,
                  title: '默认货币',
                  value: '人民币',
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _SectionLabel('数据备份'),
            _SettingsCard(
              children: [
                _SettingsItem(
                  icon: FLucideIcons.upload,
                  title: '导出数据',
                  subtitle: '打包账单与图片，可设密码',
                  showChevron: !_busy,
                  onTap: _busy ? null : _exportBackup,
                ),
                _SettingsItem(
                  icon: FLucideIcons.download,
                  title: '导入数据',
                  subtitle: '从备份文件恢复，覆盖当前数据',
                  showChevron: !_busy,
                  trailing: _busy ? const _RowSpinner() : null,
                  onTap: _busy ? null : _restoreBackup,
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _SectionLabel('关于'),
            const _AboutCard(),
          ],
        ),
      ),
    );
  }
}

/// 关于卡片：品牌行 + 检查更新行。
///
/// 版本号从原生 PackageInfo 读，不再硬编码——之前写死的
/// 「版本 1.0.0」在发布 1.0.1 后就不准了。
class _AboutCard extends ConsumerStatefulWidget {
  const _AboutCard();

  @override
  ConsumerState<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends ConsumerState<_AboutCard> {
  String? _version;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final version = await ref.read(updateServiceProvider).currentVersion();
    if (!mounted) return;
    setState(() => _version = version?.toString());
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    final message = await ref
        .read(updateControllerProvider.notifier)
        .checkManually();
    if (!mounted) return;
    setState(() => _checking = false);
    if (message.isEmpty) return;
    showAppToast(context, message: message);
  }

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(updateControllerProvider);
    final pending = updateState.phase == UpdatePhase.available
        ? updateState.info
        : null;
    final busy = _checking || updateState.isBusy;

    // 下载中把进度写进副标题，让这一行自己能交代状态
    final fraction = updateState.progress?.fraction;
    final String? busySubtitle;
    if (updateState.phase == UpdatePhase.verifying) {
      busySubtitle = '正在校验安装包…';
    } else if (updateState.phase == UpdatePhase.downloading) {
      busySubtitle = fraction == null
          ? '正在下载…'
          : '正在下载 ${(fraction * 100).toStringAsFixed(0)}%';
    } else if (_checking) {
      busySubtitle = '正在检查…';
    } else if (pending != null && pending.apkSize > 0) {
      busySubtitle =
          '安装包 ${(pending.apkSize / 1024 / 1024).toStringAsFixed(0)}MB';
    } else {
      busySubtitle = null;
    }

    return _SettingsCard(
      children: [
        _BrandRow(version: _version, hasUpdate: pending != null),
        _SettingsItem(
          icon: pending != null
              ? FLucideIcons.cloudDownload
              : FLucideIcons.refreshCw,
          title: pending != null ? '更新到 v${pending.version}' : '检查更新',
          subtitle: busySubtitle,
          accent: pending != null,
          trailing: busy ? const _RowSpinner() : null,
          showChevron: !busy,
          onTap: busy
              ? null
              : pending != null
              ? () => ref
                    .read(updateControllerProvider.notifier)
                    .downloadAndInstall()
              : _checkUpdate,
        ),
      ],
    );
  }
}

/// 关于卡片顶部的品牌行：应用图标 + 名称 + 版本号。
///
/// 图标沿用普通行的 32×32 槽位，让品牌名和下方「检查更新」的标题
/// 落在同一条左对齐线上（也正好对上分割线的 indent）。
class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.version, required this.hasUpdate});

  final String? version;
  final bool hasUpdate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Image.asset(
                'assets/branding/ligytally-mark.png',
                width: 19,
                height: 19,
                // 图标是单色透明底，直接染成品牌蓝
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Ligy Tally',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    version == null ? '正在读取版本…' : '版本 $version',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inactive,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (hasUpdate) ...[const SizedBox(width: 12), const _Badge('新版本')],
          ],
        ),
      ),
    );
  }
}

/// 「有新版本」这类状态胶囊。
class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
          height: 1.1,
        ),
      ),
    );
  }
}

/// 分组小标题：卡片外的灰色说明文字。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.inactive,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// 行内小转圈：与 chevron 同宽，替换时不会让右侧跳动。
class _RowSpinner extends StatelessWidget {
  const _RowSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

/// 设置页卡片容器：白底、大圆角、组内发丝分割线。
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            // 分割线从标题文字起始处开始（左 16 + 图标 32 + 间距 12），
            // 不切到左侧图标，视觉上更整齐。
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 60,
                color: Color(0xFFEEF2F0),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 设置页列表行：左侧图标 + 标题（可带副标题），右侧值/ 控件 / chevron。
///
/// 右侧统一收在 16 的内边距上——chevron、开关、值文字的右边缘对齐同一条线，
/// 所以带chevron 的行不再额外撑出 8px。
class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.showChevron = false,
    this.accent = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// 右侧灰色只读值（如「人民币」）。
  final String? value;
  final Widget? trailing;
  final bool showChevron;

  /// true 时标题与图标走品牌色，用于「有新版本可更新」这类强引导。
  final bool accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // minHeight 40：让「只有标题」「标题+副标题」「带开关」三种行
        // 的高度都落在 64，否则开关（39 高）会把那一行顶得比邻居高。
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent ? AppColors.primary : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 17,
                  color: accent ? Colors.white : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: accent ? AppColors.primary : AppColors.ink,
                        height: 1.25,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inactive,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                Text(
                  value!,
                  style: const TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              if (showChevron) ...[
                const SizedBox(width: 6),
                const Icon(
                  FLucideIcons.chevronRight,
                  size: 18,
                  color: Color(0xFFC2CBC6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 行尾开关：把 forui 开关的隐形留白补掉，让轨道右边缘和chevron 对齐。
///
/// [AppSwitch] 内部 FLabel 左右各留 8，CupertinoSwitch 的 59×39 画布相对
/// 51×31 的轨道又各多出 4 —— 右侧共空12px，不修正就会比其它行内缩。
class _TrailingSwitch extends StatelessWidget {
  const _TrailingSwitch({required this.value, required this.onChange});

  final bool value;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(12, 0),
      child: AppSwitch(value: value, onChange: onChange),
    );
  }
}

/// 应用图标行的右侧小缩略图：让用户在设置列表里就能看到当前选中的图标样式，
/// 不需要文字说明。尺寸和其它行右侧的开关/胶囊控件视觉重量对齐。
class _AppIconPreview extends StatelessWidget {
  const _AppIconPreview({required this.style});

  final AppIconStyle style;

  @override
  Widget build(BuildContext context) {
    final asset = style == AppIconStyle.dark
        ? 'assets/branding/app-icon-dark.png'
        : 'assets/branding/app-icon-light.png';
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(asset, fit: BoxFit.cover),
    );
  }
}

/// 分类选择样式的紧凑二态切换器：灰底轨道 + 白色滑块（列表 / 网格）。
///
/// 做成有可见边界的胶囊，右边缘能和同列的开关轨道、chevron 对齐；
/// 之前两枚裸图标按钮没有边界，看起来比其它行内缩一截。
class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({required this.value, required this.onChanged});

  final CategoryPickerLayout value;
  final ValueChanged<CategoryPickerLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F2),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LayoutIcon(
            icon: FLucideIcons.list,
            selected: value == CategoryPickerLayout.list,
            onTap: () => onChanged(CategoryPickerLayout.list),
          ),
          _LayoutIcon(
            icon: FLucideIcons.layoutGrid,
            selected: value == CategoryPickerLayout.grid,
            onTap: () => onChanged(CategoryPickerLayout.grid),
          ),
        ],
      ),
    );
  }
}

class _LayoutIcon extends StatelessWidget {
  const _LayoutIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 38,
        height: 28,
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x14000000),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 16,
          color: selected ? AppColors.primary : AppColors.inactive,
        ),
      ),
    );
  }
}

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
  List<CategoryEntry> _categories = const [];
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
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('覆盖分类配置'),
          content: Text(
            '配置包含 ${preview.parentCount} 个一级分类和 '
            '${preview.childCount} 个二级分类。现有可用分类将被替换，'
            '历史账单使用的旧分类会保留但停用。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await service.importAndReplace(path);
        if (mounted) _showMessage('分类配置已导入', level: AppToastLevel.success);
      }
    } catch (error) {
      if (mounted) _showMessage('导入分类配置失败：$error', level: AppToastLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCategory(CategoryEntry category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分类'),
        content: Text(
          category.level == 1
              ? '确定删除“${category.name}”及其全部二级分类吗？'
              : '确定删除“${category.name}”吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await ref.read(databaseProvider).deleteCategory(category.id);
    if (!mounted) return;
    switch (result) {
      case CategoryDeleteResult.deleted:
        _showMessage('分类已删除', level: AppToastLevel.success);
        return;
      case CategoryDeleteResult.inUse:
        _showMessage('该分类已被历史账单使用，不能删除，可以将它停用', level: AppToastLevel.error);
        return;
      case CategoryDeleteResult.lastRoot:
        _showMessage('收入和支出至少各保留一个可用的一级分类', level: AppToastLevel.error);
        return;
    }
  }

  void _showMessage(
    String message, {
    AppToastLevel level = AppToastLevel.info,
  }) {
    showAppToast(context, message: message, level: level);
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    String parentId = '';
    final parents = _categories
        .where((item) => item.level == 1 && item.isActive)
        .toList();
    final result = await showDialog<({String name, String? parentId})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建分类'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 12,
                decoration: const InputDecoration(labelText: '分类名称'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: parentId,
                decoration: const InputDecoration(labelText: '所属层级'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('一级分类')),
                  for (final parent in parents)
                    DropdownMenuItem(
                      value: parent.id,
                      child: Text(parent.name),
                    ),
                ],
                onChanged: (value) {
                  setDialogState(() => parentId = value ?? '');
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(context, (
                  name: name,
                  parentId: parentId.isEmpty ? null : parentId,
                ));
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    await ref
        .read(databaseProvider)
        .addCategory(
          id: const Uuid().v4(),
          kind: _kind,
          name: result.name,
          parentId: result.parentId,
        );
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
            tooltip: '新建分类',
            onTap: _busy ? null : _addCategory,
          ),
        ],
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: AppSegmentedControl<int>(
                selected: _kind,
                onChanged: (value) => setState(() => _kind = value),
                segments: const [
                  AppSegment(value: 0, label: '支出分类'),
                  AppSegment(value: 1, label: '收入分类'),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<CategoryEntry>>(
                stream: database.watchCategories(_kind, activeOnly: false),
                builder: (context, snapshot) {
                  final categories = snapshot.data;
                  if (categories == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  _categories = categories;
                  final parents = categories
                      .where((category) => category.level == 1)
                      .toList();
                  final ordered = <CategoryEntry>[
                    for (final parent in parents) ...[
                      parent,
                      ...categories.where(
                        (category) => category.parentId == parent.id,
                      ),
                    ],
                  ];
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: ordered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final category = ordered[index];
                      final isChild = category.level == 2;
                      CategoryEntry? parent;
                      if (isChild) {
                        for (final candidate in parents) {
                          if (candidate.id == category.parentId) {
                            parent = candidate;
                          }
                        }
                      }
                      return Padding(
                        padding: EdgeInsets.only(left: isChild ? 24 : 0),
                        child: AppCard(
                          child: AppTile(
                            prefix: CircleAvatar(
                              radius: isChild ? 17 : 20,
                              backgroundColor: category.isActive
                                  ? AppColors.primarySoft
                                  : AppColors.line,
                              foregroundColor: category.isActive
                                  ? AppColors.primary
                                  : AppColors.muted,
                              child: Icon(
                                categoryIcon(category.iconKey),
                                size: isChild ? 17 : 20,
                              ),
                            ),
                            title: Text(category.name),
                            subtitle: Text(
                              isChild
                                  ? '${parent?.name ?? '二级分类'} · ${category.isActive ? '启用' : '停用'}'
                                  : '一级分类 · ${category.isActive ? '启用' : '停用'}',
                            ),
                            suffix: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppSwitch(
                                  value: category.isActive,
                                  onChange: (value) => database
                                      .setCategoryActive(category.id, value),
                                ),
                                const SizedBox(width: 4),
                                AppIconButton(
                                  onPress: () => _deleteCategory(category),
                                  icon: const Icon(FLucideIcons.trash2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
