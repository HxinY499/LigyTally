import 'package:drift/drift.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/media/image_storage.dart';
import '../../../core/utils/ledger_date.dart';

class LedgerService {
  LedgerService(this.database, this.imageStorage);

  final AppDatabase database;
  final ImageStorage imageStorage;
  final Uuid _uuid = const Uuid();

  Future<void> save({
    LedgerItem? existing,
    required int kind,
    required int amountCents,
    required String categoryId,
    required DateTime accountingDate,
    required DateTime occurredAt,
    required String note,
    required List<XFile> pendingImages,
    required List<TransactionImageEntry> existingImages,
    required Set<String> removedImageIds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final transactionId = existing?.transaction.id ?? _uuid.v4();
    final stored = <({String id, StoredImage image})>[];

    try {
      for (final source in pendingImages) {
        final imageId = _uuid.v4();
        final image = await imageStorage.store(
          source: source,
          transactionId: transactionId,
          imageId: imageId,
        );
        stored.add((id: imageId, image: image));
      }

      final keptCount = existingImages
          .where((image) => !removedImageIds.contains(image.id))
          .length;
      await database.saveTransaction(
        entry: TransactionsCompanion.insert(
          id: transactionId,
          kind: kind,
          amountCents: amountCents,
          categoryId: categoryId,
          accountingDate: dateKey(accountingDate),
          occurredAt: occurredAt.millisecondsSinceEpoch,
          note: Value(note.trim()),
          createdAt: existing?.transaction.createdAt ?? now,
          updatedAt: now,
        ),
        newImages: [
          for (var index = 0; index < stored.length; index++)
            TransactionImagesCompanion.insert(
              id: stored[index].id,
              transactionId: transactionId,
              imagePath: stored[index].image.imagePath,
              thumbnailPath: stored[index].image.thumbnailPath,
              width: Value(stored[index].image.width),
              height: Value(stored[index].image.height),
              sizeBytes: stored[index].image.sizeBytes,
              sortOrder: Value(keptCount + index),
              createdAt: now,
            ),
        ],
        removedImageIds: removedImageIds,
      );
    } catch (_) {
      for (final item in stored) {
        await imageStorage.deleteFile(item.image.imagePath);
        await imageStorage.deleteFile(item.image.thumbnailPath);
      }
      rethrow;
    }

    for (final image in existingImages) {
      if (removedImageIds.contains(image.id)) {
        await imageStorage.deleteFile(image.imagePath);
        await imageStorage.deleteFile(image.thumbnailPath);
      }
    }
  }

  Future<void> delete(LedgerItem item) async {
    await database.deleteTransaction(item.transaction.id);
    await imageStorage.deleteTransactionDirectory(item.transaction.id);
  }

  /// 只删图片，不动账单。
  ///
  /// 先改库再删文件：库失败时文件还在，账单打开仍看得到图。
  /// 文件删除失败会留下孤儿，和编辑页移除图片同一条补偿路径。
  Future<void> deleteImages(Iterable<TransactionImageEntry> images) async {
    final list = images.toList();
    if (list.isEmpty) return;
    await database.deleteImages({for (final image in list) image.id});
    for (final image in list) {
      await imageStorage.deleteFile(image.imagePath);
      await imageStorage.deleteFile(image.thumbnailPath);
    }
  }

  /// 把长边超过 [kRecompressMaxSide] 的账单原图重新压小，账单和图都保留。
  ///
  /// 只挑「长边确实超标」的压：已经小于目标的图再压一次只会白掉画质，
  /// 体积也省不下多少。库里 width 为 0 的是早期数据，尺寸未知，一并尝试——
  /// [ImageStorage.recompress] 压不出更小的结果时会自己放弃。
  ///
  /// 缩略图不动：它本来就是 320px，占的是零头。
  ///
  /// 先落盘再写库：文件已经变小而库还写着旧体积，最坏是排序和统计偏大，
  /// 下次重压会修正；反过来库说压过了、文件其实没动，就再也不会被处理了。
  Future<RecompressResult> recompressLargeImages({
    void Function(int done, int total)? onProgress,
  }) async {
    final targets = [
      for (final image in await database.exportImages())
        if (image.width == 0 ||
            image.width > kRecompressMaxSide ||
            image.height > kRecompressMaxSide)
          image,
    ];

    var processed = 0;
    var freed = 0;
    onProgress?.call(0, targets.length);
    for (final image in targets) {
      final result = await imageStorage.recompress(
        relativePath: image.imagePath,
      );
      if (result != null) {
        await database.updateImageMetrics(
          id: image.id,
          sizeBytes: result.sizeBytes,
          width: result.width,
          height: result.height,
        );
        freed += image.sizeBytes - result.sizeBytes;
        processed++;
      }
      onProgress?.call(processed, targets.length);
    }
    return RecompressResult(
      candidateCount: targets.length,
      compressedCount: processed,
      freedBytes: freed < 0 ? 0 : freed,
    );
  }
}

/// 一次批量重压的结果。
///
/// [candidateCount] 和 [compressedCount] 分开报：挑中 40 张、真压小 12 张是
/// 正常结果（其余压完反而更大，被放弃了），只报一个数字会让用户以为出错。
class RecompressResult {
  const RecompressResult({
    required this.candidateCount,
    required this.compressedCount,
    required this.freedBytes,
  });

  final int candidateCount;
  final int compressedCount;
  final int freedBytes;
}
