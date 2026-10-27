import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/services/tox_session.dart';
import 'package:btox/sync/event.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import '../mocks/fake_bootstrap_nodes.dart';
import '../mocks/fake_toxcore.dart';

Future<void> _until(bool Function() condition) async {
  for (int i = 0; i < 50 && !condition(); i++) {
    await Future.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

void main() {
  late Database db;
  late FakeToxcore tox;
  GraphId chat() =>
      GraphId.friend(PublicKey(Uint8List(32)), tox.friendGetPublicKey(0));
  late List<Tox_Connection?> statuses;
  late Id<Profiles> profileId;

  setUp(() async {
    db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    tox = FakeToxcore();
    statuses = [];

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        bootstrapNodesProvider.overrideWith(fakeBootstrapNodesProvider),
        toxProvider.overrideWith((ref, args) {
          ref.onDispose(tox.kill);
          return tox;
        }),
      ],
    );
    addTearDown(container.dispose);

    profileId = await db.addProfile(
      ProfilesCompanion.insert(
        signedIn: const Value(true),
        settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(0),
      ),
    );
    await db.addFriendChange(
      profileId,
      tox.friendGetPublicKey(0),
      wanted: true,
    );

    container.listen(
      toxSessionsProvider,
      (_, sessions) => statuses.add(sessions[profileId]?.connection),
      fireImmediately: true,
    );
  });

  test('runs Tox for the signed-in profile and reports its status', () async {
    await _until(() => statuses.contains(Tox_Connection.TOX_CONNECTION_NONE));

    tox.pushEvent(
      ToxEventSelfConnectionStatus(
        connectionStatus: Tox_Connection.TOX_CONNECTION_UDP,
      ),
    );
    await _until(() => statuses.last == Tox_Connection.TOX_CONNECTION_UDP);
  });

  test('sends our messages until they are delivered', () async {
    await _until(() => tox.friends.isNotEmpty);
    await db.addSend(profileId, chat(), 'hi');

    tox.pushEvent(
      ToxEventFriendConnectionStatus(
        friendNumber: 0,
        connectionStatus: Tox_Connection.TOX_CONNECTION_UDP,
      ),
    );
    await _until(() => tox.sentMessages.isNotEmpty);
    expect(tox.sentMessages.single.$3, 'hi');

    tox.pushEvent(
      ToxEventFriendReadReceipt(
        friendNumber: 0,
        messageId: tox.sentMessages.single.$2,
      ),
    );
    await db
        .watchSyncEvents(profileId, chat())
        .firstWhere((events) => events.any((e) => e.$2.content is Delivered));
  });

  test('stops Tox when the profile signs out', () async {
    await _until(() => statuses.contains(Tox_Connection.TOX_CONNECTION_NONE));

    await db.signOut(profileId);
    await _until(() => statuses.last == null);
    await _until(() => !tox.isAlive);
  });

  test('saves repeated identical messages', () async {
    await _until(() => tox.friends.isNotEmpty);

    for (var i = 0; i < 2; i++) {
      tox.pushEvent(
        ToxEventFriendMessage(
          friendNumber: 0,
          type: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
          message: utf8.encode('hi'),
        ),
      );
    }
    final events = await db
        .watchSyncEvents(profileId, chat())
        .firstWhere((events) => events.length == 2);
    expect(
      [for (final (_, event) in events) (event.content as Received).message],
      [utf8.encode('hi'), utf8.encode('hi')],
    );
  });
}
