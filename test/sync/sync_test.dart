// What only bTox does; rs-toxcore-c's sync/conformance holds what every
// implementation does.

import 'dart:typed_data';

import 'package:btox/models/crypto.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/frames.dart';
import 'package:btox/sync/pairing.dart';
import 'package:btox/sync/setting.dart';
import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';

final _helloPacket = Uint8List.fromList([
  0xb0,
  0x03,
  0x92,
  0x00,
  0x92,
  0x01,
  0x01,
]);
const _link =
    'tox:0101010101010101010101010101010101010101010101010101010101010101010203'
    '040206?pair=00112233445566778899aabbccddeeff';

final _alice = PublicKey(Uint8List(32)..fillRange(0, 32, 1));
final _bob = PublicKey(Uint8List(32)..fillRange(0, 32, 2));

void main() {
  test('reads a file of unknown size as the most it can be', () {
    // A home device's file of unknown size, as toxcore gives it.
    final file = SyncEvent(
      graph: GraphId.account(_alice),
      author: _alice,
      parents: const [],
      rank: 0,
      time: 0,
      content: const FileStarted(
        sender: 'Me',
        name: 'cat.png',
        size: 3,
        incoming: false,
      ),
    );
    final unknownSize = hex
        .encode(file.encode())
        .replaceFirst('a76361742e706e6703', 'a76361742e706e67cf${'ff' * 8}');
    expect(
      SyncEvent.decode(Uint8List.fromList(hex.decode(unknownSize))).content,
      isA<FileStarted>().having((f) => f.size, 'size', 0x7fffffffffffffff),
    );
  });

  test('concurrent settings end the same when folded one at a time', () {
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

  test('refuses a message too long, and reads the next as its own bytes', () {
    final reassembler = Reassembler();
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
  });

  test('refuses pairing links with a bad checksum, and plain addresses', () {
    expect(PairingLink.parse(_link.replaceFirst('0206', '0207')), isNull);
    expect(PairingLink.parse('tox:${'0' * 76}'), isNull);
  });
}
