import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/messaging.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/services/tox_owner.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_bootstrap_nodes.dart';
import '../mocks/fake_tox_constants.dart';
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
  late List<Tox_Connection?> statuses;

  setUp(() async {
    db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    tox = FakeToxcore();
    statuses = [];

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        bootstrapNodesProvider.overrideWith(fakeBootstrapNodesProvider),
        toxConstantsProvider.overrideWith((ref) => fakeToxcoreConstants),
        toxProvider.overrideWith((ref, args) {
          ref.onDispose(tox.kill);
          return tox;
        }),
      ],
    );
    addTearDown(container.dispose);

    final profileId = await db.addProfile(
      ProfilesCompanion.insert(
        active: const Value(true),
        settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(0),
      ),
    );
    await db.addContact(
      ContactsCompanion.insert(
        profileId: profileId,
        name: Value('Friend'),
        publicKey: tox.getFriendPublicKey(0),
      ),
    );

    runToxOwner(container, statuses.add);
  });

  test('runs Tox for the active profile and reports its status', () async {
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
    final contact = (await db.select(db.contacts).get()).single;
    final id = await db.addMessage(
      newMessage(
        contactId: contact.id,
        parent: null,
        merged: null,
        author: PublicKey(Uint8List(32)),
        timestamp: DateTime.utc(2026),
        content: TextContent(text: 'hi'),
      ).copyWith(delivered: const Value(false)),
    );

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
        .watchMessagesFor(contact.id)
        .firstWhere((messages) => messages.single.delivered == true);
    expect((await db.getMessage(id)).delivered, isTrue);
  });

  test('stops Tox when no profile is active', () async {
    await _until(() => statuses.contains(Tox_Connection.TOX_CONNECTION_NONE));

    await db.deactivateProfiles();
    await _until(() => statuses.last == null);
    await _until(() => !tox.isAlive);
  });
}
