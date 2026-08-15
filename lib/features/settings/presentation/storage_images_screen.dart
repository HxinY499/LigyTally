import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/media/image_storage.dart';
import '../../../core/storage/storage_usage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/local_image.dart';
import '../../../shared/widgets/photo_viewer.dart';
import '../../ledger/application/providers.dart';

/// 图库的浏览方式。
///
/// 三种对应三个真实目的：翻找某笔账单的图（[newest]）、腾空间时先删掉最大的
/// 几张（[largest]）、看清「哪几笔账单最占地方」（[byTransaction]）。
enum _GalleryMode {
  newest('最新'),
  largest('最大'),
  byTransaction('按账单');

  const _GalleryMode(this.label);

  final String label;
}

/// 占用空间里的账单图库：浏览全部账单图，并批量删除以腾出空间。
///
/// 删的是图片，不是账单。分类图标不在这里出现。
class StorageImagesScreen extends ConsumerStatefulWidget {
  const StorageImagesScreen({super.key});

  @override
  ConsumerState<StorageImagesScreen> createState() =>
      _StorageImagesScreenState();
}

class _StorageImagesScreenState extends ConsumerState<StorageImagesScreen> {
  bool _selecting = false;
  bool _busy = false;
  _GalleryMode _mode = _GalleryMode.newest;
  final Set<String> _selected = {};
  late Stream<List<LedgerImageItem>> _images = _streamFor(_mode);

  /// 按账单分组时仍取「新的在前」，组内顺序才是自然的；组之间再按合计大小
  /// 重排（见 [_groupsOf]）——跨行汇总排序在这条 SQL 里做不到。
  Stream<List<LedgerImageItem>> _streamFor(_GalleryMode mode) {
    return ref
        .read(databaseProvider)
        .watchAllImages(
          sort: mode == _GalleryMode.largest
              ? LedgerImageSort.largest
              : LedgerImageSort.newest,
        );
  }

