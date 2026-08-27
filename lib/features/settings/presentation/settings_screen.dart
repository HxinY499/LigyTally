import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/branding/app_brand.dart';
import '../../../core/location/location_platform.dart';
import '../../../core/location/location_service.dart';
import '../../../core/preferences/auto_location.dart';
import '../../../core/preferences/quick_tally_mode.dart';
import '../../../core/storage/storage_usage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/update/update_controller.dart';
import '../../../core/update/update_progress.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/providers.dart';
import 'appearance_screen.dart';
import 'privacy_screen.dart';
import 'category_management_screen.dart';
import 'csv_export_sheet.dart';
import 'settings_widgets.dart';
import 'storage_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.active = true});

  /// 当前是否停在设置 tab。
  ///
  /// 底栏用 PageView，四页都挂在树上。占用空间若只算一次，记完账再滑过来
  /// 仍是旧数字。切到这一页时重新扫盘。
  final bool active;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  _SettingsBusy? _busy;
  bool _locationBusy = false;

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
    final choice = await showCsvExportSheet(context);
    if (choice == null || !mounted) return;
    final now = DateTime.now();
    final LedgerDateRange? range;
    switch (choice.preset) {
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
    setState(() => _busy = _SettingsBusy.csv);
    try {
      final count = await ref
          .read(csvExportServiceProvider)
          .exportAndShare(range, includeImages: choice.includeImages);
      if (!mounted) return;
      if (count == 0) {
        _showMessage('没有账单可导出');
      }
    } catch (error) {
      if (mounted) _showMessage('导出失败：$error', level: AppToastLevel.error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _exportBackup() async {
    final password = await _askPassword('导出完整备份');
    if (password == null || !mounted) return;
    setState(() => _busy = _SettingsBusy.backup);
    try {
      await ref
          .read(backupServiceProvider)
          .exportAndShare(
            password: password,
            // 外观一起打包：用户调了半小时的配色，换机恢复后账单全在、
            // 外观全丢，这件事比少几个开关更伤。
            appearance: ref.read(appearanceProvider),
          );
    } catch (error) {
      if (mounted) _showMessage('备份失败：$error', level: AppToastLevel.error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restoreBackup() async {
    final service = ref.read(backupServiceProvider);
    final file = await service.pickBackupFile();
    if (file == null || !mounted) return;
    final password = await _askPassword('打开备份');
    if (password == null || !mounted) return;
    setState(() => _busy = _SettingsBusy.restore);
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
        final appearance = await service.restore(file, password: password);
        ref.invalidate(storageUsageProvider);
        // 恢复换掉了整个 media 目录，壁纸是同名新文件，图片缓存必须失效一次，
        // 否则屏幕上还是原来那张（见 BackupService.restore 的文档）。
        await ref.read(imageStorageProvider).evictWallpaperCache();
        // 老版本的包（v4 及以前）不带外观，此时保持当前外观不动——
        // 那正是「这个包里没有外观信息」的正确处理。
        if (appearance != null) {
          ref.read(appearanceProvider.notifier).restoreFromConfig(appearance);
        }
        if (mounted) _showMessage('数据恢复完成', level: AppToastLevel.success);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('恢复失败，请检查文件和密码：$error', level: AppToastLevel.error);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _setAutoLocation(bool enabled) async {
    if (!enabled) {
      await ref.read(autoLocationProvider.notifier).setEnabled(false);
      return;
    }
    if (_locationBusy) return;
    setState(() => _locationBusy = true);
    try {
      final service = ref.read(locationServiceProvider);
      if (!await service.isServiceEnabled()) {
        if (!mounted) return;
        _showMessage('请先打开系统定位', level: AppToastLevel.error);
        await service.openLocationSettings();
        return;
      }
      var permission = await service.checkPermission();
      if (permission != DeviceLocationPermission.granted) {
        permission = await service.requestPermission();
      }
      if (!mounted) return;
      if (permission == DeviceLocationPermission.granted) {
        await ref.read(autoLocationProvider.notifier).setEnabled(true);
        return;
      }
      if (permission == DeviceLocationPermission.deniedForever) {
        _showMessage('定位权限被关闭，请在系统设置中开启', level: AppToastLevel.error);
        await service.openAppSettings();
      } else {
        _showMessage('需要定位权限才能自动记录位置', level: AppToastLevel.error);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('无法开启自动定位：$error', level: AppToastLevel.error);
      }
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }

  void _showMessage(
    String message, {
    AppToastLevel level = AppToastLevel.info,
  }) {
    showAppToast(context, message: message, level: level);
  }

  Future<void> _openStorage() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const StorageScreen()));
    if (mounted) ref.read(storageUsageProvider.notifier).refresh();
  }

  /// 占用空间行：右侧合计，副标题优先报「有多少能直接清掉」。
  ///
  /// 副标题不再拆「图片 · 数据」——那是进去之后才需要的明细；在设置列表里
  /// 唯一值得占一行的信息是「要不要点进去」，所以有可清理的就报数量。
  /// 扫盘失败只说「无法计算」，不把路径或异常原文铺到设置列表里。
  SettingsItem _storageItem() {
    final usage = ref.watch(storageUsageProvider);
    return usage.when(
      loading: () => SettingsItem(
        icon: FLucideIcons.hardDrive,
        title: '占用空间',
        showChevron: true,
        onTap: _openStorage,
        trailing: const RowSpinner(),
      ),
      error: (_, _) => SettingsItem(
        icon: FLucideIcons.hardDrive,
        title: '占用空间',
        subtitle: '无法计算',
        showChevron: true,
        onTap: _openStorage,
      ),
      data: (value) => SettingsItem(
        icon: FLucideIcons.hardDrive,
        title: '占用空间',
        subtitle: value.reclaimableBytes > 0
            ? '${formatStorageBytes(value.reclaimableBytes)} 可清理'
            : '图片 ${formatStorageBytes(value.mediaBytes)}'
                  ' · 数据 ${formatStorageBytes(value.databaseBytes)}',
        value: formatStorageBytes(value.totalBytes),
        showChevron: true,
        onTap: _openStorage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageHeader(
      title: '设置',
      slivers: [
        SliverPadding(
          // MediaQuery 的底部留白在贴底档下是 0（那块由底栏自己吃掉），
          // 悬浮档下是胶囊盖住的高度，见 `home_shell.dart`。
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            100 + MediaQuery.paddingOf(context).bottom,
          ),
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
                    icon: FLucideIcons.mapPin,
                    title: '记账时自动记录位置',
                    subtitle: '仅新建今天的账单时获取，可随时关掉',
                    trailing: _locationBusy
                        ? const RowSpinner()
                        : TrailingSwitch(
                            value: ref.watch(autoLocationProvider),
                            onChange: (value) {
                              unawaited(_setAutoLocation(value));
                            },
                          ),
                  ),
                  // 外观是唯一收进二级页的一组：那十几项互相影响，
                  // 摊在这里只能各看各的，收进去才能共用一张样张。
                  //
                  // 「金额千分位」原本摊在这一行下面，现在也收进去了：它和
                  // 「数字等宽」是同一件事的两半（金额怎么排版），隔着一层
                  // 页面分开放，改完一个还要退出来找另一个。
                  SettingsItem(
                    icon: FLucideIcons.paintbrush,
                    title: '外观',
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
                    showChevron: _busy == null,
                    trailing: _busy == _SettingsBusy.csv
                        ? const RowSpinner()
                        : null,
                    onTap: _busy != null ? null : _exportCsv,
                  ),
                  SettingsItem(
                    icon: FLucideIcons.upload,
                    title: '导出完整备份',
                    showChevron: _busy == null,
                    trailing: _busy == _SettingsBusy.backup
                        ? const RowSpinner()
                        : null,
                    onTap: _busy != null ? null : _exportBackup,
                  ),
                  SettingsItem(
                    icon: FLucideIcons.download,
                    title: '导入完整备份',
                    showChevron: _busy == null,
                    trailing: _busy == _SettingsBusy.restore
                        ? const RowSpinner()
                        : null,
                    onTap: _busy != null ? null : _restoreBackup,
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
    final outcome = await ref
        .read(updateControllerProvider.notifier)
        .checkManually();
    if (!mounted) return;
    setState(() => _checking = false);
    if (outcome.isSilent) return;
    // 检查失败走 error 级别：查不到和「已是最新」是两回事，
    // 图标和配色也得跟着分开，否则用户仍会把失败读成结论。
    showAppToast(
      context,
      message: outcome.message,
      level: outcome.failed ? AppToastLevel.error : AppToastLevel.info,
    );
  }

  void _openPrivacy() {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const PrivacyScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(updateControllerProvider);
    final updateInfo = updateState.info;
    final offeringUpdate =
        updateInfo != null &&
        updateState.phase != UpdatePhase.idle &&
        updateState.phase != UpdatePhase.failed;
    final busy = _checking || updateState.isBusy;
    final downloading = updateState.isBusy;

    // 下载中把进度写进副标题，让这一行自己能交代状态
    final String? busySubtitle;
    if (downloading) {
      busySubtitle = updateDownloadLabel(updateState);
    } else if (_checking) {
      busySubtitle = '正在检查…';
    } else if (offeringUpdate && updateInfo.apkSize > 0) {
      busySubtitle =
          '安装包 ${(updateInfo.apkSize / 1024 / 1024).toStringAsFixed(0)}MB';
    } else {
      busySubtitle = null;
    }

    final Widget? trailing;
    if (downloading) {
      trailing = SizedBox(
        width: 48,
        child: UpdateDownloadTrack(
          fraction: updateState.phase == UpdatePhase.verifying
              ? null
              : updateState.progress?.fraction,
          height: 6,
        ),
      );
    } else if (_checking) {
      trailing = const RowSpinner();
    } else {
      trailing = null;
    }

    return SettingsCard(
      children: [
        _BrandRow(version: _version, hasUpdate: offeringUpdate),
        // 政策正文和备案号都收进二级页：合规信息必须能看到，但不该和
        // 「检查更新」抢同一层——那是用户真会点的那行。
        SettingsItem(
          icon: FLucideIcons.shieldCheck,
          title: '隐私与备案',
          showChevron: true,
          onTap: _openPrivacy,
        ),
        SettingsItem(
          icon: offeringUpdate
              ? FLucideIcons.cloudDownload
              : FLucideIcons.refreshCw,
          title: offeringUpdate ? '更新到 v${updateInfo.version}' : '检查更新',
          subtitle: busySubtitle,
          accent: offeringUpdate,
          trailing: trailing,
          showChevron: !busy,
          onTap: busy
              ? null
              : offeringUpdate
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
                    kAppDisplayName,
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

/// 设置页同一时刻只跑一种数据操作，转圈落在被点的那一行。
enum _SettingsBusy { csv, backup, restore }
