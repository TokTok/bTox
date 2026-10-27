import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
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

  test('merged chats show as one, counting each message once', () async {
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
    final group = GroupChat(GroupChatId(Uint8List(32)..[0] = 1));
    final conference = ConferenceChat(ConferenceId(Uint8List(32)..[0] = 2));
    final bot = PublicKey(Uint8List(32)..[0] = 3);
    for (final chat in [group, conference]) {
      await home.record(
        home.account,
        FactContent(subject: Subject.chat(chat), value: FactValue.name('Tox')),
      );
      await home.record(
        home.account,
        FactContent(subject: Subject.chat(chat), value: FactValue.joined(true)),
      );
    }
    await home.record(
      home.account,
      MergeChat(
        chat: conference,
        bot: bot,
        into: group,
        intoBot: bot,
        merged: true,
      ),
    );
    for (final (chat, from, sender, text) in [
      (group, PublicKey(Uint8List(32)..[0] = 4), 'Bob', 'hi'),
      (conference, bot, 'bot', '<Bob> hi'),
      (conference, PublicKey(Uint8List(32)..[0] = 5), 'Dan', 'yo'),
    ]) {
      await home.record(
        chat.graph,
        Received(
          from: from,
          sender: sender,
          message: utf8.encode(text),
          kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
        ),
      );
    }

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);
    container.listen(chatsForProfileProvider(id), (_, _) {});
    List<(GraphId, int)> chats() => [
      for (final chat
          in container.read(chatsForProfileProvider(id)).value ?? [])
        (chat.ref.graph, chat.unread),
    ];
    for (var i = 0; i < 100 && chats().firstOrNull?.$2 != 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(chats(), [(group.graph, 2)]);
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
  test("a linked account's files show this device's part on top of the "
      "home device's", () async {
    final db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    final device = PublicKey(Uint8List(32));
    final home = PublicKey(Uint8List(32)..fillRange(0, 32, 1));
    final id = await db.addProfile(
      ProfilesCompanion.insert(
        settings: const ProfileSettings(nickname: 'bTox', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: device,
        nospam: ToxAddressNospam(0),
        home: Value(ToxAddress.of(home, ToxAddressNospam(0))),
      ),
    );
    final chat = ChatRef(
      id,
      GraphId.friend(home, PublicKey(Uint8List(32)..[0] = 2)),
    );
    final events = <(EventId, SyncEvent, Uint8List)>[];
    Future<EventId> add(PublicKey author, EventContent content) async {
      final event = SyncEvent(
        graph: chat.graph,
        author: author,
        parents: [?events.lastOrNull?.$1],
        rank: events.length,
        time: 0,
        content: content,
      );
      final bytes = event.encode();
      events.add((EventId.of(bytes), event, bytes));
      await db.addSyncEvents(id, [events.last]);
      return events.last.$1;
    }

    Future<Id<Transfers>> transfer(EventId event, {required bool incoming}) =>
        db.addTransfer(
          TransfersCompanion.insert(
            profileId: id,
            graph: chat.graph,
            event: Value(event),
            incoming: incoming,
            name: '',
            size: 3,
            path: '',
            state: FileState.active,
            transferred: const Value(1),
          ),
        );

    final dog = BlobId(Uint8List(32)..[0] = 1);
    final offered = await add(
      home,
      const FileStarted(
        sender: 'Bob',
        name: 'dog.png',
        size: 3,
        incoming: true,
      ),
    );
    await add(home, FileEnded(file: offered, ok: true, blob: dog));
    final sent = await add(
      device,
      FileStarted(
        sender: 'Me',
        name: 'cat.png',
        size: 3,
        incoming: false,
        blob: BlobId(Uint8List(32)..[0] = 2),
      ),
    );
    final fetch = await transfer(offered, incoming: true);
    final send = await transfer(sent, incoming: false);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);
    final shown = container.listen(chatEntriesProvider(chat), (_, _) {});
    Future<void> expectFiles(List<FileProgress> expected) async {
      List<FileProgress?> files() => [
        for (final entry in shown.read().value ?? <ChatEntry>[]) entry.file,
      ];
      for (var i = 0; i < 100 && !listEquals(files(), expected); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(files(), expected);
    }

    await expectFiles([
      FileProgress(state: FileState.active, transferred: 1, blob: dog),
      const FileProgress(state: FileState.active, transferred: 1),
    ]);

    // Ours is then the home device's to send on, which it doesn't show.
    await db.setTransferState(fetch, FileState.done, transferred: 3);
    await db.setTransferState(send, FileState.done, transferred: 3);
    await expectFiles([
      FileProgress(state: FileState.done, transferred: 3, blob: dog),
      const FileProgress(state: FileState.active),
    ]);

    await add(home, FileEnded(file: sent, ok: true));
    await expectFiles([
      FileProgress(state: FileState.done, transferred: 3, blob: dog),
      const FileProgress(state: FileState.done),
    ]);
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
