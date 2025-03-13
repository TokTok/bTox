// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2020 Nail Gilaziev
// Copyright 2025 The TokTok Team
import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/packets/messagepack/message_data.dart';
import 'package:btox/packets/messagepack/tags.dart';

// dart2js doesn't support 64 bit ints, so we unpack using 2x 32 bit ints.
int _getUint64(ByteData d, int offset) =>
    (d.getUint32(offset) << 32) | d.getUint32(offset + 4);

int _getInt64(ByteData d, int offset) =>
    (d.getInt32(offset) << 32) | d.getUint32(offset + 4);

/// Streaming API for unpacking (deserializing) data from msgpack binary format.
///
/// unpackXXX methods returns value if it exist, or `null`.
/// Throws [FormatException] if value is not an requested type,
/// but in that case throwing exception not corrupt internal state,
/// so other unpackXXX methods can be called after that.
final class Unpacker {
  /// Manipulates with provided [Uint8List] to sequentially unpack values.
  /// Use [Unpacker.fromList()] to unpack raw `List<int>` bytes.
  Unpacker(this._list) : _d = ByteData.view(_list.buffer, _list.offsetInBytes);

  ///Convenient
  Unpacker.fromList(List<int> l) : this(Uint8List.fromList(l));

  final Uint8List _list;
  final ByteData _d;
  int _offset = 0;

  bool get hasNull => _d.getUint8(_offset) == kTagNil;

