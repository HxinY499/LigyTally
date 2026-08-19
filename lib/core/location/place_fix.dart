import '../database/app_database.dart';

/// 一笔账单上的位置：坐标是机器用的，[name] 才是人看的。
///
/// 逆地理失败时 [name] 为空，界面用 [displayName] 显示「已记录位置」，
/// 不把这句占位写进数据库。
class PlaceFix {
  const PlaceFix({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracyMeters,
    this.name,
    this.fromCache = false,
  });

  final double latitude;
  final double longitude;
  final DateTime capturedAt;
  final double? accuracyMeters;
  final String? name;

  /// 来自系统「最近一次已知位置」，而不是这一次新采到的点。
  final bool fromCache;

  String get displayName {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return '已记录位置';
  }

  String? get storedName {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  PlaceFix withName(String? value) {
    return PlaceFix(
      latitude: latitude,
      longitude: longitude,
      capturedAt: capturedAt,
      accuracyMeters: accuracyMeters,
      name: value,
      fromCache: fromCache,
    );
  }

  static PlaceFix? tryFrom(TransactionEntry tx) {
    final lat = tx.locationLatitude;
    final lng = tx.locationLongitude;
    if (lat == null || lng == null) return null;
    return PlaceFix(
      latitude: lat,
      longitude: lng,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(tx.updatedAt),
      name: tx.locationName,
    );
  }
}

extension TransactionLocationX on TransactionEntry {
  bool get hasLocation => locationLatitude != null && locationLongitude != null;

  String? get locationLabel {
    final n = locationName?.trim();
    if (n != null && n.isNotEmpty) return n;
    if (hasLocation) return '已记录位置';
    return null;
  }

  /// 地点 + 备注，拼在列表时间后面。
  String get locationAndNote {
    final parts = <String>[
      ?locationLabel,
      if (note.trim().isNotEmpty) note.trim(),
    ];
    return parts.join(' · ');
  }
}

/// 把系统逆地理字段收成一句可读的中文地点。
///
/// 不要国家名，不要 Plus Code。区 / 路 / 号能拼上就拼，拼不出再退到城市或
/// 地标名。返回 null 表示这些字段里没有能给人看的东西。
String? formatAddress({
  String? subLocality,
  String? thoroughfare,
  String? subThoroughfare,
  String? street,
  String? locality,
  String? name,
  String? country,
}) {
  final parts = <String>[];
  void add(String? value) {
    if (!_usable(value)) return;
    final text = value!.trim();
    if (parts.contains(text)) return;
    parts.add(text);
  }

  add(subLocality);
  add(thoroughfare);
  add(subThoroughfare);
  if (parts.isEmpty) add(street);
  if (parts.isEmpty) add(locality);
  if (parts.isEmpty) {
    final trimmed = name?.trim();
    if (_usable(trimmed) &&
        trimmed != country?.trim() &&
        !trimmed!.contains('+')) {
      parts.add(trimmed);
    }
  }
  if (parts.isEmpty) return null;
  return parts.join();
}

bool _usable(String? value) {
  if (value == null) return false;
  final text = value.trim();
  if (text.isEmpty) return false;
  if (text == 'Unnamed Road') return false;
  return true;
}
