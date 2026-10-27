import 'package:btox_location/btox_location.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void answer(Map<String, Object?> answers) => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('btox_location'),
        (call) async => answers[call.method],
      );

  test('Android permission answers keep their meaning', () async {
    answer({'checkPermission': 'denied', 'requestPermission': 'deniedForever'});
    final location = BtoxLocationAndroid();

    expect(await location.checkPermission(), LocationPermission.denied);
    expect(
      await location.requestPermission(),
      LocationPermission.deniedForever,
    );
  });

  test('an Android fix becomes a position', () async {
    answer({
      'getCurrentPosition': {
        'latitude': 52.37,
        'longitude': 4.89,
        'timestamp': 1000,
        'accuracy': 5.0,
        'altitude': 2.0,
        'altitudeAccuracy': 1.0,
        'heading': 90.0,
        'headingAccuracy': 3.0,
        'speed': 0.5,
        'speedAccuracy': 0.1,
        'isMocked': false,
      },
    });

    final position = await BtoxLocationAndroid().getCurrentPosition();

    expect((position.latitude, position.longitude), (52.37, 4.89));
    expect(position.timestamp, DateTime.utc(1970, 1, 1, 0, 0, 1));
  });
}
