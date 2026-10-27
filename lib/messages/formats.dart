import 'package:btox/messages/message_format.dart';
import 'package:btox/messages/message_v3.dart';

/// Every message format bTox can read.
const messageFormats = <MessageFormat>[MessageV3()];

MessageFormats formatsOn(List<MessageFormat> known, Iterable<String> off) =>
    MessageFormats([
      for (final format in known)
        if (!off.contains(format.id)) format,
    ]);
