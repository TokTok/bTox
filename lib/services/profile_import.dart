import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_options.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/tox_library.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';

final class ToxSaveProfile {
  final SecretKey secretKey;
  final PublicKey publicKey;
  final ToxAddressNospam nospam;
  final String name;
  final String statusMessage;
  final List<(PublicKey, String)> friends;

  const ToxSaveProfile({
    required this.secretKey,
    required this.publicKey,
    required this.nospam,
    required this.name,
    required this.statusMessage,
    required this.friends,
  });
}

final class ProfileExistsException implements Exception {
  const ProfileExistsException();
}

/// Reads unencrypted toxcore savedata with toxcore itself, without going
/// online.
ToxSaveProfile readToxSave(ToxLibrary lib, Uint8List save) {
  // ignore: argument_type_not_assignable
  final tox = Toxcore(
    lib,
    ToxOptions(
      udpEnabled: false,
      localDiscoveryEnabled: false,
      savedata: save,
      savedataType: Tox_Savedata_Type.TOX_SAVEDATA_TYPE_TOX_SAVE,
    ),
  );
  try {
    return ToxSaveProfile(
      secretKey: tox.secretKey,
      publicKey: tox.address.publicKey,
      nospam: tox.nospam,
      name: tox.name,
      statusMessage: tox.statusMessage,
      friends: [
        for (final friend in tox.friendList)
          (tox.getFriendPublicKey(friend), tox.getFriendName(friend)),
      ],
    );
  } finally {
    tox.kill();
  }
}

/// Adds [profile] as the active profile, with its friends as contacts.
Future<Id<Profiles>> importProfile(Database db, ToxSaveProfile profile) {
  return db.transaction(() async {
    final existing = await (db.select(
      db.profiles,
    )..where((p) => p.publicKey.equals(profile.publicKey.toJson()))).get();
    if (existing.isNotEmpty) {
      throw const ProfileExistsException();
    }
    final id = await db.addProfile(
      ProfilesCompanion.insert(
        settings: ProfileSettings(
          nickname: profile.name,
          statusMessage: profile.statusMessage,
        ),
        secretKey: profile.secretKey,
        publicKey: profile.publicKey,
        nospam: profile.nospam,
      ),
    );
    for (final (publicKey, name) in profile.friends) {
      await db.addContact(
        ContactsCompanion.insert(
          profileId: id,
          publicKey: publicKey,
          name: Value(name.isEmpty ? null : name),
        ),
      );
    }
    await db.activateProfile(id);
    return id;
  });
}
