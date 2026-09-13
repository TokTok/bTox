import 'dart:typed_data';

import 'package:btox/packets/messagepack/packer.dart';
import 'package:btox/packets/messagepack/tags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Packer', () {
    test('packInt handles all ranges', () {
      void check(int value, List<int> expected) {
        final p = Packer()..packInt(value);
        expect(
          p.takeBytes(),
          Uint8List.fromList(expected),
          reason: 'Value $value',
        );
      }

      // Positive fixint
      check(0, [0x00]);
      check(127, [0x7f]);

      // uint8
      check(128, [kTagUint8, 0x80]);
      check(255, [kTagUint8, 0xff]);

      // uint16
      check(256, [kTagUint16, 0x01, 0x00]);
      check(65535, [kTagUint16, 0xff, 0xff]);

      // uint32
      check(65536, [kTagUint32, 0x00, 0x01, 0x00, 0x00]);
      check(4294967295, [kTagUint32, 0xff, 0xff, 0xff, 0xff]);

      // uint64
      check(4294967296, [
        kTagUint64,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);

      // Negative fixint
      check(-1, [0xff]);
      check(-32, [0xe0]);

      // int8
      check(-33, [kTagInt8, 0xdf]);
      check(-128, [kTagInt8, 0x80]);

      // int16
      check(-129, [kTagInt16, 0xff, 0x7f]);
      check(-32768, [kTagInt16, 0x80, 0x00]);

      // int32
      check(-32769, [kTagInt32, 0xff, 0xff, 0x7f, 0xff]);
      check(-2147483648, [kTagInt32, 0x80, 0x00, 0x00, 0x00]);

      // int64
      check(-2147483649, [
        kTagInt64,
        0xff,
        0xff,
        0xff,
        0xff,
        0x7f,
        0xff,
        0xff,
        0xff,
      ]);
    });

    test('packString handles different lengths', () {
      void check(int length, int tag, [int? lengthBytes]) {
        final s = 'a' * length;
        final p = Packer()..packString(s);
        final bytes = p.takeBytes();
        expect(bytes[0], tag);
        expect(bytes.length, 1 + (lengthBytes ?? 0) + length);
      }

      check(31, 0xA0 | 31);
      check(32, kTagStr8, 1);
      check(255, kTagStr8, 1);
      check(256, kTagStr16, 2);
      check(65535, kTagStr16, 2);
      check(65536, kTagStr32, 4);
    });

    test('packBinary handles different lengths', () {
      void check(int length, int tag, int lengthBytes) {
        final b = Uint8List(length);
        final p = Packer()..packBinary(b);
        final bytes = p.takeBytes();
        expect(bytes[0], tag);
        expect(bytes.length, 1 + lengthBytes + length);
      }

      check(255, kTagBin8, 1);
      check(256, kTagBin16, 2);
      check(65535, kTagBin16, 2);
      check(65536, kTagBin32, 4);
    });

    test('packListLength handles different lengths', () {
      void check(int length, int tag, [int? lengthBytes]) {
        final p = Packer()..packListLength(length);
        final bytes = p.takeBytes();
        expect(bytes[0], tag);
        if (lengthBytes != null) {
          expect(bytes.length, 1 + lengthBytes);
        }
      }

      check(15, 0x90 | 15);
      check(16, kTagArray16, 2);
      check(65535, kTagArray16, 2);
      check(65536, kTagArray32, 4);
    });

    test('packMapLength handles different lengths', () {
      void check(int length, int tag, [int? lengthBytes]) {
        final p = Packer()..packMapLength(length);
        final bytes = p.takeBytes();
        expect(bytes[0], tag);
        if (lengthBytes != null) {
          expect(bytes.length, 1 + lengthBytes);
        }
      }

      check(15, 0x80 | 15);
      check(16, kTagMap16, 2);
      check(65535, kTagMap16, 2);
      check(65536, kTagMap32, 4);
    });

    test('Packer buffer resizing', () {
      final p = Packer(4);
      p.packBinary(Uint8List(10));
      expect(p.takeBytes().length, 12);
    });

    test('packBool', () {
      expect(
        (Packer()..packBool(true)).takeBytes(),
        Uint8List.fromList([kTagTrue]),
      );
      expect(
        (Packer()..packBool(false)).takeBytes(),
        Uint8List.fromList([kTagFalse]),
      );
      expect(
        (Packer()..packBool(null)).takeBytes(),
        Uint8List.fromList([kTagNil]),
      );
    });

    test('packDouble', () {
      expect(
        (Packer()..packDouble(null)).takeBytes(),
        Uint8List.fromList([kTagNil]),
      );
      // 3.14 in float64 is 40 09 1e b8 51 eb 85 1f
      expect(
        (Packer()..packDouble(3.14)).takeBytes(),
        Uint8List.fromList([
          kTagFloat64,
          0x40,
          0x09,
          0x1e,
          0xb8,
          0x51,
          0xeb,
          0x85,
          0x1f,
        ]),
      );
    });

    test('packNull', () {
      expect((Packer()..packNull()).takeBytes(), Uint8List.fromList([kTagNil]));
    });

    test('packStringEmptyIsNull', () {
      expect(
        (Packer()..packStringEmptyIsNull('')).takeBytes(),
        Uint8List.fromList([kTagNil]),
      );
      expect(
        (Packer()..packStringEmptyIsNull(null)).takeBytes(),
        Uint8List.fromList([kTagNil]),
      );
      expect(
        (Packer()..packStringEmptyIsNull('a')).takeBytes(),
        Uint8List.fromList([0xA1, 0x61]),
      );
    });
  });
}
