import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/messages/message_format.dart';
import 'package:btox/messages/message_v3.dart';
import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const format = MessageV3();

  test('reads what TRIfA writes, keyed by its ID', () {
    final id = Uint8List(MessageV3.idLength)..[0] = 1;
    final message = format.read(
      Uint8List.fromList([
        ...utf8.encode('Grüße ✓'),
        0, 0, // The guard.
        ...id,
        0x63, 0xb0, 0xcd, 0x00, // 2023-01-01, in Unix seconds.
      ]),
    )!;
    expect(message.text, 'Grüße ✓');
    expect(message.key, MessageKey(format.id, hex.encode(id)));
  });

  test('leaves other messages alone', () {
    expect(
      format.read(utf8.encode('just text, long enough to have room')),
      isNull,
    );
  });
}
