import 'dart:typed_data';

import 'package:btox/packets/messagepack/message_data.dart';
import 'package:btox/packets/messagepack/packer.dart';
import 'package:btox/packets/messagepack/unpacker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Unpacker', () {
    test('unpackInt handles all ranges', () {
      void check(int? value) {
        final bytes = (Packer()..packInt(value)).takeBytes();
        final result = Unpacker(bytes).unpackInt();
        expect(result, value, reason: 'Value $value');
      }

      check(0);
      check(127);
      check(128);
      check(255);
      check(256);
      check(65535);
      check(65536);
      check(4294967295);
      check(4294967296);
      check(-1);
      check(-32);
      check(-33);
      check(-128);
      check(-129);
      check(-32768);
      check(-32769);
      check(-2147483648);
      check(-2147483649);
      check(null); // Test null
    });

    test('unpackString handles different lengths', () {
      void check(int length) {
        final s = 'a' * length;
        final bytes = (Packer()..packString(s)).takeBytes();
        final result = Unpacker(bytes).unpackString();
        expect(result, s, reason: 'Length $length');
      }

      check(31);
      check(32);
      check(255);
      check(256);
      check(65535);
      check(65536);
      expect(
        Unpacker((Packer()..packString(null)).takeBytes()).unpackString(),
        isNull,
      );
    });

    test('unpackBinary handles different lengths', () {
      void check(int length) {
        final b = Uint8List(length);
        final bytes = (Packer()..packBinary(b)).takeBytes();
        final result = Unpacker(bytes).unpackBinary();
        expect(result, b, reason: 'Length $length');
      }

      check(255);
      check(256);
      check(65535);
      check(65536);
      expect(
        Unpacker((Packer()..packBinary(null)).takeBytes()).unpackBinary(),
        isNull,
      );
    });

    test('unpackListLength handles different lengths', () {
      void check(int length) {
        final bytes = (Packer()..packListLength(length)).takeBytes();
        final result = Unpacker(bytes).unpackListLength();
        expect(result, length, reason: 'Length $length');
      }

      check(15);
      check(16);
      check(65535);
      check(65536);
      expect(
        Unpacker((Packer()..packListLength(null)).takeBytes())
            .unpackListLength(),
        0,
      );
    });

    test('unpackMapLength handles different lengths', () {
      void check(int length) {
        final bytes = (Packer()..packMapLength(length)).takeBytes();
        final result = Unpacker(bytes).unpackMapLength();
        expect(result, length, reason: 'Length $length');
      }

      check(15);
      check(16);
      check(65535);
      check(65536);
      expect(
        Unpacker((Packer()..packMapLength(null)).takeBytes()).unpackMapLength(),
        0,
      );
    });

    test('unpackBool', () {
      expect(
        Unpacker((Packer()..packBool(true)).takeBytes()).unpackBool(),
        isTrue,
      );
      expect(
        Unpacker((Packer()..packBool(false)).takeBytes()).unpackBool(),
        isFalse,
      );
      expect(
        Unpacker((Packer()..packBool(null)).takeBytes()).unpackBool(),
        isNull,
      );
    });

    test('unpackDouble', () {
      expect(
        Unpacker((Packer()..packDouble(3.14)).takeBytes()).unpackDouble(),
        3.14,
      );
      expect(
        Unpacker((Packer()..packDouble(null)).takeBytes()).unpackDouble(),
        isNull,
      );
    });

    test('unpackNull', () {
      Unpacker((Packer()..packNull()).takeBytes()).unpackNull();
    });

    test('FormatExceptions', () {
      final bytes = (Packer()..packString('not an int')).takeBytes();
      expect(() => Unpacker(bytes).unpackInt(), throwsFormatException);
      expect(() => Unpacker(bytes).unpackBool(), throwsFormatException);
      expect(() => Unpacker(bytes).unpackBinary(), throwsFormatException);
    });

    test('unpack MessageData types', () {
      final packer = Packer();
      packer.packInt(123);
      packer.packBool(true);
      packer.packDouble(1.23);
      packer.packString('test');
      packer.packBinary(Uint8List.fromList([1, 2, 3]));
      packer.packNull();

      final unpacker = Unpacker(packer.takeBytes());
      expect((unpacker.unpack() as MessageDataInt).value, 123);
      expect((unpacker.unpack() as MessageDataBool).value, true);
      expect(
        (unpacker.unpack() as MessageDataDouble).value,
        closeTo(1.23, 0.001),
      );
      expect((unpacker.unpack() as MessageDataString).value, 'test');
      expect(
        (unpacker.unpack() as MessageDataBinary).value,
        Uint8List.fromList([1, 2, 3]),
      );
      expect(unpacker.unpack(), isA<MessageDataNull>());
    });

    test('unpackList and unpackMap', () {
      final packer = Packer();
      packer.packListLength(2);
      packer.packInt(1);
      packer.packInt(2);

      packer.packMapLength(1);
      packer.packString('key');
      packer.packString('value');

      final unpacker = Unpacker(packer.takeBytes());
      final list = unpacker.unpackList();
      expect(list.length, 2);
      expect((list[0] as MessageDataInt).value, 1);
      expect((list[1] as MessageDataInt).value, 2);

      final map = unpacker.unpackMap();
      expect(map.length, 1);
      final entry = map.entries.first;
      expect((entry.key as MessageDataString).value, 'key');
      expect((entry.value as MessageDataString).value, 'value');
    });
  });
}
