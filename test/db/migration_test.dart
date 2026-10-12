import 'dart:io';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

void main() {
  late File file;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('btox_migration_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    file = File('${dir.path}/bTox.sqlite');
  });

  test('a schema version without a migration step keeps the data', () async {
    final db = Database(NativeDatabase(file));
    await db.addProfile(
      ProfilesCompanion.insert(
        settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(0),
      ),
    );
    final version = db.schemaVersion;
    await db.close();

    // E.g. an older app installed over a newer one's database.
    void setVersion(int version) => sqlite3.open(file.path)
      ..execute('PRAGMA user_version = $version;')
      ..dispose();
    setVersion(version + 1);

    final mismatched = Database(NativeDatabase(file));
    await expectLater(mismatched.watchProfiles().first, throwsA(anything));
    await mismatched.close();

    setVersion(version);
    final reopened = Database(NativeDatabase(file));
    addTearDown(reopened.close);
    expect(await reopened.watchProfiles().first, hasLength(1));
  });
}
