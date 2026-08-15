import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/preferences/money_grouped.dart';
import '../../../core/preferences/quick_tally_mode.dart';
import '../../../core/storage/storage_usage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/update/update_controller.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/providers.dart';
import 'appearance_screen.dart';
import 'category_management_screen.dart';
import 'csv_export_sheet.dart';
import 'settings_widgets.dart';
import 'storage_images_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.active = true});

  /// 当前是否停在设置 tab。
  ///
  /// 底栏用 PageView，三页都挂在树上。占用空间若只算一次，记完账再滑过来
  /// 仍是旧数字。切到这一页时重新扫盘。
  final bool active;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      ref.read(storageUsageProvider.notifier).refresh();
    }
  }

  Future<String?> _askPassword(String title) =>
      showAppPasswordDialog(context, title: title);

  Future<void> _exportCsv() async {
    final preset = await showCsvExportSheet(context);
    if (preset == null || !mounted) return;
    final now = DateTime.now();
    final LedgerDateRange? range;
    switch (preset) {
      case CsvExportPreset.month:
        range = monthRange(now);
      case CsvExportPreset.year:
        range = yearRange(now);
      case CsvExportPreset.all:
        range = null;
      case CsvExportPreset.custom:
        final picked = await showAppDateRangePicker(
          context,
          initial: monthRange(now),
        );
        if (picked == null || !mounted) return;
        range = picked;
    }
    setState(() => _busy = true);
    try {
      final count = await ref
          .read(csvExportServiceProvider)
          .exportAndShare(range);
      if (!mounted) return;
      if (count == 0) {
        _showMessage('没有账单可导出');
      }
    } catch (error) {
      if (mounted) _showMessage('导出失败：$error', level: AppToastLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      // 与密码弹窗同一套视觉，别让同一条流程里出现两种长相的弹窗。
      final confirmed = await showAppConfirmDialog(
        context,
        message:
            '备份包含 ${preview.transactionCount} 笔账单和 '
            '${preview.imageCount} 张图片'
            '${preview.categoryIconCount > 0 ? '、${preview.categoryIconCount} 个自定义分类图标' : ''}。'
            '恢复后当前数据将被替换。',
        confirmLabel: '恢复',
      );
      if (confirmed) {
        await service.restore(file, password: password);
        ref.invalidate(storageUsageProvider);
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

  Future<void> _openStorageImages() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const StorageImagesScreen()),
    );
    if (mounted) ref.read(storageUsageProvider.notifier).refresh();
  }

  /// 占用空间行：右侧合计，副标题拆开图片和数据库。
  ///
  /// 扫盘失败只说「无法计算」，不把路径或异常原文铺到设置列表里。
  /// 整行可点进账单图库，回来后重算体积。
  SettingsItem _storageItem() {
    final usage = ref.watch(storageUsageProvider);
    return usage.when(
      loading: () => SettingsItem(
        icon: FLucideIcons.hardDrive,
        title: '占用空间',
        showChevron: true,
        onTap: _openStorageImages,
        trailing: const RowSpinner(),
      ),
      error: (_, _) => SettingsItem(
        icon: FLucideIcons.hardDrive,
        title: '占用空间',
        subtitle: '无法计算',
        showChevron: true,
        onTap: _openStorageImages,
      ),
      data: (value) => SettingsItem(
        icon: FLucideIcons.hardDrive,
        title: '占用空间',
        subtitle:
            '图片 ${formatStorageBytes(value.mediaBytes)}'
            ' · 数据 ${formatStorageBytes(value.databaseBytes)}',
        value: formatStorageBytes(value.totalBytes),
        showChevron: true,
        onTap: _openStorageImages,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageHeader(
      title: '设置',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          sliver: SliverList.list(
            children: [
              const SectionLabel('偏好'),
              SettingsCard(
                children: [
                  SettingsItem(
                    icon: FLucideIcons.zap,
                    title: '快速记账模式',
                    subtitle: '打开应用后直接进入记账页',
                    trailing: TrailingSwitch(
                      value: ref.watch(quickTallyModeProvider),
                      onChange: (value) => ref
                          .read(quickTallyModeProvider.notifier)
                          .setEnabled(value),
                    ),
                  ),
                  SettingsItem(
                    icon: FLucideIcons.hash,
                    title: '金额千分位',
                    trailing: TrailingSwitch(
                      value: ref.watch(moneyGroupedProvider),
                      onChange: (value) => ref
                          .read(moneyGroupedProvider.notifier)
                          .setGrouped(value),
                    ),
                  ),
                  // 外观是唯一收进二级页的一组：这几项互相影响，
                  // 摊在这里只能六个浮层各看各的，收进去才能共用一张样张。
                  SettingsItem(
                    icon: FLucideIcons.paintbrush,
                    title: '外观',
                    subtitle: '深浅、主题色、圆角、版式',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const AppearanceScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const SectionLabel('数据'),
              SettingsCard(
                children: [
                  // 分类管理会改数据、带确认弹窗，和导出/备份是同一类操作。
                  // 之前它挤在一堆开关中间，层级不对等。
                  SettingsItem(
                    icon: FLucideIcons.tags,
                    title: '分类管理',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const CategoryManagementScreen(),
                      ),
                    ),
                  ),
                  SettingsItem(
                    icon: FLucideIcons.fileSpreadsheet,
                    title: '导出 CSV',
                    showChevron: !_busy,
                    onTap: _busy ? null : _exportCsv,
                  ),
                  SettingsItem(
                    icon: FLucideIcons.upload,
                    title: '导出完整备份',
                    showChevron: !_busy,
                    onTap: _busy ? null : _exportBackup,
                  ),
                  SettingsItem(
                    icon: FLucideIcons.download,
                    title: '导入完整备份',
                    showChevron: !_busy,
                    trailing: _busy ? const RowSpinner() : null,
                    onTap: _busy ? null : _restoreBackup,
                  ),
                  _storageItem(),
                ],
              ),
              const SizedBox(height: 18),
              const SectionLabel('关于'),
              const _AboutCard(),
            ],
          ),
        ),
      ],
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

    return SettingsCard(
      children: [
        _BrandRow(version: _version, hasUpdate: pending != null),
        SettingsItem(
          icon: pending != null
              ? FLucideIcons.cloudDownload
              : FLucideIcons.refreshCw,
          title: pending != null ? '更新到 v${pending.version}' : '检查更新',
          subtitle: busySubtitle,
          accent: pending != null,
          trailing: busy ? const RowSpinner() : null,
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
    final colors = context.colors;
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
                color: colors.primarySoft,
                borderRadius: context.radii.chipAll,
              ),
              alignment: Alignment.center,
              child: Image.asset(
                'assets/branding/ligytally-mark.png',
                width: 19,
                height: 19,
                // 图标是单色透明底，直接染成品牌蓝
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Ligy Tally',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    version == null ? '正在读取版本…' : '版本 $version',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.inactive,
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
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: colors.primary,
          height: 1.1,
        ),
      ),
    );
  }
}
