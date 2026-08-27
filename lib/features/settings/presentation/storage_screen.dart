import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/media/image_storage.dart';
import '../../../core/storage/storage_usage.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../ledger/application/providers.dart';
import 'settings_widgets.dart';
import 'storage_images_screen.dart';

/// 正在进行的清理动作。同一时刻只允许一个，否则两条清理会互相删对方正在
/// 统计的文件。
enum _StorageTask { cache, orphans, vacuum, recompress }

/// 占用空间：账本占了多少、哪些能一键腾出来、怎么在不删图的前提下变小。
///
/// 独立成页而不是塞进设置行：这里有四个会改磁盘的动作，每个都要交代清楚
/// 「删的是什么、账单会不会没」，一行副标题写不下。
class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  _StorageTask? _task;
  String? _progress;

  bool get _busy => _task != null;

  Future<void> _run(
    _StorageTask task,
    Future<String> Function() action, {
    String? confirmMessage,
    bool destructive = true,
  }) async {
    if (_busy) return;
    if (confirmMessage != null) {
      final confirmed = await showAppConfirmDialog(
        context,
        message: confirmMessage,
        confirmLabel: '继续',
        accent: destructive ? null : context.colors.primary,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _task = task);
    try {
      final message = await action();
      if (!mounted) return;
      showAppToast(context, message: message, level: AppToastLevel.success);
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          message: '操作失败：$error',
          level: AppToastLevel.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _task = null;
          _progress = null;
        });
        await ref.read(storageUsageProvider.notifier).refresh();
      }
    }
  }

  Future<void> _clearCache() => _run(
    _StorageTask.cache,
    () async {
      final freed = await ref.read(storageUsageServiceProvider).clearCache();
      return freed == 0 ? '没有可清理的缓存' : '已清理 ${formatStorageBytes(freed)}';
    },
    confirmMessage:
        '清理更新安装包，以及导出后留在本机的备份、CSV、表格和分类配置副本。'
        '账单、图片和分类都不受影响。',
    destructive: false,
  );

  Future<void> _clearOrphans() => _run(
    _StorageTask.orphans,
    () async {
      final freed = await ref.read(storageUsageServiceProvider).clearOrphans();
      return freed == 0 ? '没有无主文件' : '已清理 ${formatStorageBytes(freed)}';
    },
    confirmMessage:
        '删除这些不属于任何账单的图片文件。所有账单和它们的图片都会保留，'
        '但被删掉的文件无法恢复。',
  );

  Future<void> _compactDatabase() => _run(_StorageTask.vacuum, () async {
    final freed = await ref.read(storageUsageServiceProvider).compactDatabase();
    return freed == 0 ? '数据库已经是最紧凑的' : '已回收 ${formatStorageBytes(freed)}';
  });

  Future<void> _recompress() => _run(
    _StorageTask.recompress,
    () async {
      final result = await ref
          .read(ledgerServiceProvider)
          .recompressLargeImages(
            onProgress: (done, total) {
              if (!mounted || total == 0) return;
              setState(() => _progress = '$done / $total');
            },
          );
      if (result.candidateCount == 0) return '所有图片都已经是压缩后的尺寸';
      if (result.compressedCount == 0) return '这些图片已经没有压缩空间了';
      return '已压缩 ${result.compressedCount} 张，'
          '省下 ${formatStorageBytes(result.freedBytes)}';
    },
    confirmMessage:
        '把尺寸偏大的账单图重新压到 $kRecompressMaxSide 像素以内。'
        '账单和图片都会保留，但画质会下降且无法还原。',
  );

  Future<void> _openImages() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const StorageImagesScreen()),
    );
    if (mounted) await ref.read(storageUsageProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(storageUsageProvider);
    return AppTopBar(
      title: '占用空间',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          sliver: SliverList.list(
            children: usage.when(
              loading: () => const [_StorageMessage('正在计算…')],
              error: (_, _) => const [_StorageMessage('无法读取占用空间')],
              data: _body,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _body(StorageUsage usage) {
    return [
      _UsageOverview(usage: usage),
      const SizedBox(height: 18),
      const SectionLabel('账本数据'),
      SettingsCard(
        children: [
          SettingsItem(
            icon: FLucideIcons.images,
            title: '账单图片',
            subtitle: usage.imageCount == 0
                ? '还没有加过图片'
                : '${usage.imageCount} 张，可逐张浏览和删除',
            value: formatStorageBytes(usage.imageBytes),
            showChevron: true,
            onTap: _busy ? null : _openImages,
          ),
          SettingsItem(
            icon: FLucideIcons.brush,
            title: '分类图标',
            value: formatStorageBytes(usage.categoryIconBytes),
          ),
          SettingsItem(
            icon: FLucideIcons.database,
            title: '数据库',
            subtitle: '账单、分类和备注本身',
            value: formatStorageBytes(usage.databaseBytes),
          ),
        ],
      ),
      const SizedBox(height: 18),
      const SectionLabel('可清理'),
      SettingsCard(
        children: [
          SettingsItem(
            icon: FLucideIcons.fileArchive,
            title: '缓存',
            subtitle: '更新安装包、导出后留下的备份、CSV 和表格副本',
            value: formatStorageBytes(usage.cacheBytes),
            trailing: _task == _StorageTask.cache ? const RowSpinner() : null,
            showChevron: !_busy && usage.cacheBytes > 0,
            onTap: _busy || usage.cacheBytes == 0 ? null : _clearCache,
          ),
          SettingsItem(
            icon: FLucideIcons.folderX,
            title: '无主文件',
            subtitle: usage.orphanFileCount == 0
                ? '没有掉队的图片文件'
                : '${usage.orphanFileCount} 个文件不属于任何账单',
            value: formatStorageBytes(usage.orphanBytes),
            trailing: _task == _StorageTask.orphans ? const RowSpinner() : null,
            showChevron: !_busy && usage.orphanFileCount > 0,
            onTap: _busy || usage.orphanFileCount == 0 ? null : _clearOrphans,
          ),
          SettingsItem(
            icon: FLucideIcons.minimize2,
            title: '压缩数据库',
            subtitle: '回收删除账单后留下的空洞',
            trailing: _task == _StorageTask.vacuum ? const RowSpinner() : null,
            showChevron: !_busy,
            onTap: _busy ? null : _compactDatabase,
          ),
        ],
      ),
      const SizedBox(height: 18),
      const SectionLabel('不删图也能变小'),
      SettingsCard(
        children: [
          SettingsItem(
            icon: FLucideIcons.imageDown,
            title: '压缩已有图片',
            subtitle: _task == _StorageTask.recompress && _progress != null
                ? '正在压缩 $_progress'
                : '把大图压到 $kRecompressMaxSide 像素以内，账单和图片都保留',
            trailing: _task == _StorageTask.recompress
                ? const RowSpinner()
                : null,
            showChevron: !_busy,
            onTap: _busy ? null : _recompress,
          ),
        ],
      ),
      const SizedBox(height: 14),
      const _StorageFootnote(),
    ];
  }
}

/// 顶部总览：合计 + 分段占比条 + 图例。
class _UsageOverview extends StatelessWidget {
  const _UsageOverview({required this.usage});

  final StorageUsage usage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // 蓝系是账本本体，灰是缓存，红是该清掉的——不用四种彩色，
    // 让「哪些删得掉」一眼能分出来。
    final segments = <({String label, int bytes, Color color})>[
      (label: '图片', bytes: usage.mediaBytes, color: colors.primary),
      (
        label: '数据',
        bytes: usage.databaseBytes,
        color: colors.primary.withValues(alpha: 0.42),
      ),
      (label: '缓存', bytes: usage.cacheBytes, color: colors.inactive),
      // 「无主」是需要清理的异常占用，走 danger 而不是支出色。
      (label: '无主', bytes: usage.orphanBytes, color: colors.danger),
    ];
    final visible = [
      for (final segment in segments)
        if (segment.bytes > 0) segment,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: context.radii.cardShape(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatStorageBytes(usage.totalBytes),
            // 不是金额，但同样是「一屏里最大的那个数」，字距该跟着字号收紧，
            // 所以复用同一条规则。
            style: AppText.money(
              AppText.moneyLg,
              color: colors.ink,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            usage.reclaimableBytes > 0
                ? '其中 ${formatStorageBytes(usage.reclaimableBytes)} 可以直接清掉'
                : '没有可以直接清掉的部分',
            style: TextStyle(fontSize: 12.5, color: colors.inactive),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: visible.isEmpty
                  ? ColoredBox(color: colors.fill)
                  : Row(
                      children: [
                        for (var i = 0; i < visible.length; i++)
                          Expanded(
                            // 比例小到不足 1% 的段仍要看得见，否则图例里有
                            // 这一项、条上却找不到，会让人以为画错了。
                            flex: _flexOf(visible[i].bytes, usage.totalBytes),
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: i == visible.length - 1 ? 0 : 2,
                              ),
                              child: ColoredBox(color: visible[i].color),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          if (visible.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final segment in visible)
                  _Legend(
                    label: segment.label,
                    value: formatStorageBytes(segment.bytes),
                    color: segment.color,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  int _flexOf(int bytes, int total) {
    if (total <= 0) return 1;
    final share = bytes * 1000 ~/ total;
    return share < 20 ? 20 : share;
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12.5, color: colors.muted)),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: colors.ink,
          ),
        ),
      ],
    );
  }
}

class _StorageFootnote extends StatelessWidget {
  const _StorageFootnote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '这里统计的是应用自己写下的文件。系统设置里看到的数字还包含安装包本身，'
        '会比这里大。',
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: context.colors.inactive,
        ),
      ),
    );
  }
}

class _StorageMessage extends StatelessWidget {
  const _StorageMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          text,
          style: TextStyle(fontSize: 13.5, color: context.colors.inactive),
        ),
      ),
    );
  }
}
