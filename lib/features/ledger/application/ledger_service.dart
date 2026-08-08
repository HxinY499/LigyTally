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
}
