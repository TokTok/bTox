import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/models/crypto.dart';
import 'package:btox/packets/messagepack.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/codec.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/frames.dart';
import 'package:btox/sync/pairing.dart';
import 'package:btox/sync/session_message.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/sync/store.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';

// Every device must encode and identify these the same way.
final _helloPacket = Uint8List.fromList([
  0xb0,
  0x03,
  0x92,
  0x00,
  0x92,
  0x01,
  0x01,
]);
const _vectorGraph =
    '6fcb85e59b8be9d9e8851d580aaa9237821cddedab6214ee43b0a08ccafbaadf';
const _vectorEvent =
    '920396c4206fcb85e59b8be9d9e8851d580aaa9237821cddedab6214ee43b0a08ccafbaa'
    'dfc420010101010101010101010101010101010101010101010101010101010101010190'
    '00cf0000018bcfe568009246929201c42002020202020202020202020202020202020202'
    '020202020202020202020202029200a3426f62';
const _vectorId =
    '76128f570001c241a587d2c3d7db5da9cebbd7bcd07daa74084b10bde1e0f098';
const _vectorLink =
    'tox:0101010101010101010101010101010101010101010101010101010101010101010203'
    '040206?pair=00112233445566778899aabbccddeeff';
const _vectorSummary =
    '92019192c4206fcb85e59b8be9d9e8851d580aaa9237821cddedab6214ee43b0a08ccafb'
    'aadfc42081e78eb184795940d60d99e6491b4c553f45cb9c0912aea10a4ed737132f2512';
const _vectorSend = '920193a24d65c40568690000ff01';
const _vectorFileAnswered =
    '920792c42001000000000000000000000000000000000000000000000000000000000000'
    '00c3';
const _vectorMute =
    '924b929201c4200101010101010101010101010101010101010101010101010101010101'
    '01010192009291cf0000018bcfe56800c3';
const _vectorPictureFormat =
    '924b929201c4200101010101010101010101010101010101010101010101010101010101'
    '01010192019101';
const _vectorClearSetting =
    '924c929201c4200101010101010101010101010101010101010101010101010101010101'
    '01010100';
const _vectorUnreadableMute =
    '924b929201c4200101010101010101010101010101010101010101010101010101010101'
    '010101920091a178';

// A mute with a third field, from a newer version, and with `mentions`
// changed by this one.
const _vectorNewerMute = '92009390c2c3';
const _vectorEditedMute = '92009390c3c3';
const _vectorFile =
    '920596a24d6590a76361742e706e6703c291c42077af778b51abd4a3c51c5ddd97204a9c'
    '3ae614ebccb75a606c3b6865aed6744e';
const _vectorFact =
    '9246929203929200c4200303030303030303030303030303030303030303030303030303'
    '030303030303c42002020202020202020202020202020202020202020202020202020202'
    '02020202920601';
const _vectorWant = '924792009200a469706879';
const _vectorChatInvite =
    '924894c42002020202020202020202020202020202020202020202020202020202020202'
    '0200a3546f78c403010203';
const _vectorAnswerInvite =
    '924993c42005050505050505050505050505050505050505050505050505050505050505'
    '05c391a6736563726574';
const _vectorAnswerInviteOld =
    '924992c42005050505050505050505050505050505050505050505050505050505050505'
    '05c3';
const _vectorInviteJoined =
    '924a93c42005050505050505050505050505050505050505050505050505050505050505'
    '05919200c420030303030303030303030303030303030303030303030303030303030303'
    '0303c2';
const _vectorInviteJoinedOld =
    '924a92c42005050505050505050505050505050505050505050505050505050505050505'
    '05919200c420030303030303030303030303030303030303030303030303030303030303'
    '0303';
const _vectorFacts =
    '92089292929201c420020202020202020202020202020202020202020202020202020202'
    '0202020202920302929203929201c4200101010101010101010101010101010101010101'
    '010101010101010101010101c42003030303030303030303030303030303030303030303'
    '03030303030303030303920ec2c2';
const _vectorWantBlob =
    '9206c42077af778b51abd4a3c51c5ddd97204a9c3ae614ebccb75a606c3b6865aed6744e';

final _alice = PublicKey(Uint8List(32)..fillRange(0, 32, 1));
final _bob = PublicKey(Uint8List(32)..fillRange(0, 32, 2));

Uint8List _bytes(String value) => Uint8List.fromList(hex.decode(value));

