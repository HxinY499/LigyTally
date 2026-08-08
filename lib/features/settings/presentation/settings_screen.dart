import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/update/update_controller.dart';
import '../../../core/utils/category_icons.dart';
import '../../ledger/application/providers.dart';

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
      if (mounted) _showMessage('备份失败：$error');
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
        if (mounted) _showMessage('数据恢复完成');
      }
    } catch (error) {
      if (mounted) _showMessage('恢复失败，请检查文件和密码：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
            child: Text(
              '设置',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('分类管理'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const CategoryManagementScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                const ListTile(
                  leading: Icon(Icons.currency_yen_rounded),
                  title: Text('默认货币'),
                  trailing: Text('人民币'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  enabled: !_busy,
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('导出完整备份'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _exportBackup,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  enabled: !_busy,
                  leading: const Icon(Icons.settings_backup_restore_rounded),
                  title: const Text('从备份恢复'),
                  trailing: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: _restoreBackup,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Card(child: _AboutTile()),
        ],
      ),
    );
  }
}

/// 关于卡片：显示当前版本并提供手动检查更新。
///
/// 版本号从原生 PackageInfo 读，不再硬编码——之前写死的
/// 「版本 1.0.0」在发布 1.0.1 后就不准了。
class _AboutTile extends ConsumerStatefulWidget {
  const _AboutTile();

  @override
  ConsumerState<_AboutTile> createState() => _AboutTileState();
}

class _AboutTileState extends ConsumerState<_AboutTile> {
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(updateControllerProvider);
    final pending = updateState.phase == UpdatePhase.available
        ? updateState.info
        : null;

    return ListTile(
      leading: const Icon(Icons.info_outline_rounded),
      title: const Text('Ligy Tally'),
      subtitle: Text(
        _version == null
            ? '正在读取版本…'
            : pending != null
            ? '版本 $_version · 可更新至 v${pending.version}'
            : '版本 $_version',
      ),
      trailing: _checking || updateState.isBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          // 已发现新版时按钮直接变成「立即更新」，
          // 不必回到首页等 SnackBar 再出现一次。
          : pending != null
          ? FilledButton(
              onPressed: () => ref
                  .read(updateControllerProvider.notifier)
                  .downloadAndInstall(),
              child: const Text('立即更新'),
            )
          : TextButton(
              onPressed: _checkUpdate,
              child: const Text('检查更新'),
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
    extends ConsumerState<CategoryManagementScreen> {
  int _kind = 0;
  List<CategoryEntry> _categories = const [];
  bool _busy = false;

  Future<void> _exportConfig() async {
    setState(() => _busy = true);
    try {
      await ref.read(categoryConfigServiceProvider).exportAndShare();
    } catch (error) {
      if (mounted) _showMessage('导出分类配置失败：$error');
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
        if (mounted) _showMessage('分类配置已导入');
      }
    } catch (error) {
      if (mounted) _showMessage('导入分类配置失败：$error');
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
        _showMessage('分类已删除');
        return;
      case CategoryDeleteResult.inUse:
        _showMessage('该分类已被历史账单使用，不能删除，可以将它停用');
        return;
      case CategoryDeleteResult.lastRoot:
        _showMessage('收入和支出至少各保留一个可用的一级分类');
        return;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      appBar: AppBar(
        title: const Text('分类管理'),
        actions: [
          PopupMenuButton<String>(
            enabled: !_busy,
            tooltip: '分类配置',
            icon: const Icon(Icons.import_export_rounded),
            onSelected: (value) {
              if (value == 'export') _exportConfig();
              if (value == 'import') _importConfig();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export', child: Text('导出分类配置')),
              PopupMenuItem(value: 'import', child: Text('导入并替换配置')),
            ],
          ),
          IconButton(
            onPressed: _busy ? null : _addCategory,
            tooltip: '新建分类',
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('支出分类')),
                  ButtonSegment(value: 1, label: Text('收入分类')),
                ],
                selected: {_kind},
                onSelectionChanged: (values) {
                  setState(() => _kind = values.first);
                },
              ),
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
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: category.isActive,
                                onChanged: (value) => database
                                    .setCategoryActive(category.id, value),
                              ),
                              IconButton(
                                onPressed: () => _deleteCategory(category),
                                tooltip: '删除分类',
                                icon: const Icon(Icons.delete_outline_rounded),
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
    );
  }
}
