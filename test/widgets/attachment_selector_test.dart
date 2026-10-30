import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/content.dart';
import 'package:btox/widgets/attachment_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final class _Location extends GeolocatorPlatform {
  var enabled = true;
  var answer = LocationPermission.whileInUse;
  var fixes = true;
  final opened = <String>[];

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() async => answer;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (!fixes) {
      throw PlatformException(code: 'unavailable');
    }
    return Position(
      latitude: 52.37,
      longitude: 4.89,
      timestamp: DateTime.utc(2026),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Future<bool> openAppSettings() async {
    opened.add('app');
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    opened.add('location');
    return true;
  }
}

void main() {
  testWidgets('sharing a location says what stops it, and where to fix it', (
    tester,
  ) async {
    final location = _Location();
    final platform = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = location;
    addTearDown(() => GeolocatorPlatform.instance = platform);
    final selected = <List<Content>>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: AttachmentSelector(files: false, onSelected: selected.add),
          ),
        ),
      ),
    );
    Future<void> share() async {
      await tester.tap(find.byIcon(Icons.location_on));
      await tester.pumpAndSettle();
    }

    final settings = find.text('Settings');
    location.enabled = false;
    await share();
    expect(find.text('Turn on location to share where you are'), findsOne);
    await tester.tap(settings);

    location.enabled = true;
    location.answer = LocationPermission.deniedForever;
    await share();
    expect(find.text('bTox needs permission to use your location'), findsOne);
    await tester.tap(settings);
    expect(location.opened, ['location', 'app']);

    // Android asks again next time.
    location.answer = LocationPermission.denied;
    await share();
    expect(find.text('bTox needs permission to use your location'), findsOne);
    expect(settings, findsNothing);

    location.answer = LocationPermission.whileInUse;
    location.fixes = false;
    await share();
    expect(find.text("Couldn't find where you are"), findsOne);

    location.fixes = true;
    await share();
    expect(selected, [
      [const LocationContent(latitude: 52.37, longitude: 4.89)],
    ]);

    location.enabled = false;
    await share();
    expect(find.text('Turn on location to share where you are'), findsOne);
    // Turned on elsewhere, as from the quick settings.
    location.enabled = true;
    await share();
    expect(selected, hasLength(2));
    expect(find.byType(SnackBar), findsNothing);
  });
}
