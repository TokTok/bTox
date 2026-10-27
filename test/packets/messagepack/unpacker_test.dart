import 'dart:typed_data';

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

    test('skip passes any value, however deep, without building it', () {
      final packer = Packer()
        ..packMapLength(2)
        ..packString('a')
        ..packListLength(2)
        ..packBinary(Uint8List(3))
        ..packDouble(1.5)
        ..packInt(-7)
        ..packBool(true)
        ..packInt(42);
      final unpacker = Unpacker(packer.takeBytes())..skip();
      expect(unpacker.unpackInt(), 42);

      final deep = Uint8List.fromList([...List.filled(200000, 0x91), 0xc0]);
      expect((Unpacker(deep)..skip()).isDone, isTrue);
    });

    test('bytes that end too soon are a FormatException', () {
      for (final bytes in [
        [0xdb, 0, 0, 0, 5, 0x61],
        [0xcd, 0x01],
        <int>[],
        [0xdd, 0xff, 0xff, 0xff, 0xff],
      ]) {
        expect(
          () => Unpacker(Uint8List.fromList(bytes)).skip(),
          throwsFormatException,
          reason: '$bytes',
        );
      }
    });

    test('a uint64 too large for an int reads as the largest', () {
      final bytes = Uint8List.fromList([0xcf, ...List.filled(8, 0xff)]);
      expect(Unpacker(bytes).unpackInt(), 0x7fffffffffffffff);
    });
  });
}
