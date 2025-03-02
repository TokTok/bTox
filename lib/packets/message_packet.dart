import 'dart:typed_data';

import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/packets/messagepack.dart';
import 'package:btox/packets/packet.dart';
import 'package:crypto/crypto.dart';

final class MessagePacket extends Packet {
  final Sha256? parent;
  final Sha256? merged;
  final DateTime timestamp;
  final PublicKey author;
  final Content content;

  const MessagePacket({
    required this.parent,
    required this.merged,
    required this.timestamp,
    required this.author,
    required this.content,
  });

  factory MessagePacket.unpack(Unpacker unpacker) {
    final int length = unpacker.unpackListLength();
    if (length != 5) {
      throw Exception('Invalid message packet');
    }

    final Sha256? parent =
        unpacker.unpackBinary()?.let((sha) => Sha256.fromDigest(Digest(sha)));
    final Sha256? merged =
        unpacker.unpackBinary()?.let((sha) => Sha256.fromDigest(Digest(sha)));
    final DateTime timestamp =
        DateTime.fromMillisecondsSinceEpoch(unpacker.unpackInt()!);
    final PublicKey author = PublicKey.unpack(unpacker);
    final Content content = Content.unpack(unpacker);

    return MessagePacket(
      parent: parent,
      merged: merged,
      timestamp: timestamp,
      author: author,
      content: content,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(5)
      ..packBinary(parent?.bytes)
      ..packBinary(merged?.bytes)
      ..packInt(timestamp.millisecondsSinceEpoch)
      ..packBinary(author.bytes)
      ..pack(content);
  }
}

extension on Uint8List {
  T let<T>(T Function(Uint8List) f) {
    return f(this);
  }
}
