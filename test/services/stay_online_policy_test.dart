import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
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
      await container.read(profilesProvider.future);
      return container.read(stayOnlineProvider);
    }

    Future<void> addProfile(ProfileSettings settings) => db.addProfile(
      ProfilesCompanion.insert(
        active: const Value(true),
        settings: settings,
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(0),
      ),
    );

    test('is unknown while loading, then false without a profile', () async {
      expect(container.read(stayOnlineProvider), isNull);
      expect(await settled(), isFalse);
    });

    test("follows the active profile's setting", () async {
      await addProfile(
        ProfileSettings(nickname: 'Me', statusMessage: '', stayOnline: false),
      );
      expect(await settled(), isFalse);
    });
  });
}
