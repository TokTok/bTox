import 'dart:typed_data';

import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/packets/messagepack.dart';
import 'package:btox/packets/message_packet.dart';
import 'package:glados/glados.dart';

extension MessagePacketAny on Any {
  Generator<Uint8List> uint8ListWithLength(int length) =>
      listWithLength(length, uint8).map(Uint8List.fromList);

  Generator<PublicKey> get publicKey =>
      uint8ListWithLength(32).map(PublicKey.new);

  Generator<Sha256> get sha256 => uint8ListWithLength(32).map(Sha256.new);

  Generator<TextContent> get textContent =>
      letters.map((t) => TextContent(text: t));

  Generator<DeleteContent> get deleteContent =>
      sha256.map((s) => DeleteContent(message: s));

  Generator<EditContent> get editContent =>
      combine2(sha256, letters, (s, t) => EditContent(message: s, text: t));

  Generator<FileContent> get fileContent =>
      letters.map((u) => FileContent(name: u, size: u.length, path: u));

  Generator<MediaContent> get mediaContent =>
      letters.map((u) => MediaContent(url: u));

  Generator<LocationContent> get locationContent => combine2(
    this.double,
    this.double,
    (lat, lon) => LocationContent(latitude: lat, longitude: lon),
  );

  Generator<ReactionContent> get reactionContent => combine2(
    sha256,
    letters,
    (s, e) => ReactionContent(message: s, emoji: e),
  );

  Generator<Content> get content => oneOf([
    textContent,
    deleteContent,
    editContent,
    fileContent,
    mediaContent,
    locationContent,
    reactionContent,
  ]);

  Generator<MessagePacket> get messagePacket => combine5(
    sha256.nullable,
    sha256.nullable,
    dateTime,
    publicKey,
    content,
    (p, m, t, a, c) => MessagePacket(
      parent: p,
      merged: m,
      timestamp: t,
      author: a,
      content: c,
    ),
  );
}

void main() {
  Glados(any.messagePacket).test('MessagePacket round-trip property', (packet) {
    final encoded = packet.encode();
    final decoded = MessagePacket.unpack(Unpacker(encoded));

    expect(decoded.parent, packet.parent);
    expect(decoded.merged, packet.merged);
    // Precision might be lost in DateTime depending on how it's packed (ms vs us).
    // MessagePacket uses millisecondsSinceEpoch.
    expect(
      decoded.timestamp.millisecondsSinceEpoch,
      packet.timestamp.millisecondsSinceEpoch,
    );
    expect(decoded.author, packet.author);
    expect(decoded.content, packet.content);
  });

  Glados(any.content).test('Content round-trip property', (content) {
    final encoded = content.encode();
    final decoded = Content.unpack(Unpacker(encoded));
    expect(decoded, content);
  });
}
