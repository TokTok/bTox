import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/messages/message_format.dart';
import 'package:btox/messages/split_message.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/services/message_notifier.dart';
import 'package:btox/services/tox_sync.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/sync/store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_message_format.dart';
import '../mocks/fake_notifier.dart';
import '../mocks/fake_toxcore.dart';

final _friendAddress = ToxAddress.fromString('${'2' * 72}0000');
final _friend = _friendAddress.publicKey;
final _me = PublicKey(Uint8List(32));
final _account = GraphId.account(_me);
final _chat = GraphId.friend(_me, _friend);

Future<void> _until(bool Function() condition) async {
  for (int i = 0; i < 50 && !condition(); i++) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

Future<void> _settle() => Future.delayed(const Duration(milliseconds: 50));

void main() {
  late Database db;
  late FakeToxcore tox;
  late Id<Profiles> profileId;
  late ToxSync sync;
  late List<Shown> shown;
  late List<String> requested;
  late MessageNotifier notifier;

  setUp(() async {
    db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    tox = FakeToxcore();
    profileId = await db.addProfile(
      ProfilesCompanion.insert(
        signedIn: const Value(true),
        settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: _me,
        nospam: ToxAddressNospam(0),
      ),
    );
    shown = [];
    requested = [];
    notifier = fakeNotifier(
      shown,
      request: (_, from, message, _) async => requested.add(message),
    );
    sync = ToxSync(
      db,
      tox,
      profileId,
      maxMessageLength: 10,
      retryDelay: const Duration(milliseconds: 20),
      notifier: notifier,
      knownFormats: const [FakeMessageFormat()],
    );
    addTearDown(sync.dispose);
  });

  Future<void> want({bool withRequest = false, bool wanted = true}) =>
      db.addIntent(
        profileId,
        wanted
            ? WantFriend(
                pk: _friend,
                requestMessage: withRequest ? 'Add me' : null,
                nospam: withRequest ? _friendAddress.nospam : null,
              )
            : UnwantFriend(pk: _friend),
      );

  Future<List<EventContent>> contents(GraphId graph) async => [
    for (final (_, event) in rankOrder(
      await db.watchSyncEvents(profileId, graph).first,
    ))
      event.content,
  ];

  Future<AccountState> account() async => AccountState.of(
    rankOrder(await db.watchSyncEvents(profileId, _account).first),
  );

  void setOnline(int friendNumber, bool online) => sync.handleEvent(
    ToxEventFriendConnectionStatus(
      friendNumber: friendNumber,
      connectionStatus: online
          ? Tox_Connection.TOX_CONNECTION_UDP
          : Tox_Connection.TOX_CONNECTION_NONE,
    ),
  );

  void receipt(int messageId) => sync.handleEvent(
    ToxEventFriendReadReceipt(friendNumber: 0, messageId: messageId),
  );

  Future<bool> delivered() async =>
      (await contents(_chat)).any((content) => content is Delivered);

  List<String> sentTexts() => [
    for (final (_, _, text) in tox.sentMessages) text,
  ];

  test('sets and records our name and status message', () async {
    sync.start();
    await _until(() => tox.name == 'Me');

    await db.updateProfileSettings(
      profileId,
      (s) => s.copyWith(nickname: 'New', statusMessage: 'Busy'),
    );
    await _until(() => tox.name == 'New' && tox.statusMessage == 'Busy');
    await _settle();
    final state = await account();
    expect((state.name, state.statusMessage), ('New', 'Busy'));
  });

  test('sends friend requests until accepted', () async {
    await want(withRequest: true);
    sync.start();
    await _until(() => tox.friends.isNotEmpty);
    expect(tox.friends, [_friend]);
    expect(tox.friendRequests, [(_friendAddress, 'Add me')]);

    setOnline(0, true);
    await _settle();
    expect((await account()).friends[_friend]?.nospam, isNull);
  });

  test('asks a friend again who was added before', () async {
    await want();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);

    // Such as when they deleted us, and are added again by their address.
    await want(withRequest: true);
    await _until(() => tox.friendRequests.isNotEmpty);
    expect(tox.friendRequests, [(_friendAddress, 'Add me')]);
    expect(tox.deletedFriends, [0]);
  });

  test('deletes friends no longer wanted', () async {
    await want();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);

    await want(wanted: false);
    await _until(() => tox.deletedFriends.isNotEmpty);
    expect(tox.deletedFriends, [0]);
    expect(await db.select(db.intents).get(), isEmpty);
  });

  test("tracks the friend's online state", () async {
    await want();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);
    Future<FactValue?> connection() async =>
        (await db.watchLiveFacts(profileId).first)
            .of(Subject.friend(_friend))
            .singleOrNull;

    setOnline(0, true);
    await _settle();
    expect(await connection(), const FactValue.connection(Connection.udp));

    setOnline(0, false);
    await _settle();
    expect(await connection(), const FactValue.connection(Connection.none));
  });

  test('says Hello to friends coming online', () async {
    await want();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);

    setOnline(0, true);
    // Toxcore says so again when the friend moves from UDP to TCP.
    sync.handleEvent(
      ToxEventFriendConnectionStatus(
        friendNumber: 0,
        connectionStatus: Tox_Connection.TOX_CONNECTION_TCP,
      ),
    );
    final (friendNumber, packet) = tox.losslessPackets.single;
    expect(friendNumber, 0);
    expect(packet, [0xb0, 0x03, 0x92, 0x00, 0x92, 0x01, 0x00]);
  });

  group('messages', () {
    setUp(() async {
      await want();
      sync.start();
      await _until(() => tox.friends.isNotEmpty);
    });

    test('are sent once the friend is online, until delivered', () async {
      await db.addSend(profileId, _chat, 'hi');
      await _settle();
      expect(tox.sentMessages, isEmpty);
      expect(await db.select(db.intents).get(), isEmpty);

      setOnline(0, true);
      expect(sentTexts(), ['hi']);

      receipt(tox.sentMessages.single.$2);
      await _settle();
      expect(await contents(_chat), [
        isA<Send>(),
        isA<Sent>(),
        isA<Delivered>(),
      ]);

      setOnline(0, false);
      setOnline(0, true);
      await _settle();
      expect(sentTexts(), ['hi']);
    });

    test('are sent again after the friend went offline', () async {
      setOnline(0, true);
      await db.addSend(profileId, _chat, 'hi');
      await _until(() => tox.sentMessages.isNotEmpty);

      setOnline(0, false);
      setOnline(0, true);
      expect(sentTexts(), ['hi', 'hi']);

      receipt(tox.sentMessages.first.$2);
      await _settle();
      expect(await delivered(), isFalse);
      expect((await contents(_chat)).whereType<Sent>(), hasLength(1));
    });

    test('that fail are sent again on the next attempt', () async {
      tox.unreachableFriends.add(0);
      setOnline(0, true);
      await db.addSend(profileId, _chat, 'hi');
      await _settle();
      expect(tox.sentMessages, isEmpty);

      tox.unreachableFriends.clear();
      await _until(() => tox.sentMessages.isNotEmpty);
      expect(sentTexts(), ['hi']);
    });

    test('too long for Tox are delivered in parts', () async {
      setOnline(0, true);
      await db.addSend(profileId, _chat, 'hello brave new world');
      await _until(() => tox.sentMessages.isNotEmpty);
      expect(sentTexts(), ['hello ', 'brave new ', 'world']);

      for (final (_, messageId, _) in tox.sentMessages.take(2)) {
        receipt(messageId);
      }
      await _settle();
      expect(await delivered(), isFalse);

      receipt(tox.sentMessages.last.$2);
      await _settle();
      expect(await delivered(), isTrue);
    });

    test('in parts go on where Tox stopped, once it takes more', () async {
      tox.sendQueueRoom = 1;
      setOnline(0, true);
      await db.addSend(profileId, _chat, 'hello brave new world');
      await _until(() => tox.sentMessages.isNotEmpty);
      await _settle();
      expect(sentTexts(), ['hello ']);
      expect((await contents(_chat)).whereType<Sent>(), isEmpty);

      tox.sendQueueRoom = null;
      await _until(() => tox.sentMessages.length == 3);
      expect(sentTexts(), ['hello ', 'brave new ', 'world']);
      await _settle();
      expect((await contents(_chat)).whereType<Sent>(), hasLength(1));
    });
  });

  test('splitMessage never splits a character', () {
    List<String> split(String text, int maxBytes) => [
      for (final part in splitMessage(utf8.encode(text), maxBytes))
        utf8.decode(part),
    ];
    expect(split('ü' * 6 + '😀' * 3, 7), ['üüü', 'üüü', '😀', '😀', '😀']);
    expect(split('a bbbbbbbbbbb', 10), ['a bbbbbbbb', 'bbb']);
  });

  void receive(int friendNumber, List<int> message) => sync.handleEvent(
    ToxEventFriendMessage(
      friendNumber: friendNumber,
      type: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      message: Uint8List.fromList(message),
    ),
  );

  test('deletes a friend with their chat, which starts over', () async {
    await want();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);
    receive(0, utf8.encode('hi'));
    await _settle();
    final (hi, received) =
        (await db.watchSyncEvents(profileId, _chat).first).single;
    await db.setRead(profileId, _chat, (received.rank, hi));
    final file = File('${Directory.systemTemp.createTempSync().path}/cat.png')
      ..writeAsStringSync('meow');
    await db.addTransfer(
      TransfersCompanion.insert(
        profileId: profileId,
        graph: _chat,
        incoming: true,
        name: 'cat.png',
        size: 4,
        path: file.path,
        state: FileState.done,
      ),
    );
    await _settle();

    await db.addIntent(profileId, UnwantFriend(pk: _friend), deleteChat: true);
    await _until(() => tox.deletedFriends.isNotEmpty);
    await _settle();
    expect(await contents(_chat), isEmpty);
    expect(await db.select(db.transfers).get(), isEmpty);
    expect(file.existsSync(), isFalse);

    // Read markers point into the deleted chat, so new messages come after.
    await want();
    await _until(() => tox.friends.length == 2);
    receive(1, utf8.encode('hi again'));
    await _settle();
    final (_, again) =
        (await db.watchSyncEvents(profileId, _chat).first).single;
    expect(again.rank, greaterThan((await account()).read[_chat]!.$1));
  });

  test('records and notifies messages, except for the open chat', () async {
    await want();
    sync.start();
    await _until(() => tox.friends.isNotEmpty && tox.name == 'Me');

    notifier.openChat = ChatRef(profileId, _chat);
    receive(0, utf8.encode('seen'));
    await _settle();
    notifier.openChat = null;
    receive(0, utf8.encode('Grüße ✓'));
    await _settle();

    expect(
      [
        for (final content in await contents(_chat))
          utf8.decode((content as Received).message),
      ],
      ['seen', 'Grüße ✓'],
    );
    expect(shown, [(ChatRef(profileId, _chat), null, 'Grüße ✓', 'Me')]);

    // Muted, not even its mentions notify, until unmuted.
    shown.clear();
    final scope = Scope.conversation(_chat);
    await db.addIntent(
      profileId,
      SettingContent(
        scope: scope,
        setting: Kept(
          Setting.mute(
            until: DateTime.now().add(const Duration(hours: 1)),
            mentions: false,
          ),
        ),
      ),
    );
    await _settle();
    expect((await account()).setting<Mute>(scope), isNotNull);
    receive(0, utf8.encode('Me: quiet'));
    await _settle();
    await db.addIntent(
      profileId,
      ClearSetting(scope: scope, kind: Setting.muteKind),
    );
    await _settle();
    receive(0, utf8.encode('loud'));
    await _settle();
    expect(shown, [(ChatRef(profileId, _chat), null, 'loud', 'Me')]);
  });

  test('keeps resends a format knows, which count and notify once', () async {
    await want();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);

    final hi = FakeMessageFormat.encode('hi', '1');
    receive(0, hi);
    receive(0, hi);
    receive(0, utf8.encode('plain'));
    await _settle();

    expect(
      [
        for (final content in await contents(_chat))
          (content as Received).message,
      ],
      [hi, hi, utf8.encode('plain')],
    );
    expect(
      (await db.watchReceivedRanks(profileId, withFakeFormat).first)[_chat],
      hasLength(2),
    );
    expect([for (final s in shown) s.$3], ['hi', 'plain']);
  });

  test('ignores messages from unknown friends', () async {
    await want();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);

    receive(1, utf8.encode('from a stranger'));
    receive(0, utf8.encode('from a friend'));
    await _settle();

    expect(await contents(_chat), hasLength(1));
  });

  test('records friend names', () async {
    await want();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);

    sync.handleEvent(
      ToxEventFriendName(friendNumber: 0, name: utf8.encode('Home')),
    );
    await _settle();
    expect((await account()).friends[_friend]?.name, 'Home');
  });

  test('keeps the latest friend request, telling of each', () async {
    sync.start();
    await _settle();
    for (final message in ['add me', 'please add me', 'please add me']) {
      sync.handleEvent(
        ToxEventFriendRequest(
          publicKey: _friend,
          message: utf8.encode(message),
        ),
      );
    }
    await _settle();

    final friend = (await account()).friends[_friend]!;
    expect((friend.request, friend.wanted), ('please add me', false));
    expect(requested, ['add me', 'please add me']);
    expect(
      (await contents(_account)).whereType<FriendRequested>(),
      hasLength(2),
    );
    expect(tox.friends, isEmpty);

    // Declined, it stays declined as their client sends it again.
    await want(wanted: false);
    await _settle();
    requested.clear();
    for (final message in ['please add me', 'it is me, Bob']) {
      sync.handleEvent(
        ToxEventFriendRequest(
          publicKey: _friend,
          message: utf8.encode(message),
        ),
      );
      await _settle();
    }
    expect((await account()).friends[_friend]?.request, 'it is me, Bob');
    expect(requested, ['it is me, Bob']);
  });

  test('announces files, refuses avatars and cancels declined files', () async {
    await want();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);
    await db.updateAppSettings(
      const AppSettingsCompanion(autoAcceptFileSize: Value(0)),
    );
    await _settle();

    void offer(int fileNumber, Tox_File_Kind kind) => sync.handleEvent(
      ToxEventFileRecv(
        friendNumber: 0,
        fileNumber: fileNumber,
        kind: kind.value,
        fileSize: 10,
        filename: utf8.encode('a.txt'),
      ),
    );
    offer(0, Tox_File_Kind.TOX_FILE_KIND_AVATAR);
    offer(1, Tox_File_Kind.TOX_FILE_KIND_DATA);
    final offered = await db
        .watchTransfers(profileId)
        .firstWhere((transfers) => transfers.isNotEmpty);
    expect(offered.single.state, FileState.offered);
    expect(shown, [(ChatRef(profileId, _chat), null, '📎 a.txt', 'Me')]);
    expect(
      (await db
          .watchReceivedRanks(profileId, MessageFormats.none)
          .first)[_chat],
      hasLength(1),
    );
    expect(tox.fileControls, [
      (0, 0, Tox_File_Control.TOX_FILE_CONTROL_CANCEL),
    ]);

    await db.setTransferState(offered.single.id, FileState.cancelled);
    await _until(() => tox.fileControls.length == 2);
    expect(tox.fileControls.last, (
      0,
      1,
      Tox_File_Control.TOX_FILE_CONTROL_CANCEL,
    ));
    await _settle();
    expect(await contents(_chat), [
      isA<FileStarted>(),
      isA<FileEnded>().having((e) => e.ok, 'ok', false),
    ]);
  });

  test('ends the calls that were going on when it stopped', () async {
    final call = SyncEvent(
      graph: _chat,
      author: _me,
      parents: const [],
      rank: 0,
      time: 0,
      content: const Call(sender: 'Me', incoming: false, video: false),
    );
    final bytes = call.encode();
    await db.addSyncEvents(profileId, [(EventId.of(bytes), call, bytes)]);
    sync.start();
    await _settle();
    expect(await contents(_chat), [
      call.content,
      CallEnded(call: EventId.of(bytes)),
    ]);
  });
}
