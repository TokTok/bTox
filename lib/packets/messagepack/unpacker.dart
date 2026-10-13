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
  Unpacker(this._list) : _d = ByteData.sublistView(_list);

  final Uint8List _list;
  final ByteData _d;
  int _offset = 0;

  int get _tag => _d.getUint8(_offset);

  /// Reads the [size] bytes after the tag with [get] and moves past both.
  T _read<T>(int size, T Function(int offset) get) {
    final v = get(_offset + 1);
    _offset += 1 + size;
    return v;
  }

  /// Reads a length header, `null` for nil. See [Packer] for the layout.
  int? _length(
    String type, {
    int? fix,
    int fixMask = 0,
    int? tag8,
    required int tag16,
    required int tag32,
  }) => switch (_tag) {
    kTagNil => _read(0, (_) => null),
    final b when fix != null && b & ~fixMask == fix => _read(
      0,
      (_) => b & fixMask,
    ),
    final b when b == tag8 => _read(1, _d.getUint8),
    final b when b == tag16 => _read(2, _d.getUint16),
    final b when b == tag32 => _read(4, _d.getUint32),
    final b => throw _formatException(type, b),
  };

  Uint8List _take(int length) {
    final data = Uint8List.sublistView(_list, _offset, _offset + length);
    _offset += length;
    return data;
  }

  bool get hasNull => _tag == kTagNil;

  void unpackNull() {
    if (!hasNull) {
      throw _formatException('null', _tag);
    }
    _offset += 1;
  }

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not a bool,
  bool? unpackBool() => switch (_tag) {
    kTagFalse => _read(0, (_) => false),
    kTagTrue => _read(0, (_) => true),
    kTagNil => _read(0, (_) => null),
    final b => throw _formatException('bool', b),
  };

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not an integer,
  int? unpackInt() => switch (_tag) {
    /// Int value in fixnum range [-32..127] encoded in header 1 byte
    final b when b <= 0x7f || b >= 0xe0 => _read(0, (_) => b.toSigned(8)),
    kTagUint8 => _read(1, _d.getUint8),
    kTagUint16 => _read(2, _d.getUint16),
    kTagUint32 => _read(4, _d.getUint32),
    kTagUint64 => _read(8, (o) => _getUint64(_d, o)),
    kTagInt8 => _read(1, _d.getInt8),
    kTagInt16 => _read(2, _d.getInt16),
    kTagInt32 => _read(4, _d.getInt32),
    kTagInt64 => _read(8, (o) => _getInt64(_d, o)),
    kTagNil => _read(0, (_) => null),
    final b => throw _formatException('integer', b),
  };

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not a Double.
  double? unpackDouble() => switch (_tag) {
    kTagFloat32 => _read(4, _d.getFloat32),
    kTagFloat64 => _read(8, _d.getFloat64),
    kTagNil => _read(0, (_) => null),
    final b => throw _formatException('double', b),
  };

  /// Unpack value if it exist. Otherwise returns `null`.
  ///
  /// Throws [FormatException] if value is not a String.
  String? unpackString() => switch (_length(
    'String',
    fix: 0xA0,
    fixMask: 0x1F,
    tag8: kTagStr8,
    tag16: kTagStr16,
    tag32: kTagStr32,
  )) {
    final length? => utf8.decode(_take(length)),
    null => null,
  };

  /// Unpack [List.length] if packed value is an [List] or `null`.
  ///
  /// Encoded in msgpack packet null or 0 length unpacks to 0 for convenience.
  /// Items of the [List] must be unpacked manually with respect to returned `length`
  /// Throws [FormatException] if value is not an [List].
  int unpackListLength() =>
      _length(
        'List length',
        fix: 0x90,
        fixMask: 0xF,
        tag16: kTagArray16,
        tag32: kTagArray32,
      ) ??
      0;

  /// Unpack [Map.length] if packed value is an [Map] or `null`.
  ///
  /// Encoded in msgpack packet null or 0 length unpacks to 0 for convenience.
  /// Items of the [Map] must be unpacked manually with respect to returned `length`
  /// Throws [FormatException] if value is not an [Map].
  int unpackMapLength() =>
      _length(
        'Map length',
        fix: 0x80,
        fixMask: 0xF,
        tag16: kTagMap16,
        tag32: kTagMap32,
      ) ??
      0;

  /// Unpack value if packed value is binary or `null`.
  ///
  /// Throws [FormatException] if value is not a binary.
  Uint8List? unpackBinary() => switch (_length(
    'Binary',
    tag8: kTagBin8,
    tag16: kTagBin16,
    tag32: kTagBin32,
  )) {
    final length? => _take(length).asUnmodifiableView(),
    null => null,
  };

  MessageData unpack() => switch (_tag) {
    kTagNil => _read(0, (_) => const MessageDataNull()),
    <= 0x7f ||
    >= 0xe0 ||
    >= kTagUint8 && <= kTagInt64 => MessageDataInt(unpackInt()!),
    kTagFalse || kTagTrue => MessageDataBool(unpackBool()!),
    kTagFloat32 || kTagFloat64 => MessageDataDouble(unpackDouble()!),
    >= 0xa0 && <= 0xbf ||
    kTagStr8 ||
    kTagStr16 ||
    kTagStr32 => MessageDataString(unpackString()!),
    kTagBin8 || kTagBin16 || kTagBin32 => MessageDataBinary(unpackBinary()!),
    >= 0x90 && <= 0x9f ||
    kTagArray16 ||
    kTagArray32 => MessageDataList(unpackList()),
    >= 0x80 && <= 0x8f || kTagMap16 || kTagMap32 => MessageDataMap(unpackMap()),
    final b => throw _formatException('Unknown', b),
  };

  /// Automatically unpacks `bytes` to [List] where items has corresponding data types.
  ///
  /// Return types declared as [MessageData] instead of `dynamic` for safety reasons.
  /// This limits the number of valid types that can be cast to, and since [MessageData]
  /// is a sealed type, a switch over it can be checked for completeness at compile time.
  List<MessageData> unpackList() =>
      List.generate(unpackListLength(), (_) => unpack());

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
    'Try to unpack $type value, but it\'s not an $type, byte = $b',
  );
}
