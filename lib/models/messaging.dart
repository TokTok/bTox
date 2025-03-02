import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/packets/message_packet.dart';
import 'package:crypto/crypto.dart';

// [parent, merged, timestamp, author, content]
Uint8List encodeMessage(Message? parent, Message? merged, DateTime timestamp,
    PublicKey author, Content content) {
  return MessagePacket(
    parent: parent?.sha,
    merged: merged?.sha,
    timestamp: timestamp,
    author: author,
    content: content,
  ).encode();
}

MessagesCompanion newMessage({
  required Id<Contacts> contactId,
  required Message? parent,
  required Message? merged,
  required PublicKey author,
  required DateTime timestamp,
  required Content content,
}) {
  return MessagesCompanion.insert(
    contactId: contactId,
    parent: Value.absentIfNull(parent?.id),
    author: author,
    timestamp: timestamp,
    content: content,
    sha: Sha256.fromDigest(
      sha256.convert(encodeMessage(parent, merged, timestamp, author, content)),
    ),
  );
}
