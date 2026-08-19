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

/// 系统逆地理可能一次返回多条：有的是门牌，有的是小区/商场。
/// 优先要有名字的地点，没有再退到路号。
String? formatBestPlace(Iterable<AddressHint> places) {
  String? fallback;
  for (final place in places) {
    final label = formatAddress(
      subLocality: place.subLocality,
      thoroughfare: place.thoroughfare,
      subThoroughfare: place.subThoroughfare,
      street: place.street,
      locality: place.locality,
      name: place.name,
      country: place.country,
    );
    if (label == null) continue;
    fallback ??= label;
    if (looksLikeNamedPlace(place.name) || looksLikeNamedPlace(label)) {
      return label;
    }
  }
  return fallback;
}

class AddressHint {
  const AddressHint({
    this.subLocality,
    this.thoroughfare,
    this.subThoroughfare,
    this.street,
    this.locality,
    this.name,
    this.country,
  });

  final String? subLocality;
  final String? thoroughfare;
  final String? subThoroughfare;
  final String? street;
  final String? locality;
  final String? name;
  final String? country;
}

/// 把系统逆地理字段收成一句可读的中文地点。
///
/// 记忆场景要的是「在哪个小区/商场」，不是邮政门牌。所以有用地名时
/// 优先用 [name]，没有再拼区 / 路 / 号。
String? formatAddress({
  String? subLocality,
  String? thoroughfare,
  String? subThoroughfare,
  String? street,
  String? locality,
  String? name,
  String? country,
}) {
  final trimmedName = name?.trim();
  if (_usablePlaceName(trimmedName, country: country) &&
      !_isStreetNumberLike(trimmedName, thoroughfare, subThoroughfare)) {
    if (looksLikeNamedPlace(trimmedName) ||
        !_looksLikeStreetAddress(trimmedName, thoroughfare, subThoroughfare)) {
      return trimmedName;
    }
  }

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
  if (parts.isEmpty) return null;
  return parts.join();
}

/// 小区、商场、园区这类「有名字的地方」，相对于「xx路xx号」。
bool looksLikeNamedPlace(String? value) {
  if (!_usable(value)) return false;
  final text = value!.trim();
  if (text.contains('+')) return false;
  const markers = [
    '小区',
    '花园',
    '家园',
    '公寓',
    '别墅',
    '苑',
    '大厦',
    '广场',
    '商场',
    '超市',
    '百货',
    '中心',
    '大学',
    '学院',
    '医院',
    '公园',
    '酒店',
    '宾馆',
    '餐厅',
    '饭店',
    '食堂',
    '市场',
    '写字楼',
    '产业园',
    '工业园',
    '科技园',
    '软件园',
    '园区',
    '地铁',
    '火车站',
    '机场',
    '学校',
    '幼儿园',
    '小学',
    '中学',
    '村',
  ];
  return markers.any(text.contains);
}

bool _usablePlaceName(String? value, {String? country}) {
  if (!_usable(value)) return false;
  final text = value!.trim();
  if (text.contains('+')) return false;
  if (country != null && text == country.trim()) return false;
  return true;
}

bool _isStreetNumberLike(
  String? value,
  String? thoroughfare,
  String? subThoroughfare,
) {
  if (!_usable(value)) return true;
  final text = value!.trim();
  if (RegExp(r'^\d+号?$').hasMatch(text)) return true;
  final road = thoroughfare?.trim();
  final number = subThoroughfare?.trim();
  if (number != null && text == number) return true;
  if (road != null && text == road) return true;
  return false;
}

bool _looksLikeStreetAddress(
  String? value,
  String? thoroughfare,
  String? subThoroughfare,
) {
  if (!_usable(value)) return false;
  final text = value!.trim();
  final road = thoroughfare?.trim();
  final number = subThoroughfare?.trim();
  if (road != null && number != null && text.contains(road) && text.contains(number)) {
    return true;
  }
  return (text.contains('路') && text.contains('号')) ||
      (text.contains('街') && text.contains('号'));
}

bool _usable(String? value) {
  if (value == null) return false;
  final text = value.trim();
  if (text.isEmpty) return false;
  if (text == 'Unnamed Road') return false;
  return true;
}
