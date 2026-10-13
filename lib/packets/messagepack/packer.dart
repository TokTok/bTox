// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2020 Nail Gilaziev
// Copyright 2025 The TokTok Team
import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/packets/messagepack/message_data.dart';
import 'package:btox/packets/messagepack/tags.dart';
import 'package:btox/packets/packet.dart';

// dart2js doesn't support 64 bit ints, so we pack using 2x 32 bit ints.
void _setUint64(ByteData d, int offset, int v) {
  d.setUint32(offset, v >> 32);
  d.setUint32(offset + 4, v & 0xFFFFFFFF);
}

void _setInt64(ByteData d, int offset, int v) {
  d.setInt32(offset, v >> 32);
  d.setUint32(offset + 4, v & 0xFFFFFFFF);
}

/// Streaming API for packing (serializing) data to msgpack binary format.
///
/// Packer provide API for manually packing your data item by item in serial / streaming manner.
/// Use methods packXXX, where XXX is type names. Methods can take value and `null`.
/// If `null` provided for packXXX method it will be packed to `null` implicitly.
/// For explicitly packing `null` separate packNull function exist.
final class Packer {
  final _bytes = BytesBuilder();
  final _scratch = ByteData(8);

  /// Writes [tag], then the [size] bytes that [set] writes.
  void _put(int tag, int size, void Function(ByteData d) set) {
    _bytes.addByte(tag);
    set(_scratch);
    _bytes.add(Uint8List.sublistView(_scratch, 0, size));
  }

  /// Writes a length header: [fix] with the length in its low bits if it
  /// fits in [fixMask], otherwise the smallest of [tag8], [tag16], [tag32].
  void _length(
    String type,
    int length, {
    int? fix,
    int fixMask = 0,
    int? tag8,
    required int tag16,
    required int tag32,
  }) {
    if (fix != null && length <= fixMask) {
      _bytes.addByte(fix | length);
    } else if (tag8 != null && length <= 0xFF) {
      _put(tag8, 1, (d) => d.setUint8(0, length));
    } else if (length <= 0xFFFF) {
      _put(tag16, 2, (d) => d.setUint16(0, length));
    } else if (length <= 0xFFFFFFFF) {
      _put(tag32, 4, (d) => d.setUint32(0, length));
    } else {
      throw ArgumentError('Max $type length is 0xFFFFFFFF');
    }
  }

  /// Explicitly pack null value.
  /// Other packXXX implicitly handle null values.
  void packNull() => _bytes.addByte(kTagNil);

  /// Pack [bool] or `null`.
  // ignore: avoid_positional_boolean_parameters
  void packBool(bool? v) =>
      _bytes.addByte(v == null ? kTagNil : (v ? kTagTrue : kTagFalse));

  /// Pack [int] or `null`.
  void packInt(int? v) {
    if (v == null) {
      packNull();
    } else if (v >= -32 && v <= 127) {
      _bytes.addByte(v & 0xFF);
    } else if (v >= 0) {
      if (v <= 0xFF) {
        _put(kTagUint8, 1, (d) => d.setUint8(0, v));
      } else if (v <= 0xFFFF) {
        _put(kTagUint16, 2, (d) => d.setUint16(0, v));
      } else if (v <= 0xFFFFFFFF) {
        _put(kTagUint32, 4, (d) => d.setUint32(0, v));
      } else {
        _put(kTagUint64, 8, (d) => _setUint64(d, 0, v));
      }
    } else if (v >= -128) {
      _put(kTagInt8, 1, (d) => d.setInt8(0, v));
    } else if (v >= -32768) {
      _put(kTagInt16, 2, (d) => d.setInt16(0, v));
    } else if (v >= -2147483648) {
      _put(kTagInt32, 4, (d) => d.setInt32(0, v));
    } else {
      _put(kTagInt64, 8, (d) => _setInt64(d, 0, v));
    }
  }

  /// Pack [double] or `null`.
  void packDouble(double? v) =>
      v == null ? packNull() : _put(kTagFloat64, 8, (d) => d.setFloat64(0, v));

  /// Pack [String] or `null`.
  ///
  /// Throws [ArgumentError] if [String.length] exceed (2^32)-1.
  void packString(String? v) {
    if (v == null) {
      return packNull();
    }
    final encoded = utf8.encode(v);
    _length(
      'String',
      encoded.length,
      fix: 0xA0,
      fixMask: 0x1F,
      tag8: kTagStr8,
      tag16: kTagStr16,
      tag32: kTagStr32,
    );
    _bytes.add(encoded);
  }

  /// Convenient function that call [packString(v)] by passing empty [String] as `null`.
  ///
  /// Convenient when you not distinguish between empty [String] and null on msgpack wire.
  void packStringEmptyIsNull(String? v) =>
      packString(v == null || v.isEmpty ? null : v);

  /// Pack `List<int>` or null.
  void packBinary(List<int>? buffer) {
    if (buffer == null) {
      return packNull();
    }
    _length(
      'binary',
      buffer.length,
      tag8: kTagBin8,
      tag16: kTagBin16,
      tag32: kTagBin32,
    );
    _bytes.add(buffer);
  }

  /// Pack [List.length] or `null`.
  void packListLength(int? length) => length == null
      ? packNull()
      : _length(
          'list',
          length,
          fix: 0x90,
          fixMask: 0xF,
          tag16: kTagArray16,
          tag32: kTagArray32,
        );

  /// Pack [Map.length] or `null`.
  void packMapLength(int? length) => length == null
      ? packNull()
      : _length(
          'map',
          length,
          fix: 0x80,
          fixMask: 0xF,
          tag16: kTagMap16,
          tag32: kTagMap32,
        );

  void packMessageData(MessageData data) {
    data.pack(this);
  }

  void pack(Packet packet) {
    packet.pack(this);
  }

  /// Get bytes representation of this packer.
  /// Note: after this call do not reuse packer - create new.
  Uint8List takeBytes() => _bytes.takeBytes();
}
