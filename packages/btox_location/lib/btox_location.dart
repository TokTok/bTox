import 'package:flutter/services.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

/// Android location without Google Play services.
final class BtoxLocationAndroid extends GeolocatorPlatform {
  static const _channel = MethodChannel('btox_location');

  static void registerWith() {
    GeolocatorPlatform.instance = BtoxLocationAndroid();
  }

  @override
  Future<bool> isLocationServiceEnabled() async =>
      (await _channel.invokeMethod<bool>('isLocationServiceEnabled'))!;

  @override
  Future<LocationPermission> checkPermission() async => LocationPermission
      .values
      .byName((await _channel.invokeMethod<String>('checkPermission'))!);

  @override
  Future<LocationPermission> requestPermission() async => LocationPermission
      .values
      .byName((await _channel.invokeMethod<String>('requestPermission'))!);

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final fix = (await _channel.invokeMapMethod<String, Object?>(
      'getCurrentPosition',
    ))!;
    double at(String key) => fix[key]! as double;
    return Position(
      latitude: at('latitude'),
      longitude: at('longitude'),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        fix['timestamp']! as int,
        isUtc: true,
      ),
      accuracy: at('accuracy'),
      altitude: at('altitude'),
      altitudeAccuracy: at('altitudeAccuracy'),
      heading: at('heading'),
      headingAccuracy: at('headingAccuracy'),
      speed: at('speed'),
      speedAccuracy: at('speedAccuracy'),
      isMocked: fix['isMocked']! as bool,
    );
  }

  @override
  Future<bool> openAppSettings() async =>
      (await _channel.invokeMethod<bool>('openAppSettings'))!;

  @override
  Future<bool> openLocationSettings() async =>
      (await _channel.invokeMethod<bool>('openLocationSettings'))!;
}
