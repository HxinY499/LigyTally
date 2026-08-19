import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_platform.dart';
import 'place_fix.dart';

enum LocationCaptureError {
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  timeout,
  unavailable,
}

class LocationCaptureResult {
  const LocationCaptureResult._({this.place, this.error});

  const LocationCaptureResult.success(PlaceFix place) : this._(place: place);

  const LocationCaptureResult.failure(LocationCaptureError error)
    : this._(error: error);

  final PlaceFix? place;
  final LocationCaptureError? error;

  bool get isSuccess => place != null;
}

/// 最近一次已知位置足够新、足够准时，直接用，不再等新点。
const kFreshFixMaxAge = Duration(minutes: 2);
const kFreshFixMaxAccuracyMeters = 100.0;

/// 新点超时后，还能接受的缓存点。
const kFallbackFixMaxAge = Duration(minutes: 15);
const kFallbackFixMaxAccuracyMeters = 500.0;

/// 「再记一笔」时复用上一笔位置的窗口。
const kReuseFixMaxAge = Duration(minutes: 2);

const kCurrentPositionTimeout = Duration(seconds: 8);

/// 一次取点：预检权限 → 新鲜缓存直接用 → 否则采新点，超时再降级。
///
/// 逆地理失败不影响成功：有坐标就算拿到了位置。
class LocationService {
  LocationService(this._platform, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final LocationPlatform _platform;
  final DateTime Function() _now;

  Future<bool> isServiceEnabled() => _platform.isServiceEnabled();

  Future<DeviceLocationPermission> checkPermission() =>
      _platform.checkPermission();

  Future<DeviceLocationPermission> requestPermission() =>
      _platform.requestPermission();

  Future<bool> openAppSettings() => _platform.openAppSettings();

  Future<bool> openLocationSettings() => _platform.openLocationSettings();

  /// [requestIfNeeded] 为 false 时不弹权限框：给自动获取用，权限应在设置页开开关时已经要过。
  Future<LocationCaptureResult> capture({
    bool requestIfNeeded = true,
    Duration timeLimit = kCurrentPositionTimeout,
  }) async {
    if (!await _platform.isServiceEnabled()) {
      return const LocationCaptureResult.failure(
        LocationCaptureError.serviceDisabled,
      );
    }

    var permission = await _platform.checkPermission();
    if (permission != DeviceLocationPermission.granted) {
      if (!requestIfNeeded) {
        return LocationCaptureResult.failure(_permissionError(permission));
      }
      permission = await _platform.requestPermission();
      if (permission != DeviceLocationPermission.granted) {
        return LocationCaptureResult.failure(_permissionError(permission));
      }
    }

    final lastKnown = await _platform.lastKnown();
    if (_isUsable(lastKnown, kFreshFixMaxAge, kFreshFixMaxAccuracyMeters)) {
      return _finish(lastKnown!, fromCache: true);
    }

    try {
      final current = await _platform.currentPosition(timeLimit: timeLimit);
      return _finish(current, fromCache: false);
    } on TimeoutException {
      if (_isUsable(
        lastKnown,
        kFallbackFixMaxAge,
        kFallbackFixMaxAccuracyMeters,
      )) {
        return _finish(lastKnown!, fromCache: true);
      }
      return const LocationCaptureResult.failure(LocationCaptureError.timeout);
    } on LocationUnavailableException {
      if (_isUsable(
        lastKnown,
        kFallbackFixMaxAge,
        kFallbackFixMaxAccuracyMeters,
      )) {
        return _finish(lastKnown!, fromCache: true);
      }
      return const LocationCaptureResult.failure(
        LocationCaptureError.unavailable,
      );
    }
  }

  LocationCaptureError _permissionError(DeviceLocationPermission permission) {
    return permission == DeviceLocationPermission.deniedForever
        ? LocationCaptureError.permissionDeniedForever
        : LocationCaptureError.permissionDenied;
  }

  bool _isUsable(GeoPoint? point, Duration maxAge, double maxAccuracy) {
    if (point == null) return false;
    if (_now().difference(point.timestamp) > maxAge) return false;
    final accuracy = point.accuracyMeters;
    if (accuracy == null || accuracy <= 0) return true;
    return accuracy <= maxAccuracy;
  }

  Future<LocationCaptureResult> _finish(
    GeoPoint point, {
    required bool fromCache,
  }) async {
    final name = await _platform.reverseGeocode(point);
    return LocationCaptureResult.success(
      PlaceFix(
        latitude: point.latitude,
        longitude: point.longitude,
        capturedAt: point.timestamp,
        accuracyMeters: point.accuracyMeters,
        name: name,
        fromCache: fromCache,
      ),
    );
  }
}

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService(GeolocatorLocationPlatform());
});
