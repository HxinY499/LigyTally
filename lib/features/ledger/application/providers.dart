import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backup/backup_service.dart';
import '../../../core/category_config/category_config_service.dart';
import '../../../core/database/app_database.dart';
import '../../../core/export/csv_export_service.dart';
import '../../../core/media/image_storage.dart';
import 'ledger_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final imageStorageProvider = Provider<ImageStorage>((ref) => ImageStorage());

final ledgerServiceProvider = Provider<LedgerService>((ref) {
  return LedgerService(
    ref.watch(databaseProvider),
    ref.watch(imageStorageProvider),
  );
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    ref.watch(databaseProvider),
    ref.watch(imageStorageProvider),
  );
});

final csvExportServiceProvider = Provider<CsvExportService>((ref) {
  return CsvExportService(ref.watch(databaseProvider));
});

final categoryConfigServiceProvider = Provider<CategoryConfigService>((ref) {
  return CategoryConfigService(
    ref.watch(databaseProvider),
    ref.watch(imageStorageProvider),
  );
});
