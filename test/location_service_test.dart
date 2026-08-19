import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ligy_tally/core/database/app_database.dart';
import 'package:ligy_tally/core/location/location_platform.dart';
import 'package:ligy_tally/core/location/location_service.dart';
import 'package:ligy_tally/core/location/place_fix.dart';

void main() {
  group('formatAddress', () {
    test('优先拼区、路、号，不要国家', () {
      expect(
        formatAddress(
          subLocality: '玄武区',
          thoroughfare: '中山路',
          subThoroughfare: '128号',
          locality: '南京市',
          country: '中国',
        ),
        '玄武区中山路128号',
      );
    });

    test('没有路名时退到城市', () {
      expect(formatAddress(locality: '南京市', country: '中国'), '南京市');
    });

    test('Plus Code 不当成地点名', () {
      expect(formatAddress(name: '7FG8+2X', country: '中国'), isNull);
    });

    test('全空返回 null', () {
      expect(formatAddress(), isNull);
    });
  });

  group('LocationService.capture', () {
    late _FakePlatform platform;
    late DateTime now;
    late LocationService service;

    GeoPoint point({
      required DateTime timestamp,
      double accuracy = 30,
      double lat = 32.04,
      double lng = 118.78,
    }) {
      return GeoPoint(
        latitude: lat,
        longitude: lng,
        timestamp: timestamp,
        accuracyMeters: accuracy,
      );
    }

    setUp(() {
      now = DateTime(2026, 8, 19, 21, 0);
      platform = _FakePlatform();
      service = LocationService(platform, clock: () => now);
    });

    test('缓存足够新时不再采新点', () async {
      platform.lastKnownPoint = point(
        timestamp: now.subtract(const Duration(minutes: 1)),
      );
      platform.reverseName = '新街口';
      platform.current = point(timestamp: now, lat: 1, lng: 1);

      final result = await service.capture();

      expect(result.isSuccess, isTrue);
      expect(result.place!.name, '新街口');
      expect(result.place!.fromCache, isTrue);
      expect(platform.currentCount, 0);
    });

    test('新点超时后降级用可接受的缓存', () async {
      platform.lastKnownPoint = point(
        timestamp: now.subtract(const Duration(minutes: 10)),
        accuracy: 200,
      );
      platform.currentThrows = TimeoutException('timeout');
      platform.reverseName = '大约在这里';

      final result = await service.capture();

      expect(result.place?.fromCache, isTrue);
      expect(result.place?.name, '大约在这里');
      expect(platform.currentCount, 1);
    });

    test('超时且没有可用缓存就是失败', () async {
      platform.lastKnownPoint = point(
        timestamp: now.subtract(const Duration(hours: 2)),
      );
      platform.currentThrows = TimeoutException('timeout');

      final result = await service.capture();

      expect(result.error, LocationCaptureError.timeout);
    });

    test('自动获取不弹权限框', () async {
      platform.permission = DeviceLocationPermission.denied;

      final result = await service.capture(requestIfNeeded: false);

      expect(result.error, LocationCaptureError.permissionDenied);
      expect(platform.requestCount, 0);
    });

    test('手动获取会申请权限', () async {
      platform.permission = DeviceLocationPermission.denied;
      platform.permissionAfterRequest = DeviceLocationPermission.granted;
      platform.current = point(timestamp: now);
      platform.reverseName = '夫子庙';

      final result = await service.capture(requestIfNeeded: true);

      expect(platform.requestCount, 1);
      expect(result.place?.name, '夫子庙');
      expect(result.place?.fromCache, isFalse);
    });

    test('系统定位关闭', () async {
      platform.serviceEnabled = false;
      final result = await service.capture();
      expect(result.error, LocationCaptureError.serviceDisabled);
      expect(platform.currentCount, 0);
    });

    test('逆地理失败仍算定位成功', () async {
      platform.current = point(timestamp: now);
      platform.reverseName = null;

      final result = await service.capture();

      expect(result.isSuccess, isTrue);
      expect(result.place!.name, isNull);
      expect(result.place!.displayName, '已记录位置');
    });
  });

  test('旧备份 JSON 缺地点字段也能读', () {
    final entry = TransactionEntry.fromJson({
      'id': 'a',
      'kind': 0,
      'amountCents': 100,
      'categoryId': 'c',
      'accountingDate': '2026-08-19',
      'occurredAt': 1,
      'note': '',
      'createdAt': 1,
      'updatedAt': 1,
    });
    expect(entry.locationLatitude, isNull);
    expect(entry.locationLongitude, isNull);
    expect(entry.locationName, isNull);
    expect(entry.hasLocation, isFalse);
  });
}

class _FakePlatform implements LocationPlatform {
  bool serviceEnabled = true;
  DeviceLocationPermission permission = DeviceLocationPermission.granted;
  DeviceLocationPermission? permissionAfterRequest;
  GeoPoint? lastKnownPoint;
  GeoPoint? current;
  Object? currentThrows;
  String? reverseName;
  int requestCount = 0;
  int currentCount = 0;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<DeviceLocationPermission> checkPermission() async => permission;

  @override
  Future<DeviceLocationPermission> requestPermission() async {
    requestCount++;
    permission = permissionAfterRequest ?? DeviceLocationPermission.granted;
    return permission;
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<GeoPoint?> lastKnown() async => lastKnownPoint;

  @override
  Future<GeoPoint> currentPosition({required Duration timeLimit}) async {
    currentCount++;
    final error = currentThrows;
    if (error != null) {
      if (error is Exception) throw error;
      throw LocationUnavailableException(error.toString());
    }
    final point = current;
    if (point == null) {
      throw const LocationUnavailableException('no current');
    }
    return point;
  }

  @override
  Future<String?> reverseGeocode(GeoPoint point) async => reverseName;
}
