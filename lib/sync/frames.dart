import 'dart:math';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_constants.dart';

const syncPacketId = 0xb0;
const maxSyncMessage = 1 << 20;

const _flagFinal = 1;
const _flagFirst = 2;
const _header = 2;
const _maxPayload = toxMaxCustomPacketSize - _header;

List<Uint8List> frames(Uint8List message) => [
  for (int start = 0; start < message.length; start += _maxPayload)
    Uint8List.fromList([
      syncPacketId,
      (start == 0 ? _flagFirst : 0) |
          (start + _maxPayload >= message.length ? _flagFinal : 0),
      ...message.sublist(start, min(start + _maxPayload, message.length)),
    ]),
];

final class Reassembler {
  // Copied, so a message kept doesn't keep the Tox events it came with.
  final _buffer = BytesBuilder();
  bool _discarding = false;

  /// Returns the message once its final frame has arrived.
  Uint8List? push(Uint8List packet) {
    if (packet.length < _header || packet[0] != syncPacketId) {
      throw const FormatException('Not a sync packet');
    }
    final last = packet[1] & _flagFinal != 0;
    // Left from a connection that ended mid-message.
    if (packet[1] & _flagFirst != 0) {
      _buffer.clear();
      _discarding = false;
    }
    if (_discarding) {
      _discarding = !last;
      return null;
    }
    if (_buffer.length + packet.length - _header > maxSyncMessage) {
      _buffer.clear();
      _discarding = !last;
      throw const FormatException('Sync message too long');
    }
    _buffer.add(Uint8List.sublistView(packet, _header));
    return last ? _buffer.takeBytes() : null;
  }
}