void main() {
  test('encodes and identifies events', () {
    final graph = GraphId.account(_alice);
    final bytes = _bytes(_vectorEvent);
    final event = SyncEvent.decode(bytes);
    expect(
      event,
      SyncEvent(
        graph: graph,
        author: _alice,
        parents: const [],
        rank: 0,
        time: 1700000000000,
        content: FactContent(
          subject: Subject.friend(_bob),
          value: FactValue.name('Bob'),
        ),
      ),
    );
    expect(event.encode(), bytes);
    expect(graph, GraphId.fromJson(_vectorGraph));
    expect(EventId.of(bytes), EventId.fromJson(_vectorId));
    expect(
      Summary([
        (graph, HeadsDigest.of([EventId.of(bytes)])),
      ]).encode(),
      _bytes(_vectorSummary),
    );
    final send = event.copyWith(
      content: Send(
        sender: 'Me',
        message: Uint8List.fromList([0x68, 0x69, 0, 0, 0xff]),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_ACTION,
      ),
    );
    expect(hex.encode(send.encode()), endsWith(_vectorSend));
    final answered = event.copyWith(
      content: FileAnswered(
        file: EventId(Uint8List(32)..[0] = 1),
        accepted: true,
      ),
    );
    expect(hex.encode(answered.encode()), endsWith(_vectorFileAnswered));
    expect(SyncEvent.decode(answered.encode()), answered);
    final scope = Scope.conversation(GraphId(Uint8List.fromList(_alice.bytes)));
    for (final (content, vector) in [
      (
        SettingContent(
          scope: scope,
          setting: Kept(
            Setting.mute(
              until: DateTime.fromMillisecondsSinceEpoch(1700000000000),
              mentions: true,
            ),
          ),
        ),
        _vectorMute,
      ),
      (
        SettingContent(
          scope: scope,
          setting: const Kept(Setting.pictureFormat(PictureEncoding.qoi)),
        ),
        _vectorPictureFormat,
      ),
      (ClearSetting(scope: scope, kind: Setting.muteKind), _vectorClearSetting),
    ]) {
      final setting = event.copyWith(content: content);
      expect(hex.encode(setting.encode()), endsWith(vector));
      expect(SyncEvent.decode(setting.encode()), setting);
    }
    // A known kind whose fields don't decode is kept, as unknown.
    final unreadable = hex.encode(
      event.copyWith(content: ClearSetting(scope: scope, kind: 0)).encode(),
    );
    expect(
      SyncEvent.decode(
        _bytes(
          unreadable.replaceFirst(_vectorClearSetting, _vectorUnreadableMute),
        ),
      ).content,
      SettingContent(scope: scope, setting: const Kept(Setting.unknown(0))),
    );
    // A newer version's mute keeps the field this one doesn't know through
    // an edit here.
    final newer = event.copyWith(
      content: SettingContent(
        scope: const Scope.account(),
        setting: Kept.read(
          const Setting.mute(mentions: false),
          _bytes(_vectorNewerMute),
        ),
      ),
    );
    final edited = AccountState.of([
      (EventId.of(newer.encode()), SyncEvent.decode(newer.encode())),
    ]).edit<Mute>(const Scope.account(), (m) => m.copyWith(mentions: true));
    expect(hex.encode(edited!.bytes!), _vectorEditedMute);
    final blob = BlobId(
      Uint8List.fromList(sha256.convert(utf8.encode('cat')).bytes),
    );
    final file = event.copyWith(
      content: FileStarted(
        sender: 'Me',
        name: 'cat.png',
        size: 3,
        incoming: false,
        blob: blob,
      ),
    );
    expect(hex.encode(file.encode()), endsWith(_vectorFile));
    expect(SyncEvent.decode(file.encode()), file);
    // A home device's file of unknown size, as toxcore gives it.
    final unknownSize = hex
        .encode(file.encode())
        .replaceFirst('a76361742e706e6703', 'a76361742e706e67cf${'ff' * 8}');
    expect(
      SyncEvent.decode(Uint8List.fromList(hex.decode(unknownSize))).content,
      isA<FileStarted>().having((f) => f.size, 'size', 0x7fffffffffffffff),
    );
    expect(
      () => SessionMessage.decode(
        Uint8List.fromList(hex.decode('9207c41f${'00' * 31}')),
      ),
      throwsFormatException,
    );
    expect(hex.encode(WantBlob(blob).encode()), _vectorWantBlob);
    final group = ChatId.group(GroupChatId(Uint8List(32)..fillRange(0, 32, 3)));
    final fact = event.copyWith(
      content: FactContent(
        subject: Subject.peer(group, _bob),
        value: const FactValue.role(Role.moderator),
      ),
    );
    expect(hex.encode(fact.encode()), endsWith(_vectorFact));
    expect(SyncEvent.decode(fact.encode()), fact);
    final wish = event.copyWith(
      content: const Wish(
        subject: Subject.account(),
        value: FactValue.name('iphy'),
      ),
    );
    expect(hex.encode(wish.encode()), endsWith(_vectorWant));
    expect(SyncEvent.decode(wish.encode()), wish);
    final five = EventId(Uint8List(32)..fillRange(0, 32, 5));
    for (final (content, vector) in [
      (
        ChatInvite(
          from: _bob,
          kind: ChatKind.group,
          name: 'Tox',
          invite: Uint8List.fromList([1, 2, 3]),
        ),
        _vectorChatInvite,
      ),
      (
        AnswerInvite(invite: five, join: true, password: 'secret'),
        _vectorAnswerInvite,
      ),
      (InviteJoined(invite: five, chat: group), _vectorInviteJoined),
    ]) {
      final invite = event.copyWith(content: content);
      expect(hex.encode(invite.encode()), endsWith(vector));
      expect(SyncEvent.decode(invite.encode()), invite);
    }
    // As versions before passwords wrote them.
    for (final (old, current, content) in [
      (
        _vectorAnswerInviteOld,
        _vectorAnswerInvite,
        AnswerInvite(invite: five, join: true),
      ),
      (
        _vectorInviteJoinedOld,
        _vectorInviteJoined,
        InviteJoined(invite: five, chat: group),
      ),
    ]) {
      final encoded = hex
          .encode(event.copyWith(content: content).encode())
          .replaceAll(current, old);
      expect(
        SyncEvent.decode(Uint8List.fromList(hex.decode(encoded))).content,
        content,
      );
    }
    final device = PublicKey(Uint8List(32)..fillRange(0, 32, 3));
    final conference = ChatId.conference(
      ConferenceId(Uint8List(32)..fillRange(0, 32, 1)),
    );
    final facts = FactsUpdate([
      (Subject.friend(_bob), const FactValue.connection(Connection.udp)),
      (Subject.peer(conference, device), const FactValue.present(false)),
    ], all: false);
    expect(hex.encode(facts.encode()), _vectorFacts);
    expect(frames(const Hello(features: Features.accountSync).encode()), [
      _helloPacket,
    ]);
  });

  test('invites follow their last answer', () {
    final store = EventStore();
    final account = GraphId.account(_alice);
    EventId add(EventContent content) {
      final (id, _, bytes) = store.author(
        account,
        _alice,
        DateTime(2026),
        content,
      );
      store.insert(bytes);
      return id;
    }

    EventId invite(String name) => add(
      ChatInvite(
        from: _bob,
        kind: ChatKind.conference,
        name: name,
        invite: Uint8List.fromList([1, 2, 3]),
      ),
    );
    InviteStatus? status(EventId id) =>
        AccountState.of(rankOrder(store.eventsIn(account))).invites[id]?.status;

    final refused = invite('refused');
    final declined = invite('declined');
    final pending = invite('pending');
    final chat = ChatId.conference(
      ConferenceId(Uint8List(32)..fillRange(0, 32, 4)),
    );
    add(AnswerInvite(invite: refused, join: true, password: 'secret'));
    expect(status(refused), InviteStatus.joining);
    add(InviteJoined(invite: refused, chat: chat));
    expect(status(refused), InviteStatus.joined);
    add(AnswerInvite(invite: declined, join: false));
    expect(status(declined), InviteStatus.declined);
    expect(status(pending), InviteStatus.pending);

    // The chat can turn the account away later, and the invite keeps the
    // chat it joined.
    add(InviteJoined(invite: refused, needsPassword: true));
    expect(
      AccountState.of(rankOrder(store.eventsIn(account))).invites[refused],
      AccountInvite(
        from: _bob,
        kind: ChatKind.conference,
        name: 'refused',
        status: InviteStatus.failed,
        chat: chat,
        needsPassword: true,
      ),
    );
  });

  test('concurrent settings end the same in any order', () {
    final account = GraphId.account(_alice);
    const scope = Scope.account();
    final root = SyncEvent(
      graph: account,
      author: _alice,
      parents: const [],
      rank: 0,
      time: 0,
      content: const Notice(text: ''),
    );
    final rootId = EventId.of(root.encode());
    (EventId, SyncEvent) sibling(EventContent content) {
      final event = SyncEvent(
        graph: account,
        author: _bob,
        parents: [rootId],
        rank: 1,
        time: 0,
        content: content,
      );
      return (EventId.of(event.encode()), event);
    }

    SettingContent mute(bool mentions) => SettingContent(
      scope: scope,
      setting: Kept(Setting.mute(mentions: mentions)),
    );
    for (final (a, b) in [
      (sibling(mute(true)), sibling(mute(false))),
      (
        sibling(mute(true)),
        sibling(const ClearSetting(scope: scope, kind: Setting.muteKind)),
      ),
    ]) {
      final state = AccountState.of([(rootId, root), a, b]);
      expect(AccountState.of([(rootId, root), b, a]), state);
      // Of equal ranks, the higher ID wins.
      expect(state, AccountState.of([a.$1.compareTo(b.$1) > 0 ? a : b]));
      // The same when they come one at a time, and from the start again.
      for (final events in [
        [(rootId, root), a, b],
        [(rootId, root), b, a],
      ]) {
        final fold = AccountFold();
        for (var count = 1; count < events.length; count++) {
          fold.update(events.sublist(0, count));
        }
        expect(fold.update(events), state);
        expect(fold.update(events.sublist(0, 1)), AccountState.of([events[0]]));
      }
    }
  });

  test('events round trip', () {
    final id = EventId(Uint8List(32));
    for (final content in [
      WantFriend(
        pk: _bob,
        requestMessage: 'hi',
        nospam: ToxAddressNospam(0x01020304),
      ),
      UnwantFriend(pk: _bob),
      ReadUpTo(graph: GraphId.account(_alice), event: id, rank: 7),
      FriendRequested(pk: _bob, message: 'hi'),
      SettingContent(
        scope: Scope.conversation(GraphId.account(_alice)),
        setting: Kept(
          Setting.mute(
            until: DateTime.fromMillisecondsSinceEpoch(1700000000000),
            mentions: true,
          ),
        ),
      ),
      const SettingContent(
        scope: Scope.account(),
        setting: Kept(Setting.pictureFormat(PictureEncoding.qoi)),
      ),
      const ClearSetting(scope: Scope.account(), kind: Setting.muteKind),
      Received(
        from: _bob,
        sender: 'Bob',
        message: utf8.encode('hi'),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_ACTION,
      ),
      Send(
        sender: 'Me',
        message: utf8.encode('hello'),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      ),
      Sent(intent: id),
      Delivered(intent: id),
      const Notice(text: 'Bob joined'),
      FileStarted(
        sender: 'Bob',
        fileId: FileId(Uint8List(32)),
        name: 'cat.png',
        size: 1234,
        incoming: true,
      ),
      FileEnded(file: id, ok: true, blob: BlobId(Uint8List(32))),
      const UnknownContent(99),
    ]) {
      final event = SyncEvent(
        graph: GraphId.account(_alice),
        author: _alice,
        parents: [id],
        rank: 1,
        time: -1,
        content: content,
      );
      expect(SyncEvent.decode(event.encode()), event);
    }
  });

  test('session messages round trip', () {
    final id = EventId(Uint8List(32));
    final graph = GraphId.account(_alice);
    for (final message in [
      const Hello(features: Features.accountSync),
      Summary([
        (graph, HeadsDigest.of([id])),
      ]),
      Heads(graph: graph, heads: [id]),
      Want([id]),
      Events([
        Uint8List.fromList([1, 2, 3]),
      ]),
      History(graph: graph, before: [id], limit: 50),
      FactsUpdate([
        (Subject.friend(_alice), const FactValue.connection(Connection.udp)),
        (
          Subject.peer(ChatId.group(GroupChatId(Uint8List(32))), _bob),
          const FactValue.role(Role.moderator),
        ),
      ], all: true),
      WantBlob(BlobId(Uint8List(32))),
      NoBlob(BlobId(Uint8List(32))),
    ]) {
      expect(SessionMessage.decode(message.encode()), message);
    }
  });

  test('newer and older versions are understood', () {
    // Fields and messages this version doesn't know are skipped.
    final newer = ArrayWriter()
      ..uint(0)
      ..array(
        ArrayWriter()
          ..uint(1)
          ..uint(1)
          ..string('future'),
      );
    expect(
      SessionMessage.decode(newer.encode()),
      const Hello(features: Features.accountSync),
    );
    final unknown = ArrayWriter()
      ..uint(99)
      ..string('?');
    expect(SessionMessage.decode(unknown.encode()), isNull);

    // A field appended since is absent in an older event.
    final older = ArrayWriter()
      ..uint(eventVersion)
      ..array(
        ArrayWriter()
          ..bin(GraphId.account(_alice).bytes)
          ..bin(_alice.bytes)
          ..array(ArrayWriter())
          ..uint(0)
          ..sint(0)
          ..array(
            ArrayWriter()
              ..uint(64)
              ..array(
                ArrayWriter()
                  ..bin(_bob.bytes)
                  ..optString('hi'),
              ),
          ),
      );
    final bytes = older.encode();
    expect(
      SyncEvent.decode(bytes).content,
      WantFriend(pk: _bob, requestMessage: 'hi'),
    );

    // Trailing bytes would give the same event another ID.
    expect(
      () => SyncEvent.decode(Uint8List.fromList([...bytes, 0])),
      throwsFormatException,
    );
  });

  test('reads newer or malformed values as unknown', () {
    T read<T>(T Function(Fields) reader, ArrayWriter value) =>
        reader(Fields(Unpacker((ArrayWriter()..array(value)).encode())));
    ArrayWriter mute(void Function(ArrayWriter) until) {
      final fields = ArrayWriter();
      until(fields);
      return ArrayWriter()
        ..uint(Setting.muteKind)
        ..array(fields..flag(true));
    }

    // A status of a newer version, which gave it a payload.
    expect(
      read(
        readValue,
        ArrayWriter()
          ..uint(2)
          ..array(
            ArrayWriter()
              ..uint(5)
              ..uint(0),
          ),
      ),
      const FactValue.unknown(2),
    );
    // A mute with an until that isn't a time.
    for (final until in <void Function(ArrayWriter)>[
      (w) => w.array(
        ArrayWriter()
          ..uint(1)
          ..uint(2),
      ),
      (w) => w.raw(Uint8List.fromList([0xc0])),
    ]) {
      expect(read(readSetting, mute(until)).value, const Setting.unknown(0));
    }

    // Extension values are skipped as any field this version doesn't know.
    for (final extension in [
      [0xd4, 0, 0],
      [0xc7, 1, 5, 9],
    ]) {
      final hello = ArrayWriter()
        ..uint(0)
        ..array(
          ArrayWriter()
            ..uint(1)
            ..uint(1)
            ..raw(Uint8List.fromList(extension)),
        );
      expect(
        SessionMessage.decode(hello.encode()),
        const Hello(features: Features.accountSync),
      );
    }

    // A time no date can be.
    for (final time in [maxTime + 1, -0x8000000000000000]) {
      final event = SyncEvent(
        graph: GraphId.account(_alice),
        author: _alice,
        parents: const [],
        rank: 0,
        time: time,
        content: const Notice(text: ''),
      );
      expect(() => SyncEvent.decode(event.encode()), throwsFormatException);
    }
  });

  test('long messages are split and joined', () {
    final message = Uint8List.fromList(List.generate(3000, (i) => i % 256));
    final packets = frames(message);
    expect(packets, hasLength(3));

    final reassembler = Reassembler();
    expect(reassembler.push(packets[0]), isNull);
    expect(reassembler.push(packets[1]), isNull);
    expect(reassembler.push(packets[2]), message);

    final tooLong = frames(Uint8List(maxSyncMessage + 1));
    var failed = false;
    for (final packet in tooLong) {
      try {
        expect(reassembler.push(packet), isNull);
      } on FormatException {
        failed = true;
      }
    }
    expect(failed, isTrue);
    // Its own bytes, not a view of the packet's, which may be much more.
    final packet = Uint8List.fromList(_helloPacket);
    final hello = reassembler.push(packet)!;
    packet.fillRange(0, packet.length, 0);
    expect(hello, _helloPacket.sublist(2));

    // A message cut off by a reconnect doesn't spoil the next one.
    expect(reassembler.push(packets[0]), isNull);
    expect(reassembler.push(_helloPacket), hasLength(5));
    // Older versions mark only the final frame.
    expect(
      reassembler.push(Uint8List.fromList(_helloPacket)..[1] = 0x01),
      hasLength(5),
    );
  });

  test('reads pairing links', () {
    final link = PairingLink.parse(_vectorLink)!;
    expect(link.home, ToxAddress.of(_alice, ToxAddressNospam(0x01020304)));
    expect(link.requestMessage, 'pair:00112233445566778899aabbccddeeff');
    expect(PairingLink.parse(_vectorLink.replaceFirst('0206', '0207')), isNull);
    expect(PairingLink.parse('tox:${'0' * 76}'), isNull);
  });
}
