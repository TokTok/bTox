import 'package:btox/db/database.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/services/stay_online_policy.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _grace = Duration(milliseconds: 50);

Future<void> _pastGrace() => Future.delayed(_grace * 3);

void main() {
  late int stops;
  late List<bool> bootModes;
  late StayOnlinePolicy policy;

  setUp(() {
    stops = 0;
    bootModes = [];
    policy = StayOnlinePolicy(
      onStop: () => stops++,
      onAutoStartOnBoot: bootModes.add,
      grace: _grace,
    );
    addTearDown(policy.dispose);
  });

  test('stops once no UI has been open for the grace period', () async {
    policy
      ..uiCount = 1
      ..uiCount = 0
      ..uiCount = 1;
    await _pastGrace();
    expect(stops, 0);

    policy.uiCount = 0;
    await _pastGrace();
    expect(stops, 1);
  });

  test('stays online while the setting is on', () async {
    policy.stayOnline = true;
    await _pastGrace();
    expect(stops, 0);

    policy.stayOnline = false;
    await _pastGrace();
    expect(stops, 1);
  });

  test('sets the boot mode once known, and again when a UI opens', () {
    policy
      ..uiCount = 1
      ..stayOnline = null;
    expect(bootModes, isEmpty);

    policy
      ..stayOnline = true
      ..uiCount = 2;
    expect(bootModes, [true, true]);
  });

  group('stayOnlineProvider', () {
    late Database db;
    late ProviderContainer container;

    setUp(() {
      db = Database(NativeDatabase.memory());
      addTearDown(db.close);
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWith((ref) => db)],
      );
      addTearDown(container.dispose);
    });

    Future<bool?> settled() async {
      container.listen(stayOnlineProvider, (_, _) {});
      await container.read(appSettingsProvider.future);
      return container.read(stayOnlineProvider);
    }

    test('is unknown while loading, then on by default', () async {
      expect(container.read(stayOnlineProvider), isNull);
      expect(await settled(), isTrue);
    });

    test('follows the app setting', () async {
      await db.updateAppSettings(
        const AppSettingsCompanion(stayOnline: Value(false)),
      );
      expect(await settled(), isFalse);
    });
  });
}
