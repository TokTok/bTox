import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_options.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/tox_library.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/home.dart';
import 'package:clock/clock.dart';

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
      secretKey: tox.selfGetSecretKey(),
      publicKey: tox.selfGetPublicKey(),
      nospam: ToxAddressNospam(tox.selfGetNospam()),
      name: _text(tox.selfGetName()),
      statusMessage: _text(tox.selfGetStatusMessage()),
      friends: [
        for (final friend in tox.selfGetFriendList())
          (tox.friendGetPublicKey(friend), _text(tox.friendGetName(friend))),
      ],
    );
  } finally {
    tox.kill();
  }
}

/// Adds [profile], signed in, with its friends.
Future<Id<Profiles>> importProfile(Database db, ToxSaveProfile profile) {
  return db.transaction(() async {
    final existing = await (db.select(
      db.profiles,
    )..where((p) => p.publicKey.equals(profile.publicKey.toJson()))).get();
    if (existing.isNotEmpty) {
      throw const ProfileExistsException();
    }
    final settings = ProfileSettings(
      nickname: profile.name,
      statusMessage: profile.statusMessage,
    );
    final id = await db.addProfile(
      ProfilesCompanion.insert(
        settings: settings,
        secretKey: profile.secretKey,
        publicKey: profile.publicKey,
        nospam: profile.nospam,
      ),
    );
    final account = AccountWriter(profile.publicKey, settings);
    final now = clock.now();
    for (final (pk, name) in profile.friends) {
      account.addFriend(now, WantFriend(pk: pk), name);
    }
    await db.addSyncEvents(id, account.events);
    await db.signIn(id);
    return id;
  });
}

String _text(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);
