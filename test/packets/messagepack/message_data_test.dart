import 'dart:convert';

import 'package:btox/packets/messagepack.dart';
import 'package:btox/packets/messagepack/message_data.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MessageDataList is equality comparable', () {
    final l1 = MessageDataList([
      MessageDataBool(true),
    ]);
    final l2 = MessageDataList([
      MessageDataBool(true),
    ]);
    final l3 = MessageDataList([
      MessageDataBool(false),
    ]);

    expect(l1, l2);
    expect(l1, isNot(l3));
  }, tags: ['models']);

  test('MessageDataMap is equality comparable', () {
    final m1 = MessageDataMap({
      MessageDataBool(true): MessageDataBool(true),
      MessageDataBinary(Uint8List.fromList([1, 2, 3, 4])):
          MessageDataBinary(Uint8List.fromList([1, 2, 3, 4])),
    });
    final m2 = MessageDataMap({
      MessageDataBool(true): MessageDataBool(true),
      MessageDataBinary(Uint8List.fromList([1, 2, 3, 4])):
          MessageDataBinary(Uint8List.fromList([1, 2, 3, 4])),
    });
    final m3 = MessageDataMap({
      MessageDataBool(false): MessageDataBool(true),
    });

    expect(m1, m2);
    expect(m1, isNot(m3));
  }, tags: ['models']);

  test('MessageData encode and decode', () {
    final l1 = MessageDataList([
      MessageDataBool(true),
      MessageDataDouble(3.14),
      MessageDataInt(42),
      MessageDataBinary(Uint8List.fromList([1, 2, 3, 4])),
      MessageDataString('hello'),
      MessageDataNull(),
      MessageDataList([
        MessageDataBool(true),
        MessageDataDouble(3.14),
        MessageDataInt(42),
        MessageDataBinary(Uint8List.fromList([1, 2, 3, 4])),
        MessageDataString('hello'),
        MessageDataNull(),
      ]),
      MessageDataMap({
        MessageDataBool(true): MessageDataBool(true),
        MessageDataDouble(3.14): MessageDataDouble(3.14),
        MessageDataInt(42): MessageDataInt(42),
        // MessageDataBinary(Uint8List.fromList([1, 2, 3, 4])):
        //     MessageDataBinary(Uint8List.fromList([1, 2, 3, 4])),
        MessageDataString('hello'): MessageDataString('hello'),
        MessageDataNull(): MessageDataNull(),
      }),
    ]);
    final l2 =
        Unpacker((Packer()..packMessageData(l1)).takeBytes()).unpackList();
    final l3 = MessageData.fromJson(jsonDecode(jsonEncode(l1)));

    expect(l1.value, l2);
    expect(l1, l3);
  }, tags: ['models']);
}