  void unpackNull() {
    if (!hasNull) {
      throw _formatException('null', _d.getUint8(_offset));
    }
    _offset += 1;
  }

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not a bool,
  bool? unpackBool() {
    final b = _d.getUint8(_offset);
    bool? v;
    if (b == kTagFalse) {
      v = false;
      _offset += 1;
    } else if (b == kTagTrue) {
      v = true;
      _offset += 1;
    } else if (b == kTagNil) {
      v = null;
      _offset += 1;
    } else {
      throw _formatException('bool', b);
    }
    return v;
  }

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not an integer,
  int? unpackInt() {
    final b = _d.getUint8(_offset);
    int? v;
    if (b <= 0x7f || b >= 0xe0) {
      /// Int value in fixnum range [-32..127] encoded in header 1 byte
      v = _d.getInt8(_offset);
      _offset += 1;
    } else if (b == kTagUint8) {
      v = _d.getUint8(++_offset);
      _offset += 1;
    } else if (b == kTagUint16) {
      v = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == kTagUint32) {
      v = _d.getUint32(++_offset);
      _offset += 4;
    } else if (b == kTagUint64) {
      v = _getUint64(_d, ++_offset);
      _offset += 8;
    } else if (b == kTagInt8) {
      v = _d.getInt8(++_offset);
      _offset += 1;
    } else if (b == kTagInt16) {
      v = _d.getInt16(++_offset);
      _offset += 2;
    } else if (b == kTagInt32) {
      v = _d.getInt32(++_offset);
      _offset += 4;
    } else if (b == kTagInt64) {
      v = _getInt64(_d, ++_offset);
      _offset += 8;
    } else if (b == kTagNil) {
      v = null;
      _offset += 1;
    } else {
      throw _formatException('integer', b);
    }
    return v;
  }

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not a Double.
  double? unpackDouble() {
    final b = _d.getUint8(_offset);
    double? v;
    if (b == kTagFloat32) {
      v = _d.getFloat32(++_offset);
      _offset += 4;
    } else if (b == kTagFloat64) {
      v = _d.getFloat64(++_offset);
      _offset += 8;
    } else if (b == kTagNil) {
      v = null;
      _offset += 1;
    } else {
      throw _formatException('double', b);
    }
    return v;
  }

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Empty
  /// Throws [FormatException] if value is not a String.
  String? unpackString() {
    final b = _d.getUint8(_offset);
    if (b == kTagNil) {
      _offset += 1;
      return null;
    }
    int len;

    /// fixstr 101XXXXX stores a byte array whose len is up to 31 bytes:
    if (b & 0xE0 == 0xA0) {
      len = b & 0x1F;
      _offset += 1;
    } else if (b == kTagNil) {
      _offset += 1;
      return null;
    } else if (b == kTagStr8) {
      len = _d.getUint8(++_offset);
      _offset += 1;
    } else if (b == kTagStr16) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == kTagStr32) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('String', b);
    }
    final data =
        Uint8List.view(_list.buffer, _list.offsetInBytes + _offset, len);
    _offset += len;
    return utf8.decode(data);
  }

  /// Unpack [List.length] if packed value is an [List] or `null`.
  ///
  /// Encoded in msgpack packet null or 0 length unpacks to 0 for convenience.
  /// Items of the [List] must be unpacked manually with respect to returned `length`
  /// Throws [FormatException] if value is not an [List].
  int unpackListLength() {
    final b = _d.getUint8(_offset);
    int len;
    if (b & 0xF0 == 0x90) {
      /// fixarray 1001XXXX stores an array whose length is up to 15 elements:
      len = b & 0xF;
      _offset += 1;
    } else if (b == kTagNil) {
      len = 0;
      _offset += 1;
    } else if (b == kTagArray16) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == kTagArray32) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('List length', b);
    }
    return len;
  }

  /// Unpack [Map.length] if packed value is an [Map] or `null`.
  ///
  /// Encoded in msgpack packet null or 0 length unpacks to 0 for convenience.
  /// Items of the [Map] must be unpacked manually with respect to returned `length`
  /// Throws [FormatException] if value is not an [Map].
  int unpackMapLength() {
    final b = _d.getUint8(_offset);
    int len;
    if (b & 0xF0 == 0x80) {
      /// fixmap 1000XXXX stores a map whose length is up to 15 elements
      len = b & 0xF;
      _offset += 1;
    } else if (b == kTagNil) {
      len = 0;
      _offset += 1;
    } else if (b == kTagMap16) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == kTagMap32) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('Map length', b);
    }
    return len;
  }

  /// Unpack value if packed value is binary or `null`.
  ///
  /// Encoded in msgpack packet null unpacks to [List] with 0 length for convenience.
  /// Throws [FormatException] if value is not a binary.
  Uint8List? unpackBinary() {
    final b = _d.getUint8(_offset);
    int len;
    if (b == kTagNil) {
      _offset += 1;
      return null;
    } else if (b == kTagBin8) {
      len = _d.getUint8(++_offset);
      _offset += 1;
    } else if (b == kTagBin16) {
      len = _d.getUint16(++_offset);
      _offset += 2;
    } else if (b == kTagBin32) {
      len = _d.getUint32(++_offset);
      _offset += 4;
    } else {
      throw _formatException('Binary', b);
    }
    final data =
        Uint8List.view(_list.buffer, _list.offsetInBytes + _offset, len);
    _offset += len;
    return data.asUnmodifiableView();
  }

  MessageData unpack() {
    final b = _d.getUint8(_offset);
    if (b == kTagNil) {
      unpackNull();
      return const MessageDataNull();
    } else if (b <= 0x7f ||
        b >= 0xe0 ||
        b == kTagUint8 ||
        b == kTagUint16 ||
        b == kTagUint32 ||
        b == kTagUint64 ||
        b == kTagInt8 ||
        b == kTagInt16 ||
        b == kTagInt32 ||
        b == kTagInt64) {
      return MessageDataInt(unpackInt()!);
    } else if (b == kTagFalse || b == kTagTrue) {
      return MessageDataBool(unpackBool()!);
    } else if (b == kTagFloat32 || b == kTagFloat64) {
      return MessageDataDouble(unpackDouble()!);
    } else if ((b & 0xE0) == 0xA0 ||
        b == kTagNil ||
        b == kTagStr8 ||
        b == kTagStr16 ||
        b == kTagStr32) {
      return MessageDataString(unpackString()!);
    } else if (b == kTagBin8 || b == kTagBin16 || b == kTagBin32) {
      return MessageDataBinary(unpackBinary()!);
    } else if ((b & 0xF0) == 0x90 || b == kTagArray16 || b == kTagArray32) {
      return MessageDataList(unpackList());
    } else if ((b & 0xF0) == 0x80 || b == kTagMap16 || b == kTagMap32) {
      return MessageDataMap(unpackMap());
    } else {
      throw _formatException('Unknown', b);
    }
  }

  /// Automatically unpacks `bytes` to [List] where items has corresponding data types.
  ///
  /// Return types declared as [MessageData] instead of `dynamic` for safety reasons.
  /// This limits the number of valid types that can be cast to, and since [MessageData]
  /// is a sealed type, a switch over it can be checked for completeness at compile time.
  List<MessageData> unpackList() {
    final length = unpackListLength();
    return List.generate(length, (_) => unpack());
  }

  /// Automatically unpacks `bytes` to [Map] where key and values has corresponding data types.
  ///
  /// Return types declared as [MessageData] instead of `dynamic` for safety reasons.
  /// This limits the number of valid types that can be cast to, and since [MessageData]
  /// is a sealed type, a switch over it can be checked for completeness at compile time.
  Map<MessageData, MessageData> unpackMap() {
    final length = unpackMapLength();
    return {for (var i = 0; i < length; i++) unpack(): unpack()};
  }

  Exception _formatException(String type, int b) => FormatException(
      'Try to unpack $type value, but it\'s not an $type, byte = $b');
}
