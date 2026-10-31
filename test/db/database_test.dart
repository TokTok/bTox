import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/messages/message_format.dart';
import 'package:btox/messages/split_message.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/home.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_message_format.dart';

final _bob = PublicKey(Uint8List(32)..[0] = 1);

void main() {
  late Database db;

  setUp(() {
    db = Database(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Database', () {
    test('live facts are replaced, updated and dropped', () async {
      final id = await db.addProfile(
        ProfilesCompanion.insert(
          settings: const ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );
      final chat = ChatId.group(GroupChatId(Uint8List(32)));
      final bob = Subject.peer(chat, PublicKey(Uint8List(32)..[0] = 2));
      final carol = Subject.peer(chat, PublicKey(Uint8List(32)..[0] = 3));
      await db.updateLiveFacts(id, [
        (bob, const FactValue.name('Bob')),
        (bob, const FactValue.role(Role.user)),
      ]);
      await db.updateLiveFacts(id, [
        (carol, const FactValue.name('Carol')),
      ], all: true);
      // A newer home device's value doesn't keep the others out.
      await db.updateLiveFacts(id, [
        (carol, const FactValue.role(Role.founder)),
        (carol, const FactValue.unknown(99)),
        (carol, const FactValue.name('Caz')),
      ]);
      expect(
        await db.watchLiveFacts(id).first,
        Facts.of([
          (carol, const FactValue.name('Caz')),
          (carol, const FactValue.role(Role.founder)),
        ]),
      );

      await db.updateLiveFacts(id, [(carol, const FactValue.present(false))]);
      expect((await db.watchLiveFacts(id).first).subjects, isEmpty);
    });

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

    test(
      'signIn keeps other profiles signed in and shows the new one',
      () async {
        final p1 = ProfilesCompanion.insert(
          signedIn: const Value(true),
          settings: const ProfileSettings(nickname: 'P1', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(1),
        );
        final p2 = ProfilesCompanion.insert(
          signedIn: const Value(false),
          settings: const ProfileSettings(nickname: 'P2', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(2),
        );

        final id1 = await db.addProfile(p1);
        final id2 = await db.addProfile(p2);

        await db.signIn(id2);
        expect((await db.watchProfile(id1).first).signedIn, isTrue);
        expect((await db.watchProfile(id2).first).signedIn, isTrue);
        expect((await db.watchAppSettings().first).currentProfile, id2);

        await db.signOut(id1);
        expect((await db.watchProfile(id1).first).signedIn, isFalse);
      },
    );

    test('a long message is sent as parts an event takes', () async {
      final id = await db.addProfile(
        ProfilesCompanion.insert(
          settings: const ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );
      final text = 'é' * 40000;
      await db.addSend(id, GraphId.account(PublicKey(Uint8List(32))), text);

      final sends = [
        for (final intent in await db.watchIntents(id).first)
          (intent.content as Send).message,
      ];
      expect(sends.length, greaterThan(1));
      expect(
        sends.map((s) => s.length),
        everyElement(lessThanOrEqualTo(maxSendBytes)),
      );
      expect(utf8.decode([for (final s in sends) ...s]), text);
    });

    test('deleteProfile cleans up everything of the profile', () async {
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
      final home = await Home.load(db, await db.watchProfile(pId).first);
      await home.record(
        home.account,
        const FactContent(
          subject: Subject.account(),
          value: FactValue.name('Profile'),
        ),
      );
      await db.addIntent(pId, WantFriend(pk: PublicKey(Uint8List(32))));
      await db.addSend(pId, GraphId.account(PublicKey(Uint8List(32))), 'hi');
      await db.addTransfer(
        TransfersCompanion.insert(
          profileId: pId,
          graph: GraphId.account(PublicKey(Uint8List(32))),
          incoming: false,
          name: 'a',
          size: 1,
          path: 'a',
          state: FileState.active,
        ),
      );
      await db.setDraft(
        StoredDraft(
          profileId: pId,
          graph: GraphId.account(PublicKey(Uint8List(32))),
          message: '',
          attachments: const [FileContent(path: 'b')],
        ),
      );

      expect(await db.deleteProfile(pId), ['a', 'b']);

      for (final table in db.allTables) {
        if (table.actualTableName
            case 'app_settings' || 'cached_bootstrap_nodes') {
          continue;
        }
        expect(
          await db.select(table).get(),
          isEmpty,
          reason: table.actualTableName,
        );
      }
    });

    test("a chat's events come as they're added, and all again when some "
        'go', () async {
      final id = await db.addProfile(
        ProfilesCompanion.insert(
          settings: const ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );
      final home = await Home.load(db, await db.watchProfile(id).first);
      final bob = home.chatWith(PublicKey(Uint8List(32)..[0] = 1));
      final seen = <List<String>>[];
      final watching = db
          .watchSyncEvents(id, bob)
          .listen(
            (events) => seen.add([
              for (final (_, e) in events) (e.content as Received).sender,
            ]),
          );
      Future<EventId> receive(String sender) async {
        final (event, _, _) = (await home.record(
          bob,
          Received(
            sender: sender,
            message: utf8.encode('hi'),
            kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
          ),
        ))!;
        await pumpEventQueue();
        return event;
      }

      await pumpEventQueue();
      // Another chat's event isn't this one's.
      await home.record(
        home.chatWith(PublicKey(Uint8List(32)..[0] = 2)),
        const Notice(text: 'joined'),
      );
      final first = await receive('Bob');
      final second = await receive('Robert');
      await db.dropSyncEvents(id, [first]);
      await pumpEventQueue();
      // Once all are gone, new events may reuse their rowids.
      await db.dropSyncEvents(id, [second]);
      await pumpEventQueue();
      await receive('Bobby');
      await watching.cancel();
      expect(seen, [
        <String>[],
        ['Bob'],
        ['Bob', 'Robert'],
        ['Robert'],
        <String>[],
        ['Bobby'],
      ]);
    });

    test('a message sent again counts once, also when the first comes '
        'later', () async {
      final id = await db.addProfile(
        ProfilesCompanion.insert(
          settings: const ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );
      final chat = GraphId.friend(PublicKey(Uint8List(32)), _bob);
      NewEvent received(int rank, String text) {
        final event = SyncEvent(
          graph: chat,
          author: PublicKey(Uint8List(32)),
          parents: const [],
          rank: rank,
          time: rank,
          content: Received(
            sender: 'Bob',
            message: FakeMessageFormat.encode(text, '1'),
            kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
          ),
        );
        final bytes = event.encode();
        return (EventId.of(bytes), event, bytes);
      }

      final ranks = <List<int>?>[];
      final watching = db
          .watchReceivedRanks(id, withFakeFormat)
          .listen((received) => ranks.add(received[chat]));
      await pumpEventQueue();
      await db.addSyncEvents(id, [received(5, 'again')]);
      await pumpEventQueue();
      // As when older history comes after.
      await db.addSyncEvents(id, [received(2, 'first')]);
      await pumpEventQueue();
      await watching.cancel();
      expect(ranks, [
        null,
        [5],
        [2],
      ]);
    });

    test('each chat shows its latest entry', () async {
      final id = await db.addProfile(
        ProfilesCompanion.insert(
          settings: const ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );
      final home = await Home.load(db, await db.watchProfile(id).first);
      final alice = home.chatWith(PublicKey(Uint8List(32)..[0] = 1));
      final bob = home.chatWith(PublicKey(Uint8List(32)..[0] = 2));
      const kind = Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL;
      await home.record(
        alice,
        Received(sender: 'Alice', message: utf8.encode('first'), kind: kind),
      );
      final (sent, _, _) = (await home.record(
        alice,
        Send(sender: 'Me', message: utf8.encode('second'), kind: kind),
      ))!;
      await home.record(alice, Sent(intent: sent));
      await home.record(
        bob,
        Received(sender: 'Bob', message: utf8.encode('hi'), kind: kind),
      );
      Future<Map<GraphId, String>> latest() async => {
        for (final MapEntry(:key, :value)
            in (await db.watchLatestEntries(id, MessageFormats.none).first)
                .entries)
          key: value.content.plainText,
      };
      expect(await latest(), {alice: 'second', bob: 'hi'});
    });

    test('of messages written at once, the chat list shows the one the '
        'chat shows last', () async {
      final id = await db.addProfile(
        ProfilesCompanion.insert(
          settings: const ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );
      final chat = GraphId.account(PublicKey(Uint8List(32)..[0] = 1));
      NewEvent event(String text, int rank, int time, [EventId? parent]) {
        final event = SyncEvent(
          graph: chat,
          author: PublicKey(Uint8List(32)),
          parents: [?parent],
          rank: rank,
          time: time,
          content: Received(
            sender: 'Bob',
            message: utf8.encode(text),
            kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
          ),
        );
        final bytes = event.encode();
        return (EventId.of(bytes), event, bytes);
      }

      // A was written with an earlier clock, but after its parent.
      final parent = event('parent', 0, 200);
      final a = event('a', 1, 100, parent.$1);
      final b = event('b', 1, 150);
      await db.addSyncEvents(id, [parent, a, b]);

      final latest = await db.watchLatestEntries(id, MessageFormats.none).first;
      expect(latest[chat]?.content.plainText, 'a');
    });

    test('quick settings changes all stick', () async {
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

      await Future.wait([
        db.updateProfileSettings(id, (s) => s.copyWith(nickname: 'New Name')),
        db.updateProfileSettings(id, (s) => s.copyWith(statusMessage: 'Busy')),
      ]);

      final profile = await db.watchProfile(id).first;
      expect(profile.settings.nickname, 'New Name');
      expect(profile.settings.statusMessage, 'Busy');
    });
  });
}
