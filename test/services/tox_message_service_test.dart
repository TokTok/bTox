import 'dart:convert';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/services/message_notifier.dart';
import 'package:btox/services/tox_message_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_toxcore.dart';
import '../mocks/fake_tox_constants.dart';
import '../mocks/fake_bootstrap_nodes.dart';

const _secretKey =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

/// Starts the service for an active profile that has friend 0 as a contact.
Future<(Database, FakeToxcore)> _startService({
  MessageNotifier? notifier,
}) async {
  final db = Database(NativeDatabase.memory());
  addTearDown(db.close);
  final tox = FakeToxcore();
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => db),
      toxConstantsProvider.overrideWith((ref) => fakeToxcoreConstants),
      bootstrapNodesProvider.overrideWith(fakeBootstrapNodesProvider),
      // Families in riverpod_generator use a single object for multiple parameters.
      toxProvider.overrideWith((ref, args) => tox),
      messageNotifierProvider.overrideWithValue(notifier),
    ],
  );
  addTearDown(container.dispose);

  final profileId = await db.addProfile(
    ProfilesCompanion.insert(
      active: const Value(true),
      settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
      secretKey: SecretKey.fromJson(_secretKey),
      publicKey: PublicKey.fromJson(
        '0000000000000000000000000000000000000000000000000000000000000000',
      ),
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

  container.read(toxMessageServiceProvider);

  // Explicitly listen to the profiles stream to ensure it's pumping data.
  container.listen(profilesProvider, (prev, next) {});

  // Wait for the active profile to actually load and be recognized by the service.
  for (int i = 0; i < 20; i++) {
    if (container.read(activeProfileProvider) != null) {
      break;
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }

  // Explicitly listen to the stream to ensure the provider is active.
  container.listen(
    toxEventsProvider(SecretKey.fromJson(_secretKey), ToxAddressNospam(0)),
    (previous, next) {},
  );

  return (db, tox);
}

void _pushMessage(FakeToxcore tox, int friendNumber, String text) {
  tox.pushEvent(
    ToxEventFriendMessage(
      friendNumber: friendNumber,
      message: utf8.encode(text),
      type: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      messageLength: utf8.encode(text).length,
    ),
  );
}

/// Waits until at least [count] messages are stored, then returns all of them.
Future<List<Message>> _waitForMessages(Database db, int count) async {
  for (int i = 0; i < 10; i++) {
    final messages = await db.select(db.messages).get();
    if (messages.length >= count) {
      return messages;
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
  return db.select(db.messages).get();
}

void main() {
  test('ToxMessageService persists incoming messages', () async {
    final (db, tox) = await _startService();

    const text = 'Grüße from Tox! ✓';
    _pushMessage(tox, 0, text);

    final messages = await _waitForMessages(db, 1);
    expect(messages.length, 1);
    expect((messages.first.content as TextContent).text, text);
    expect(messages.first.author, tox.getFriendPublicKey(0));
  });

  test('ToxMessageService persists repeated identical messages', () async {
    final (db, tox) = await _startService();

    _pushMessage(tox, 0, 'hi');
    _pushMessage(tox, 0, 'hi');

    final messages = await _waitForMessages(db, 2);
    expect(messages.map((m) => (m.content as TextContent).text), ['hi', 'hi']);
  });

  test('ToxMessageService notifies, except for the open chat', () async {
    final shown = <(Id<Contacts>, String, String)>[];
    final notifier = MessageNotifier(
      (id, title, body) async => shown.add((id, title, body)),
      (id) async {},
    );
    final (db, tox) = await _startService(notifier: notifier);
    final contact = (await db.select(db.contacts).get()).single;

    notifier.openChat = contact.id;
    _pushMessage(tox, 0, 'seen');
    await _waitForMessages(db, 1);
    notifier.openChat = null;
    _pushMessage(tox, 0, 'hi');
    for (var i = 0; i < 20 && shown.isEmpty; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    expect(shown, [(contact.id, 'Friend', 'hi')]);
  });

  test('ToxMessageService ignores messages from unknown contacts', () async {
    final (db, tox) = await _startService();

    _pushMessage(tox, 1, 'from a stranger');
    _pushMessage(tox, 0, 'from a friend');

    final messages = await _waitForMessages(db, 1);
    expect(messages.map((m) => (m.content as TextContent).text), [
      'from a friend',
    ]);
  });

  test('ToxMessageService survives failing friend lookups', () async {
    final (db, tox) = await _startService();
    tox.missingFriendNumbers.add(2);

    _pushMessage(tox, 2, 'from a missing friend');
    _pushMessage(tox, 0, 'from a friend');

    final messages = await _waitForMessages(db, 1);
    expect(messages.map((m) => (m.content as TextContent).text), [
      'from a friend',
    ]);
  });

  test('ToxMessageService saves friend names', () async {
    final (db, tox) = await _startService();

    tox.pushEvent(
      ToxEventFriendName(friendNumber: 0, name: utf8.encode('toxxi')),
    );
    final contacts = await db
        .select(db.contacts)
        .watch()
        .firstWhere((c) => c.single.name != 'Friend');

    expect(contacts.single.name, 'toxxi');
  });

  test('ToxMessageService keeps the latest friend request', () async {
    final (db, tox) = await _startService();

    for (final message in ['add me', 'please add me']) {
      tox.pushEvent(
        ToxEventFriendRequest(
          publicKey: tox.getFriendPublicKey(3),
          message: utf8.encode(message),
        ),
      );
    }
    final requests = await db
        .select(db.friendRequests)
        .watch()
        .firstWhere((r) => r.isNotEmpty && r.single.message != 'add me');

    expect(requests.single.publicKey, tox.getFriendPublicKey(3));
    expect(requests.single.message, 'please add me');
    expect(await db.select(db.contacts).get(), hasLength(1));
  });
}
