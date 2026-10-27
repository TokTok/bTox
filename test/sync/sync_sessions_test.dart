import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/services/tox_sync.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/frames.dart';
import 'package:btox/sync/session_message.dart';
import 'package:btox/sync/setting.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_message_format.dart';
import '../mocks/fake_notifier.dart';
import '../mocks/fake_toxcore.dart';

final _home = PublicKey(Uint8List(32)..fillRange(0, 32, 1));
final _bob = PublicKey(Uint8List(32)..fillRange(0, 32, 3));

Future<void> _settle() => Future.delayed(const Duration(milliseconds: 50));

void main() {
  late Database db;
  late FakeToxcore tox;
  late Id<Profiles> profileId;
  late ToxSync sync;
  late List<Shown> shown;
  late List<(EventId, String?)> invited;
  late List<EventId> uninvited;

  setUp(() async {
    db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    tox = FakeToxcore();
    profileId = await db.addProfile(
      ProfilesCompanion.insert(
        signedIn: const Value(true),
        settings: ProfileSettings(nickname: 'Phone', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(0),
        home: Value(ToxAddress.of(_home, ToxAddressNospam(0))),
      ),
    );
    shown = [];
    invited = [];
    uninvited = [];
    sync = ToxSync(
      db,
      tox,
      profileId,
      maxMessageLength: 100,
      notifier: fakeNotifier(shown, invited: invited, uninvited: uninvited),
    );
    addTearDown(sync.dispose);
    sync.start();
    await _settle();
  });

  int numberOf(PublicKey publicKey) => tox.friends.indexOf(publicKey);

  void from(PublicKey publicKey, SessionMessage message) {
    for (final frame in frames(message.encode())) {
      sync.handleEvent(
        ToxEventFriendLosslessPacket(
          friendNumber: numberOf(publicKey),
          data: frame,
        ),
      );
    }
  }

  List<SessionMessage> sentTo(PublicKey publicKey) {
    final reassembler = Reassembler();
    final messages = [
      for (final (friendNumber, packet) in tox.losslessPackets)
        if (friendNumber == numberOf(publicKey))
          if (reassembler.push(packet) case final bytes?)
            SessionMessage.decode(bytes)!,
    ];
    tox.losslessPackets.removeWhere((sent) => sent.$1 == numberOf(publicKey));
    return messages;
  }

  /// What's sent to [publicKey], once anything is.
  Future<List<SessionMessage>> sentSoon(PublicKey publicKey) async {
    for (var i = 0; i < 100; i++) {
      if (tox.losslessPackets.any((sent) => sent.$1 == numberOf(publicKey))) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return sentTo(publicKey);
  }

  test('keeps the linked account from its home device', () async {
    sync.handleEvent(
      ToxEventFriendConnectionStatus(
        friendNumber: numberOf(_home),
        connectionStatus: Tox_Connection.TOX_CONNECTION_UDP,
      ),
    );
    expect(tox.friends, [_home]);
    expect(sentTo(_home), [const Hello(features: Features.accountSync)]);

    final account = GraphId.account(_home);
    final profile = SyncEvent(
      graph: account,
      author: _home,
      parents: const [],
      rank: 0,
      time: 0,
      content: const FactContent(
        subject: Subject.account(),
        value: FactValue.name('Me'),
      ),
    ).encode();
    final bob = SyncEvent(
      graph: account,
      author: _home,
      parents: [EventId.of(profile)],
      rank: 1,
      time: 0,
      content: WantFriend(pk: _bob),
    ).encode();
    from(_home, const Hello(features: Features.accountSync));
    expect(sentTo(_home), [const Summary([])]);
    from(_home, Events([profile, bob]));
    from(
      _home,
      const FactsUpdate([
        (Subject.account(), FactValue.connection(Connection.udp)),
      ], all: true),
    );
    await _settle();
    expect(await db.getSyncEvents(profileId), [profile, bob]);
    expect(
      (await db.watchLiveFacts(profileId).first).of(const Subject.account()),
      [const FactValue.connection(Connection.udp)],
    );

    // A message from the chat page becomes this device's event, once.
    final chat = GraphId.friend(_home, _bob);
    sentTo(_home);
    await db.addSend(profileId, chat, 'hello');
    await _settle();
    expect(await db.select(db.chatSends).get(), isEmpty);
    final [Events(events: [sent])] = sentTo(_home).cast<Events>();
    expect(
      SyncEvent.decode(sent),
      isA<SyncEvent>()
          .having((e) => e.graph, 'graph', chat)
          .having((e) => e.author, 'author', PublicKey(Uint8List(32)))
          .having(
            (e) => e.content,
            'content',
            Send(
              sender: 'Me',
              message: utf8.encode('hello'),
              kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
            ),
          ),
    );
    expect(
      await db.getSyncEvents(profileId),
      unorderedEquals([profile, bob, sent]),
    );

    // Each follows the one before, even when they're queued together.
    await db.addSend(profileId, chat, 'one');
    await db.addSend(profileId, chat, 'two');
    await _settle();
    final [Events(events: [one]), Events(events: [two])] = sentTo(_home)
        .cast<Events>();
    expect(SyncEvent.decode(one).parents, [EventId.of(sent)]);
    expect(SyncEvent.decode(two).parents, [EventId.of(one)]);

    // So does an answer to a file the home device was offered.
    final file = EventId(Uint8List(32)..[0] = 9);
    await db.addFileAnswer(profileId, chat, file, accepted: true);
    await _settle();
    expect(await db.select(db.fileAnswers).get(), isEmpty);
    final [Events(events: [answer])] = sentTo(_home).cast<Events>();
    expect(
      SyncEvent.decode(answer).content,
      FileAnswered(file: file, accepted: true),
    );

    // Reading further than the account knows tells the home, once.
    final upTo = (SyncEvent.decode(two).rank, EventId.of(two));
    await db.setRead(profileId, chat, upTo);
    await _settle();
    final [Events(events: [read])] = sentTo(_home).cast<Events>();
    expect(
      SyncEvent.decode(read).content,
      ReadUpTo(graph: chat, event: upTo.$2, rank: upTo.$1),
    );
    await db.setRead(profileId, chat, upTo);
    await _settle();
    expect(sentTo(_home), isEmpty);

    // A message nobody has read is shown, under its chat's name.
    final friend = SyncEvent(
      graph: account,
      author: _home,
      parents: [EventId.of(profile)],
      rank: 1,
      time: 0,
      content: FactContent(
        subject: Subject.friend(_bob),
        value: FactValue.name('Bob'),
      ),
    ).encode();
    final hi = SyncEvent(
      graph: chat,
      author: _home,
      parents: [EventId.of(two)],
      rank: SyncEvent.decode(two).rank + 1,
      time: 0,
      content: Received(
        sender: 'Bob',
        message: utf8.encode('hi'),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      ),
    ).encode();
    final paired = SyncEvent(
      graph: account,
      author: _home,
      parents: [EventId.of(friend)],
      rank: 2,
      time: 0,
      content: WantFriend(pk: PublicKey(Uint8List(32))),
    ).encode();
    from(_home, Events([friend, paired, hi]));
    await _settle();
    expect(shown, [(ChatRef(profileId, chat), 'Bob', 'hi', 'Me')]);
    expect(ChatRef.ofKey(shown.single.$1.key), shown.single.$1);

    // Without the home device, nobody's online state is known.
    sync.handleEvent(
      ToxEventFriendConnectionStatus(
        friendNumber: numberOf(_home),
        connectionStatus: Tox_Connection.TOX_CONNECTION_NONE,
      ),
    );
    await _settle();
    expect(await db.select(db.liveFacts).get(), isEmpty);
  });

  test("the home device's Hello before Tox sees it online gets its "
      'Summary', () async {
    final home = numberOf(_home);
    tox.unconnectedFriends.add(home);
    from(_home, const Hello(features: Features.accountSync));
    expect(sentTo(_home), isEmpty);

    tox.unconnectedFriends.clear();
    sync.handleEvent(
      ToxEventFriendConnectionStatus(
        friendNumber: home,
        connectionStatus: Tox_Connection.TOX_CONNECTION_UDP,
      ),
    );
    // Ours first, or the home device drops the Summary.
    expect(sentTo(_home), [
      const Hello(features: Features.accountSync),
      const Summary([]),
    ]);
  });

  test('moves files between here and the home device', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    sync.dispose();
    tox = FakeToxcore();
    sync = ToxSync(
      db,
      tox,
      profileId,
      maxMessageLength: 100,
      attachmentsDirectory: () async => dir.path,
    );
    addTearDown(sync.dispose);
    sync.start();
    await _settle();
    final home = numberOf(_home);
    sync.handleEvent(
      ToxEventFriendConnectionStatus(
        friendNumber: home,
        connectionStatus: Tox_Connection.TOX_CONNECTION_UDP,
      ),
    );
    from(_home, const Hello(features: Features.accountSync));
    final profile = SyncEvent(
      graph: GraphId.account(_home),
      author: _home,
      parents: const [],
      rank: 0,
      time: 0,
      content: const FactContent(
        subject: Subject.account(),
        value: FactValue.name('Me'),
      ),
    ).encode();
    final bob = SyncEvent(
      graph: GraphId.account(_home),
      author: _home,
      parents: [EventId.of(profile)],
      rank: 1,
      time: 0,
      content: WantFriend(pk: _bob),
    ).encode();
    from(_home, Events([profile, bob]));
    await _settle();
    sentTo(_home);

    // A picture sent here names its blob, which the home device fetches.
    final chat = GraphId.friend(_home, _bob);
    final cat = utf8.encode('cat');
    final picture = File('${dir.path}/cat.png')..writeAsBytesSync(cat);
    final catBlob = BlobId(Uint8List.fromList(sha256.convert(cat).bytes));
    await db.addFileSend(
      profileId,
      chat,
      FileContent(name: 'cat.png', size: 3, path: picture.path),
    );
    final [Events(events: [sent])] = (await sentSoon(_home)).cast<Events>();
    expect(
      SyncEvent.decode(sent).content,
      FileStarted(
        sender: 'Me',
        name: 'cat.png',
        size: 3,
        incoming: false,
        blob: catBlob,
      ),
    );
    from(_home, WantBlob(catBlob));
    expect(tox.fileSends, [(home, 3, '')]);
    expect(tox.fileSendKinds.single.$1, blobFileKind);
    expect(BlobId(tox.fileSendKinds.single.$2), catBlob);
    for (final (position, length) in [(0, 3), (3, 0)]) {
      sync.handleEvent(
        ToxEventFileChunkRequest(
          friendNumber: home,
          fileNumber: 0,
          position: position,
          length: length,
        ),
      );
    }
    expect(tox.fileChunks.single.$4, cat);
    await db
        .watchTransfers(profileId)
        .firstWhere((t) => t.single.state == FileState.done);

    // Bob's file, once the home device has it, is fetched here.
    final dog = utf8.encode('dog');
    final dogBlob = BlobId(Uint8List.fromList(sha256.convert(dog).bytes));
    final offered = SyncEvent(
      graph: chat,
      author: _home,
      parents: [EventId.of(sent)],
      rank: 1,
      time: 0,
      content: const FileStarted(
        sender: 'Bob',
        name: 'dog.png',
        size: 3,
        incoming: true,
      ),
    ).encode();
    final ended = SyncEvent(
      graph: chat,
      author: _home,
      parents: [EventId.of(offered)],
      rank: 2,
      time: 0,
      content: FileEnded(file: EventId.of(offered), ok: true, blob: dogBlob),
    ).encode();
    // Its end can come first.
    from(_home, Events([ended]));
    await _settle();
    from(_home, Events([offered]));
    await _settle();
    expect(sentTo(_home), contains(WantBlob(dogBlob)));

    // Only the blob asked for is taken.
    tox.fileIds[(home, 1)] = catBlob.bytes;
    tox.fileIds[(home, 2)] = dogBlob.bytes;
    for (final fileNumber in [1, 2]) {
      sync.handleEvent(
        ToxEventFileRecv(
          friendNumber: home,
          fileNumber: fileNumber,
          kind: blobFileKind,
          fileSize: 3,
          filename: Uint8List(0),
        ),
      );
    }
    expect(tox.fileControls, [
      (home, 1, Tox_File_Control.TOX_FILE_CONTROL_CANCEL),
      (home, 2, Tox_File_Control.TOX_FILE_CONTROL_RESUME),
    ]);
    for (final (position, data) in [(0, dog), (3, Uint8List(0))]) {
      sync.handleEvent(
        ToxEventFileRecvChunk(
          friendNumber: home,
          fileNumber: 2,
          position: position,
          data: data,
        ),
      );
    }
    final fetched = await db
        .watchTransfers(profileId)
        .map((t) => t.where((t) => t.incoming && t.state == FileState.done))
        .firstWhere((t) => t.isNotEmpty);
    expect(fetched.single.event, EventId.of(offered));
    expect(File(fetched.single.path).readAsBytesSync(), dog);

    // One the home device no longer has is given up.
    final cowBlob = BlobId(Uint8List(32)..[0] = 4);
    final cow = SyncEvent(
      graph: chat,
      author: _home,
      parents: [EventId.of(ended)],
      rank: 3,
      time: 0,
      content: const FileStarted(
        sender: 'Bob',
        name: 'cow.png',
        size: 3,
        incoming: true,
      ),
    ).encode();
    from(
      _home,
      Events([
        cow,
        SyncEvent(
          graph: chat,
          author: _home,
          parents: [EventId.of(cow)],
          rank: 4,
          time: 0,
          content: FileEnded(file: EventId.of(cow), ok: true, blob: cowBlob),
        ).encode(),
      ]),
    );
    expect(await sentSoon(_home), contains(WantBlob(cowBlob)));
    from(_home, NoBlob(cowBlob));
    bool givenUp(Transfer t) =>
        t.blobId == cowBlob && t.state == FileState.cancelled;
    await db.watchTransfers(profileId).firstWhere((t) => t.any(givenUp));
  });

  test("drops events it can't read, which then sync again", () async {
    sync.dispose();
    // An event in an older encoding, and how far it was read.
    final old = Uint8List.fromList([0x97, 0x01, 0xc0, 0xc0, 0x90, 0, 0, 0x91]);
    final chat = GraphId.friend(_home, _bob);
    await db
        .into(db.syncEvents)
        .insert(
          SyncEventsCompanion.insert(
            profileId: profileId,
            id: EventId.of(old),
            graph: chat,
            rank: 0,
            received: true,
            bytes: old,
          ),
        );
    await db.setRead(profileId, chat, (0, EventId.of(old)));
    expect(await db.watchSyncEvents(profileId, chat).first, isEmpty);

    final restarted = ToxSync(db, tox, profileId, maxMessageLength: 100);
    addTearDown(restarted.dispose);
    restarted.start();
    await _settle();
    expect(await db.getSyncEvents(profileId), isEmpty);
    expect(await db.select(db.chatReads).get(), isEmpty);
  });

  test('notifies each message once, never history synced again', () async {
    final account = GraphId.account(_home);
    final chat = GraphId.friend(_home, _bob);
    final events = <Uint8List>[];
    Uint8List add(GraphId graph, int time, EventContent content) {
      final parents = [
        for (final bytes in events)
          if (SyncEvent.decode(bytes).graph == graph) EventId.of(bytes),
      ].reversed.take(1).toList();
      final bytes = SyncEvent(
        graph: graph,
        author: _home,
        parents: parents,
        rank: events.where((e) => SyncEvent.decode(e).graph == graph).length,
        time: time,
        content: content,
      ).encode();
      events.add(bytes);
      return bytes;
    }

    Received said(String text) => Received(
      sender: 'Bob',
      message: utf8.encode(text),
      kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
    );
    add(
      account,
      100,
      FactContent(subject: Subject.friend(_bob), value: FactValue.name('Bob')),
    );
    add(account, 100, WantFriend(pk: PublicKey(Uint8List(32))));
    add(chat, 50, said('from before the pairing'));
    add(chat, 150, said('after'));

    final cancelled = <ChatRef>[];
    // A fresh Tox each start, as after a relaunch.
    late FakeToxcore phoneTox;
    ToxSync start() {
      phoneTox = FakeToxcore();
      final sync = ToxSync(
        db,
        phoneTox,
        profileId,
        maxMessageLength: 100,
        knownFormats: const [FakeMessageFormat()],
        notifier: fakeNotifier(shown, cancelled: cancelled),
      );
      addTearDown(sync.dispose);
      sync.start();
      return sync;
    }

    void send(ToxSync sync, SessionMessage message) {
      for (final frame in frames(message.encode())) {
        sync.handleEvent(
          ToxEventFriendLosslessPacket(
            friendNumber: phoneTox.friends.indexOf(_home),
            data: frame,
          ),
        );
      }
    }

    sync.dispose();
    var phone = start();
    await _settle();
    send(phone, const Hello(features: Features.accountSync));
    send(phone, Events(events));
    await _settle();
    expect([for (final s in shown) s.$3], ['after']);

    // A force-stop and relaunch, with the home replaying the chat to a phone
    // that lost its copy, as when it drops events it can't read.
    phone.dispose();
    await db.delete(db.syncEvents).go();
    shown.clear();
    phone = start();
    await _settle();
    send(phone, const Hello(features: Features.accountSync));
    send(phone, Events(events));
    await _settle();
    expect(shown, isEmpty);

    send(phone, Events([add(chat, 200, said('new'))]));
    await _settle();
    expect([for (final s in shown) s.$3], ['new']);

    // So does a file Bob sent the home device.
    send(
      phone,
      Events([
        add(
          chat,
          250,
          const FileStarted(
            sender: 'Bob',
            name: 'cat.jpg',
            size: 3,
            incoming: true,
          ),
        ),
      ]),
    );
    await _settle();
    expect([for (final s in shown) s.$3], ['new', '📎 cat.jpg']);

    // A message sent again, as a format knows it, counts and notifies once.
    final again = Received(
      sender: 'Bob',
      message: FakeMessageFormat.encode('again', '1'),
      kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
    );
    for (final time in [300, 400]) {
      send(phone, Events([add(chat, time, again)]));
      await _settle();
    }
    expect([for (final s in shown) s.$3], ['new', '📎 cat.jpg', 'again']);
    expect(
      (await db.watchReceivedRanks(profileId, withFakeFormat).first)[chat],
      hasLength(5),
    );

    // Read on another device, the chat's notification goes.
    final newest = SyncEvent.decode(events.last);
    send(
      phone,
      Events([
        add(
          account,
          500,
          ReadUpTo(
            graph: chat,
            event: EventId.of(events.last),
            rank: newest.rank,
          ),
        ),
      ]),
    );
    await _settle();
    expect(cancelled, [ChatRef(profileId, chat)]);
  });

  test(
    'merged chats notify once, as who said it, and merge on request',
    () async {
      final account = GraphId.account(_home);
      final group = GroupChat(GroupChatId(Uint8List(32)..[0] = 1));
      final conference = ConferenceChat(ConferenceId(Uint8List(32)..[0] = 2));
      final groupBot = PublicKey(Uint8List(32)..fillRange(0, 32, 4));
      final conferenceBot = PublicKey(Uint8List(32)..fillRange(0, 32, 5));
      final ranks = <GraphId, int>{};
      Uint8List add(GraphId graph, int time, EventContent content) => SyncEvent(
        graph: graph,
        author: _home,
        parents: const [],
        rank: ranks[graph] = (ranks[graph] ?? -1) + 1,
        time: time,
        content: content,
      ).encode();
      Received said(PublicKey from, String sender, String text) => Received(
        from: from,
        sender: sender,
        message: utf8.encode(text),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      );

      from(_home, const Hello(features: Features.accountSync));
      from(
        _home,
        Events([
          add(account, 0, WantFriend(pk: PublicKey(Uint8List(32)))),
          for (final chat in [group, conference])
            for (final value in [FactValue.name('Tox'), FactValue.joined(true)])
              add(
                account,
                0,
                FactContent(subject: Subject.chat(chat), value: value),
              ),
          add(
            account,
            0,
            MergeChat(
              chat: conference,
              bot: conferenceBot,
              into: group,
              intoBot: groupBot,
              merged: true,
            ),
          ),
        ]),
      );
      await _settle();
      for (final event in [
        add(group.graph, 100, said(_bob, 'Bob', 'hi')),
        add(conference.graph, 101, said(conferenceBot, '!', '<Bob> hi')),
        add(conference.graph, 200, said(conferenceBot, '!', '<Carol> yo')),
      ]) {
        from(_home, Events([event]));
        await _settle();
      }
      expect(shown, [
        for (final text in ['Bob: hi', 'Carol: yo'])
          (ChatRef(profileId, group.graph), 'Tox', text, null),
      ]);

      sentTo(_home);
      await db.showApart(
        profileId,
        group.graph,
        AccountState.of(await db.watchSyncEvents(profileId, account).first)
            .merges,
      );
      await _settle();
      expect(await db.select(db.chatMerges).get(), isEmpty);
      final [Events(events: [merge])] = sentTo(_home).cast<Events>();
      expect(
        SyncEvent.decode(merge).content,
        MergeChat(
          chat: conference,
          bot: conferenceBot,
          into: group,
          intoBot: groupBot,
          merged: false,
        ),
      );
    },
  );

  test(
    "a relay bot's chat notifies as who said it, and stops on request",
    () async {
      final account = GraphId.account(_home);
      final conference = ConferenceChat(ConferenceId(Uint8List(32)..[0] = 2));
      final bot = PublicKey(Uint8List(32)..fillRange(0, 32, 5));
      final ranks = <GraphId, int>{};
      Uint8List add(GraphId graph, int time, EventContent content) => SyncEvent(
        graph: graph,
        author: _home,
        parents: const [],
        rank: ranks[graph] = (ranks[graph] ?? -1) + 1,
        time: time,
        content: content,
      ).encode();

      from(_home, const Hello(features: Features.accountSync));
      from(
        _home,
        Events([
          add(account, 0, WantFriend(pk: PublicKey(Uint8List(32)))),
          for (final value in [FactValue.name('Tox'), FactValue.joined(true)])
            add(
              account,
              0,
              FactContent(subject: Subject.chat(conference), value: value),
            ),
          add(account, 0, RelayBot(chat: conference, bot: bot, relays: true)),
        ]),
      );
      await _settle();
      from(
        _home,
        Events([
          add(
            conference.graph,
            100,
            Received(
              from: bot,
              sender: '!',
              message: utf8.encode('<Carol> yo'),
              kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
            ),
          ),
        ]),
      );
      await _settle();
      expect(shown, [
        (ChatRef(profileId, conference.graph), 'Tox', 'Carol: yo', null),
      ]);

      sentTo(_home);
      await db.addRelayBot(
        profileId,
        chat: conference.graph,
        bot: bot,
        relays: false,
      );
      await _settle();
      expect(await db.select(db.relayBots).get(), isEmpty);
      final [Events(events: [stop])] = sentTo(_home).cast<Events>();
      expect(
        SyncEvent.decode(stop).content,
        RelayBot(chat: conference, bot: bot, relays: false),
      );
    },
  );

  test('a muted chat notifies only of mentions; settings go on '
      'request', () async {
    final account = GraphId.account(_home);
    final group = GroupChat(GroupChatId(Uint8List(32)..[0] = 3));
    var rank = 0;
    Uint8List add(GraphId graph, int time, EventContent content) => SyncEvent(
      graph: graph,
      author: _home,
      parents: const [],
      rank: rank++,
      time: time,
      content: content,
    ).encode();
    Uint8List say(String text) => add(
      group.graph,
      DateTime.now().millisecondsSinceEpoch,
      Received(
        from: PublicKey(Uint8List(32)..fillRange(0, 32, 6)),
        sender: 'Carol',
        message: utf8.encode(text),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      ),
    );
    final scope = Scope.conversation(group.graph);
    SettingContent mute(DateTime? until) => SettingContent(
      scope: scope,
      setting: Kept(Setting.mute(until: until, mentions: true)),
    );

    from(_home, const Hello(features: Features.accountSync));
    from(
      _home,
      Events([
        add(account, 0, WantFriend(pk: PublicKey(Uint8List(32)))),
        for (final value in [
          FactValue.name('Tox'),
          FactValue.joined(true),
          FactValue.selfName('iphy'),
        ])
          add(
            account,
            0,
            FactContent(subject: Subject.chat(group), value: value),
          ),
        add(account, 0, mute(null)),
      ]),
    );
    await _settle();
    from(
      _home,
      Events([say('hello all'), say('iphyfan here'), say('IPHY: ping')]),
    );
    await _settle();
    expect(shown, [
      (ChatRef(profileId, group.graph), 'Tox', 'Carol: IPHY: ping', null),
    ]);

    // One that has ended holds no more.
    shown.clear();
    from(_home, Events([add(account, 0, mute(DateTime(2000))), say('later')]));
    await _settle();
    expect(shown, [
      (ChatRef(profileId, group.graph), 'Tox', 'Carol: later', null),
    ]);

    sentTo(_home);
    final until = DateTime.fromMillisecondsSinceEpoch(1800000000000);
    await db.setSetting(
      profileId,
      scope,
      Kept(Setting.mute(until: until, mentions: false)),
    );
    await _settle();
    expect(await db.select(db.settingChanges).get(), isEmpty);
    final [Events(events: [muted])] = sentTo(_home).cast<Events>();
    expect(
      SyncEvent.decode(muted).content,
      SettingContent(
        scope: scope,
        setting: Kept(Setting.mute(until: until, mentions: false)),
      ),
    );

    // Clearing it goes the same way.
    await db.clearSetting(profileId, scope, Setting.muteKind);
    await _settle();
    expect(await db.select(db.settingChanges).get(), isEmpty);
    final [Events(events: [cleared])] = sentTo(_home).cast<Events>();
    expect(
      SyncEvent.decode(cleared).content,
      ClearSetting(scope: scope, kind: Setting.muteKind),
    );
  });

  test('invites to the linked account are told of until answered, here or '
      'elsewhere', () async {
    final account = GraphId.account(_home);
    var rank = -1;
    NewEvent add(int time, EventContent content, {PublicKey? author}) {
      final event = SyncEvent(
        graph: account,
        author: author ?? _home,
        parents: const [],
        rank: ++rank,
        time: time,
        content: content,
      );
      final bytes = event.encode();
      return (EventId.of(bytes), event, bytes);
    }

    NewEvent invite(String name) => add(
      100,
      ChatInvite(
        from: _bob,
        kind: ChatKind.group,
        name: name,
        invite: Uint8List.fromList([1, 2, 3]),
      ),
    );

    from(_home, const Hello(features: Features.accountSync));
    final (here, _, hereBytes) = invite('here');
    final (elsewhere, _, elsewhereBytes) = invite('elsewhere');
    from(
      _home,
      Events([
        add(0, WantFriend(pk: PublicKey(Uint8List(32)))).$3,
        add(
          0,
          FactContent(
            subject: Subject.friend(_bob),
            value: const FactValue.name('Bob'),
          ),
        ).$3,
        hereBytes,
        elsewhereBytes,
      ]),
    );
    await _settle();
    expect(invited, [(here, 'Bob'), (elsewhere, 'Bob')]);

    sentTo(_home);
    await db.addInviteAnswer(
      profileId,
      here,
      accepted: true,
      password: 'secret',
    );
    await _settle();
    expect(await db.select(db.inviteAnswers).get(), isEmpty);
    final [Events(events: [answer])] = sentTo(_home).cast<Events>();
    expect(
      SyncEvent.decode(answer).content,
      AnswerInvite(invite: here, join: true, password: 'secret'),
    );
    expect(uninvited, [here]);

    from(
      _home,
      Events([
        add(
          200,
          AnswerInvite(invite: elsewhere, join: false),
          author: PublicKey(Uint8List(32)..fillRange(0, 32, 9)),
        ).$3,
      ]),
    );
    await _settle();
    expect(uninvited, [here, elsewhere]);
  });
}
