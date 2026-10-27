import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart';
import 'package:btox/packets/messagepack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an event that can\'t be read is left out of its batch', () {
    final packer = Packer()..packListLength(3);
    // A conference type newer than these bindings.
    packer
      ..packListLength(2)
      ..packInt(Tox_Event_Type.TOX_EVENT_CONFERENCE_INVITE.value)
      ..packListLength(3)
      ..packInt(0)
      ..packInt(7)
      ..packBinary([1, 2, 3]);
    // A kind newer than them.
    packer
      ..packListLength(2)
      ..packInt(200)
      ..packInt(0);
    packer
      ..packListLength(2)
      ..packInt(Tox_Event_Type.TOX_EVENT_FRIEND_TYPING.value)
      ..packListLength(2)
      ..packInt(0)
      ..packBool(true);

    expect(unpackEvents(Unpacker(packer.takeBytes())), [
      const Event.friendTyping(friendNumber: 0, typing: true),
    ]);
  });
}