  void _switchMode(_GalleryMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _images = _streamFor(mode);
    });
  }

  /// 按账单聚合，合计大的在前。
  List<_ImageGroup> _groupsOf(List<LedgerImageItem> items) {
    final grouped = <String, List<LedgerImageItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.transaction.id, () => []).add(item);
    }
    final groups = [
      for (final entry in grouped.values)
        _ImageGroup(
          transaction: entry.first.transaction,
          items: entry,
          totalBytes: entry.fold(
            0,
            (sum, item) => sum + item.image.sizeBytes,
          ),
        ),
    ];
    groups.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    return groups;
  }

  void _pruneSelection(List<LedgerImageItem> items) {
    final live = {for (final item in items) item.image.id};
    final stale = _selected.where((id) => !live.contains(id)).toList();
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selected.removeAll(stale));
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _enterSelect([String? firstId]) {
    HapticFeedback.selectionClick();
    setState(() {
      _selecting = true;
      if (firstId != null) _selected.add(firstId);
    });
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _toggleAll(List<LedgerImageItem> items) {
    setState(() {
      if (_selected.length == items.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(items.map((item) => item.image.id));
      }
    });
  }

  /// 整笔账单的图一起选中 / 取消。腾空间时「这笔的图都不要了」比逐张点快得多。
  void _toggleGroup(_ImageGroup group) {
    final ids = group.items.map((item) => item.image.id).toSet();
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.containsAll(ids)) {
        _selected.removeAll(ids);
      } else {
        _selecting = true;
        _selected.addAll(ids);
      }
    });
  }

  Future<void> _openViewer(List<LedgerImageItem> items, int index) async {
    final storage = ref.read(imageStorageProvider);
    final images = <ImageProvider>[];
    for (final item in items) {
      images.add(FileImage(await storage.resolve(item.image.imagePath)));
    }
    if (!mounted || images.isEmpty) return;
    await showPhotoViewer(
      context,
      images: images,
      initialIndex: index.clamp(0, images.length - 1),
    );
  }

  Future<void> _deleteSelected(List<LedgerImageItem> items) async {
    final chosen = [
      for (final item in items)
        if (_selected.contains(item.image.id)) item.image,
    ];
    if (chosen.isEmpty) return;
    final confirmed = await showAppConfirmDialog(
      context,
      message: '删除这 ${chosen.length} 张图片？账单会保留，删除后不可恢复',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(ledgerServiceProvider).deleteImages(chosen);
      if (!mounted) return;
      _exitSelect();
      showAppToast(
        context,
        message: '已删除 ${chosen.length} 张图片',
        level: AppToastLevel.success,
      );
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          message: '删除失败：$error',
          level: AppToastLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LedgerImageItem>>(
      stream: _images,
      builder: (context, snapshot) {
        final items = snapshot.data;
        if (items != null) _pruneSelection(items);
        final count = items?.length ?? 0;
        return AppTopBar(
          title: _selecting ? '已选 ${_selected.length} / $count' : '账单图片',
          actions: [
            if (items != null && items.isNotEmpty)
              _HeaderTextAction(
                label: _selecting ? '取消' : '选择',
                onTap: _busy
                    ? null
                    : () => _selecting ? _exitSelect() : _enterSelect(),
              ),
          ],
          bottom: _selecting && items != null && items.isNotEmpty
              ? _SelectBar(
                  allSelected: _selected.length == items.length,
                  selectedCount: _selected.length,
                  busy: _busy,
                  onToggleAll: () => _toggleAll(items),
                  onDelete: _selected.isEmpty
                      ? null
                      : () => _deleteSelected(items),
                )
              : null,
          slivers: _slivers(snapshot, items),
        );
      },
    );
  }

  List<Widget> _slivers(
    AsyncSnapshot<List<LedgerImageItem>> snapshot,
    List<LedgerImageItem>? items,
  ) {
    if (snapshot.hasError) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyState(
            icon: FLucideIcons.circleAlert,
            title: '图片加载失败',
            detail: '${snapshot.error}',
          ),
        ),
      ];
    }
    if (items == null) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (items.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyState(
            icon: FLucideIcons.image,
            title: '还没有账单图片',
            detail: '记账时加上照片后，会显示在这里',
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: _ModeBar(current: _mode, onSelect: _switchMode),
      ),
      if (_mode == _GalleryMode.byTransaction)
        _groupedSliver(items)
      else
        _gridSliver(items),
    ];
  }

  Widget _gridSliver(List<LedgerImageItem> items) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          return _tile(items, index, showSize: _mode == _GalleryMode.largest);
        }, childCount: items.length),
      ),
    );
  }

  Widget _groupedSliver(List<LedgerImageItem> items) {
    final groups = _groupsOf(items);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      sliver: SliverList.separated(
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final group = groups[index];
          final ids = group.items.map((item) => item.image.id).toSet();
          return _GroupCard(
            group: group,
            allSelected: _selected.containsAll(ids),
            selecting: _selecting,
            onToggleGroup: _busy ? null : () => _toggleGroup(group),
            tileBuilder: (position) =>
                _tile(group.items, position, showSize: true),
          );
        },
      ),
    );
  }

  /// 一格缩略图。[items] 是它所在的那一串——全屏浏览要按这一串左右翻。
  Widget _tile(
    List<LedgerImageItem> items,
    int index, {
    required bool showSize,
  }) {
    final item = items[index];
    return Consumer(
      builder: (context, ref, _) {
        return _ImageTile(
          item: item,
          storage: ref.watch(imageStorageProvider),
          selected: _selected.contains(item.image.id),
          selecting: _selecting,
          // 按大小翻的时候日期没用，用户要看的是这张到底多大。
          caption: showSize
              ? formatStorageBytes(item.image.sizeBytes)
              : formatDay(dateFromKey(item.transaction.accountingDate)),
          onTap: _busy
              ? null
              : () {
                  if (_selecting) {
                    _toggle(item.image.id);
                  } else {
                    _openViewer(items, index);
                  }
                },
          onLongPress: _busy
              ? null
              : () {
                  if (_selecting) {
                    _toggle(item.image.id);
                  } else {
                    _enterSelect(item.image.id);
                  }
                },
        );
      },
    );
  }
}

