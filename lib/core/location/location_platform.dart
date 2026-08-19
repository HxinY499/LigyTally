import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'place_fix.dart';

enum DeviceLocationPermission { denied, deniedForever, granted }

class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? accuracyMeters;
}

class LocationUnavailableException implements Exception {
  const LocationUnavailableException([this.message]);

  final String? message;

  @override
  String toString() => message ?? 'LocationUnavailableException';
}

/// 系统定位与逆地理的底层，方便单测替换。
abstract class LocationPlatform {
  Future<bool> isServiceEnabled();

  Future<DeviceLocationPermission> checkPermission();

  Future<DeviceLocationPermission> requestPermission();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();

  Future<GeoPoint?> lastKnown();

  Future<GeoPoint> currentPosition({required Duration timeLimit});

  Future<String?> reverseGeocode(GeoPoint point);
}

class GeolocatorLocationPlatform implements LocationPlatform {
  GeolocatorLocationPlatform({Geocoding? geocoding})
    : _geocoding = geocoding ?? Geocoding(locale: const Locale('zh', 'CN'));

  final Geocoding _geocoding;

  LocationSettings _settings(Duration timeLimit) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: timeLimit,
        forceLocationManager: true,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: timeLimit,
    );
  }

  DeviceLocationPermission _mapPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => DeviceLocationPermission.granted,
      LocationPermission.deniedForever =>
        DeviceLocationPermission.deniedForever,
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => DeviceLocationPermission.denied,
    };
  }

  GeoPoint _toPoint(Position position) {
    return GeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
      accuracyMeters: position.accuracy,
    );
  }

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<DeviceLocationPermission> checkPermission() async {
    return _mapPermission(await Geolocator.checkPermission());
  }

  @override
  Future<DeviceLocationPermission> requestPermission() async {
    return _mapPermission(await Geolocator.requestPermission());
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<GeoPoint?> lastKnown() async {
    final position = await Geolocator.getLastKnownPosition(
      forceAndroidLocationManager: true,
    );
    if (position == null) return null;
    return _toPoint(position);
  }

  @override
  Future<GeoPoint> currentPosition({required Duration timeLimit}) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _settings(timeLimit),
      );
      return _toPoint(position);
    } on TimeoutException {
      rethrow;
    } catch (error) {
      throw LocationUnavailableException(error.toString());
    }
  }

  @override
  Future<String?> reverseGeocode(GeoPoint point) async {
    try {
      final present = await _geocoding.isPresent();
      if (!present) return null;
      final marks = await _geocoding
          .placemarkFromCoordinates(point.latitude, point.longitude)
          .timeout(const Duration(seconds: 5));
      if (marks.isEmpty) return null;
      return formatBestPlace([
        for (final mark in marks)
          AddressHint(
            subLocality: mark.subLocality,
            thoroughfare: mark.thoroughfare,
            subThoroughfare: mark.subThoroughfare,
            street: mark.street,
            locality: mark.locality,
            name: mark.name,
            country: mark.country,
          ),
      ]);
    } catch (_) {
      return null;
    }
  }
}
