import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/home.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show ProviderBase;
import 'package:riverpod/riverpod.dart';

void main() {
  test("a chat that's gone from the list still shows", () {
    final chat = ChatRef(
      Id(1),
      GraphId.friend(PublicKey(Uint8List(32)), PublicKey(Uint8List(32))),
    );
    final container = ProviderContainer(
      overrides: [
        chatsForProfileProvider(Id(1)).overrideWithValue(const AsyncData([])),
      ],
    );
    addTearDown(container.dispose);

    final summary = container.read(chatProvider(chat)).requireValue;
    expect((summary.ref, summary.name, summary.key), (chat, null, chat.graph));
  });

  test('chats with the latest messages come first', () async {
    final db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.addProfile(
      ProfilesCompanion.insert(
        settings: const ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(0),
      ),
    );
    final home = await Home.load(db, await db.watchProfile(id).first);
    final friends = {
      for (final (i, name) in ['Alice', 'Bob', 'Carol'].indexed)
        name: PublicKey(Uint8List(32)..[0] = i + 1),
    };
    for (final MapEntry(key: name, value: pk) in friends.entries) {
      await home.record(home.account, WantFriend(pk: pk));
      await home.record(
        home.account,
        FactContent(subject: Subject.friend(pk), value: FactValue.name(name)),
      );
    }
    for (final (name, day) in [('Alice', 2), ('Carol', 3)]) {
      await withClock(
        Clock.fixed(DateTime.utc(2026, 1, day)),
        () => home.record(
          home.chatWith(friends[name]!),
          Received(
            sender: name,
            message: utf8.encode('hi'),
            kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
          ),
        ),
      );
    }

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);
    container.listen(chatsForProfileProvider(id), (_, _) {});
    List<String?> names() => [
      for (final chat
          in container.read(chatsForProfileProvider(id)).value ?? [])
        chat.name,
    ];
    const expected = ['Carol', 'Alice', 'Bob'];
    for (var i = 0; i < 100 && !listEquals(names(), expected); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(names(), expected);
  });

  test("leaving a chat leaves none of the chat's providers alive", () async {
    final db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.addProfile(
      ProfilesCompanion.insert(
        settings: const ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(0),
      ),
    );
    final alive = _Alive();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) => db)],
      observers: [alive],
    );
    addTearDown(container.dispose);
    final chat = ChatRef(
      id,
      GraphId.friend(
        PublicKey(Uint8List(32)),
        PublicKey(Uint8List(32)..[0] = 1),
      ),
    );

    final shown = container.listen(chatEntriesProvider(chat), (_, _) {});
    for (var i = 0; i < 100 && !shown.read().hasValue; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(shown.read().value, isEmpty);
    shown.close();
    await pumpEventQueue();

    expect(alive.providers.where((p) => p.argument != null), isEmpty);
  });
}

final class _Alive extends ProviderObserver {
  final providers = <ProviderBase<Object?>>{};

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) =>
      providers.add(context.provider);

  @override
  void didDisposeProvider(ProviderObserverContext context) =>
      providers.remove(context.provider);
}
