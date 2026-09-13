import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Database db;

  setUp(() {
    db = Database(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Database', () {
    test('profiles can be added and watched', () async {
      final p1 = ProfilesCompanion.insert(
        settings: const ProfileSettings(
          nickname: 'Test',
          statusMessage: 'Available',
        ),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(0),
      );

      final id = await db.addProfile(p1);
      final profiles = await db.watchProfiles().first;

      expect(profiles, hasLength(1));
      expect(profiles.first.id, id);
    });

    test('activateProfile toggles active flag correctly', () async {
      final p1 = ProfilesCompanion.insert(
        active: const Value(true),
        settings: const ProfileSettings(nickname: 'P1', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(1),
      );
      final p2 = ProfilesCompanion.insert(
        active: const Value(false),
        settings: const ProfileSettings(nickname: 'P2', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(2),
      );

      final id1 = await db.addProfile(p1);
      final id2 = await db.addProfile(p2);

      await db.activateProfile(id2);

      final profile1 = await db.watchProfile(id1).first;
      final profile2 = await db.watchProfile(id2).first;

      expect(profile1.active, isFalse);
      expect(profile2.active, isTrue);
    });

    test('deleteProfile cleans up contacts and messages', () async {
      final pId = await db.addProfile(
        ProfilesCompanion.insert(
          settings: const ProfileSettings(
            nickname: 'Profile',
            statusMessage: '',
          ),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );

      final cId = await db.addContact(
        ContactsCompanion.insert(
          profileId: pId,
          publicKey: PublicKey(Uint8List(32)),
          name: const Value('Test Contact'),
        ),
      );

      await db.addMessage(
        MessagesCompanion.insert(
          contactId: cId,
          author: PublicKey(Uint8List(32)),
          sha: Sha256(Uint8List(32)),
          timestamp: DateTime.now(),
          content: const TextContent(text: 'Hello'),
        ),
      );

      await db.deleteProfile(pId);

      final profiles = await db.watchProfiles().first;
      expect(profiles, isEmpty);

      // Verify contacts for that profile are gone.
      final contacts = await db.watchContactsFor(pId).first;
      expect(contacts, isEmpty);
    });

    test('updateProfileSettings updates only requested profile', () async {
      final id = await db.addProfile(
        ProfilesCompanion.insert(
          settings: const ProfileSettings(
            nickname: 'Old Name',
            statusMessage: '',
          ),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );

      const newSettings = ProfileSettings(
        nickname: 'New Name',
        statusMessage: 'Busy',
      );
      await db.updateProfileSettings(id, newSettings);

      final profile = await db.watchProfile(id).first;
      expect(profile.settings.nickname, 'New Name');
      expect(profile.settings.statusMessage, 'Busy');
    });
  });
}
