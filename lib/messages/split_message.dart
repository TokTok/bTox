import 'dart:typed_data';

/// The most a message we send takes, in bytes: longer ones go as several,
/// as events take 64 KiB at most.
const maxSendBytes = 32 * 1024;

const _whitespace = {0x09, 0x0a, 0x0d, 0x20};

/// [message] in parts of at most [maxBytes], never inside a UTF-8 character,
/// and after whitespace where there is some in a part's second half.
List<Uint8List> splitMessage(Uint8List message, int maxBytes) {
  final parts = <Uint8List>[];
  var start = 0;
  while (message.length - start > maxBytes) {
    var end = start + maxBytes;
    // A UTF-8 character's later bytes are 10xxxxxx.
    while (end > start + 1 && message[end] & 0xc0 == 0x80) {
      end--;
    }
    for (var i = end - 1; i >= start + (end - start) ~/ 2; i--) {
      if (_whitespace.contains(message[i])) {
        end = i + 1;
        break;
      }
    }
    parts.add(Uint8List.sublistView(message, start, end));
    start = end;
  }
  parts.add(Uint8List.sublistView(message, start));
  return parts;
}
