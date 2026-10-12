import 'dart:async';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/db/native.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

ProfilesCompanion _profile(String nickname) => ProfilesCompanion.insert(
  settings: ProfileSettings(nickname: nickname, statusMessage: ''),
  secretKey: SecretKey(Uint8List(32)),
  publicKey: PublicKey(Uint8List(32)),
  nospam: ToxAddressNospam(0),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Database host;

  setUp(() async {
    host = await hostDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await host.close();
    await unhostDatabase();
  });

  test('client and host see each other\'s writes', () async {
    final client = await connectToHostedDatabase();
    addTearDown(client.close);

    final hostSeesClient = host.watchProfiles().firstWhere(
      (profiles) => profiles.any((p) => p.settings.nickname == 'client'),
    );
    await client.addProfile(_profile('client'));
    await hostSeesClient;

    final clientSeesHost = client.watchProfiles().firstWhere(
      (profiles) => profiles.any((p) => p.settings.nickname == 'host'),
    );
    await host.addProfile(_profile('host'));
    await clientSeesHost;
  });

  test('connecting fails if nothing is hosted', () async {
    await unhostDatabase();
    await expectLater(
      connectToHostedDatabase(timeout: const Duration(milliseconds: 200)),
      throwsA(isA<TimeoutException>()),
    );
  });
}
