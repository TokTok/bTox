import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/messages/message_format.dart';

/// A message format only tests know: "text#key" reads as the text, keyed by
/// what follows the last "#".
final class FakeMessageFormat implements MessageFormat {
  const FakeMessageFormat();

  static Uint8List encode(String text, String key) => utf8.encode('$text#$key');

  @override
  String get id => 'fake';

  @override
  String title(AppLocalizations l10n) => 'Fake';

  @override
  String description(AppLocalizations l10n) => 'Reads text#key';

  @override
  ReadMessage? read(Uint8List bytes) {
    final message = utf8.decode(bytes, allowMalformed: true);
    final end = message.lastIndexOf('#');
    return end < 0
        ? null
        : ReadMessage(
            message.substring(0, end),
            key: MessageKey(id, message.substring(end + 1)),
          );
  }
}

const withFakeFormat = MessageFormats([FakeMessageFormat()]);