/// 一笔账单和它的全部图片。
class _ImageGroup {
  const _ImageGroup({
    required this.transaction,
    required this.items,
    required this.totalBytes,
  });

  final TransactionEntry transaction;
  final List<LedgerImageItem> items;
  final int totalBytes;
}

/// 浏览方式切换条。
class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.current, required this.onSelect});

  final _GalleryMode current;
  final ValueChanged<_GalleryMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (final mode in _GalleryMode.values) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: mode == current ? colors.primarySoft : colors.fill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: mode == current ? colors.primary : colors.inactive,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// 按账单聚合时的一组：标题交代这笔多大，下面是这笔的图。
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.allSelected,
    required this.selecting,
    required this.onToggleGroup,
    required this.tileBuilder,
  });

  final _ImageGroup group;
  final bool allSelected;
  final bool selecting;
  final VoidCallback? onToggleGroup;
  final Widget Function(int index) tileBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final day = dateFromKey(group.transaction.accountingDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggleGroup,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatDay(day)} · '
                    '${formatMoney(group.transaction.amountCents)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${group.items.length} 张 · '
                  '${formatStorageBytes(group.totalBytes)}',
                  style: TextStyle(fontSize: 12.5, color: colors.muted),
                ),
                if (selecting) ...[
                  const SizedBox(width: 8),
                  Icon(
                    allSelected
                        ? FLucideIcons.circleCheckBig
                        : FLucideIcons.circle,
                    size: 16,
                    color: allSelected ? colors.primary : colors.faint,
                  ),
                ],
              ],
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 6.0;
            final side = (constraints.maxWidth - spacing * 2) / 3;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (var i = 0; i < group.items.length; i++)
                  SizedBox(width: side, height: side, child: tileBuilder(i)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.item,
    required this.storage,
    required this.selected,
    required this.selecting,
    required this.caption,
    required this.onTap,
    required this.onLongPress,
  });

  final LedgerImageItem item;
  final ImageStorage storage;
  final bool selected;
  final bool selecting;

  /// 压在缩略图下沿的一行小字：日期或体积，由浏览方式决定。
  final String caption;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.fill,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LocalImage(storage: storage, relativePath: item.image.thumbnailPath),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x99000000)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                  child: Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            if (selecting)
              Positioned(
                top: 6,
                right: 6,
                child: _Check(selected: selected),
              ),
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.primary : const Color(0x66000000),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: selected
          ? const Icon(FLucideIcons.check, size: 13, color: Colors.white)
          : null,
    );
  }
}

class _SelectBar extends StatelessWidget {
  const _SelectBar({
    required this.allSelected,
    required this.selectedCount,
    required this.busy,
    required this.onToggleAll,
    required this.onDelete,
  });

  final bool allSelected;
  final int selectedCount;
  final bool busy;
  final VoidCallback onToggleAll;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            children: [
              TextButton(
                onPressed: busy ? null : onToggleAll,
                child: Text(
                  allSelected ? '取消全选' : '全选',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: busy ? null : onDelete,
                child: Text(
                  selectedCount == 0 ? '删除' : '删除 $selectedCount',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: onDelete == null || busy
                        ? colors.inactive
                        : colors.expense,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderTextAction extends StatelessWidget {
  const _HeaderTextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: SizedBox(
          height: kAppHeaderActionSize,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: onTap == null ? colors.inactive : colors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: colors.muted),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: colors.muted),
          ),
        ],
      ),
    );
  }
}
