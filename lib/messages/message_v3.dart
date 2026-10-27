import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/messages/message_format.dart';
import 'package:convert/convert.dart';

const _guardLength = 2;
const _timeLength = 4;
const _trailerLength = _guardLength + MessageV3.idLength + _timeLength;

/// TRIfA's "message V3": the text, two zero bytes, an ID TRIfA keeps when it
/// sends the message again, and the sender's time as big-endian Unix seconds.
final class MessageV3 implements MessageFormat {
  static const idLength = 32;

  const MessageV3();

  @override
  String get id => 'message_v3';

  @override
  String title(AppLocalizations l10n) => l10n.messageV3;

  @override
  String description(AppLocalizations l10n) => l10n.messageV3Hint;

  @override
  ReadMessage? read(Uint8List bytes) {
    final end = bytes.length - _trailerLength;
    if (end <= 0 || bytes[end] != 0 || bytes[end + 1] != 0) {
      return null;
    }
    final idStart = end + _guardLength;
    return ReadMessage(
      utf8.decode(bytes.sublist(0, end), allowMalformed: true),
      key: MessageKey(
        id,
        hex.encode(bytes.sublist(idStart, idStart + idLength)),
      ),
    );
  }
}
