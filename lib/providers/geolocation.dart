import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

/// Why the device's position isn't available.
enum LocationProblem {
  /// Location is turned off on the device.
  off,

  /// bTox may not use location, and asking again won't help.
  denied,

  /// The user said no this time.
  refused,
}

final class LocationUnavailable implements Exception {
  final LocationProblem problem;

  const LocationUnavailable(this.problem);

  @override
  String toString() => 'Location unavailable: ${problem.name}';
}

/// The device's current position, asking for permission if needed.
Future<Position> geolocation() async {
  final location = GeolocatorPlatform.instance;
  if (!await location.isLocationServiceEnabled()) {
    throw const LocationUnavailable(LocationProblem.off);
  }
  var permission = await location.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await location.requestPermission();
  }
  switch (permission) {
    case LocationPermission.denied:
      throw const LocationUnavailable(LocationProblem.refused);
    case LocationPermission.deniedForever:
      throw const LocationUnavailable(LocationProblem.denied);
    case _:
      return location.getCurrentPosition();
  }
}

/// Opens where the user can fix [problem].
Future<void> fixLocation(LocationProblem problem) => switch (problem) {
  LocationProblem.off => GeolocatorPlatform.instance.openLocationSettings(),
  LocationProblem.denied => GeolocatorPlatform.instance.openAppSettings(),
  LocationProblem.refused => Future.value(),
};
