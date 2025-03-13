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
///
/// Streaming packing requires buffer to collect your data.
/// Try to figure out the best initial size of this buffer, that minimal enough to fit your most common data packing scenario.
/// Try to find balance. Provide this value in constructor [Packer()]
final class Packer {
  /// Provide the [_bufSize] size, that minimal enough to fit your most used data packets.
  /// Try to find balance, small buffer is good, and if most of your data will fit to it, performance will be good.
  /// If buffer not enough it will be increased automatically.
  Packer([this._bufSize = 64]) {
    _newBuf(_bufSize);
  }

  int _bufSize;

  late Uint8List _buf;
  late ByteData _d;
  int _offset = 0;

  void _newBuf(int size) {
    _buf = Uint8List(size);
    _d = ByteData.view(_buf.buffer, _buf.offsetInBytes);
    _offset = 0;
  }

  final _builder = BytesBuilder(copy: false);
  final _strCodec = const Utf8Codec();

  void _nextBuf() {
    _flushBuf();
    _bufSize = _bufSize *= 2;
    _newBuf(_bufSize);
  }

  /// Flush [_buf] to [_builder] when [_buf] if almost full
  /// or when packer completes his job and transforms to bytes
  void _flushBuf() {
    _builder.add(Uint8List.view(
      _buf.buffer,
      _buf.offsetInBytes,
      _offset,
    ));
  }

  /// Pack binary and string uses this internally.
  void _putBytes(List<int> bytes) {
    final length = bytes.length;
    if (_buf.length - _offset < length) _nextBuf();
    if (_offset == 0) {
      /// buf flushed to builder, next new buf created, so we can write directly to builder
      _builder.add(bytes);
    } else {
      /// buf has space for us
      _buf.setRange(_offset, _offset + length, bytes);
      _offset += length;
    }
  }

  /// Explicitly pack null value.
  /// Other packXXX implicitly handle null values.
  void packNull() {
    if (_buf.length - _offset < 1) _nextBuf();
    _d.setUint8(_offset++, kTagNil);
  }

  /// Pack [bool] or `null`.
  // ignore: avoid_positional_boolean_parameters
  void packBool(bool? v) {
    if (_buf.length - _offset < 1) _nextBuf();
    if (v == null) {
      _d.setUint8(_offset++, kTagNil);
    } else {
      _d.setUint8(_offset++, v ? kTagTrue : kTagFalse);
    }
  }

  /// Pack [int] or `null`.
  void packInt(int? v) {
    // max 8 byte int + 1 control byte
    if (_buf.length - _offset < 9) _nextBuf();
    if (v == null) {
      _d.setUint8(_offset++, kTagNil);
    } else if (v >= 0) {
      if (v <= 127) {
        _d.setUint8(_offset++, v);
      } else if (v <= 0xFF) {
        _d.setUint8(_offset++, kTagUint8);
        _d.setUint8(_offset++, v);
      } else if (v <= 0xFFFF) {
        _d.setUint8(_offset++, kTagUint16);
        _d.setUint16(_offset, v);
        _offset += 2;
      } else if (v <= 0xFFFFFFFF) {
        _d.setUint8(_offset++, kTagUint32);
        _d.setUint32(_offset, v);
        _offset += 4;
      } else {
        _d.setUint8(_offset++, kTagUint64);
        _setUint64(_d, _offset, v);
        _offset += 8;
      }
    } else if (v >= -32) {
      _d.setInt8(_offset++, v);
    } else if (v >= -128) {
      _d.setUint8(_offset++, kTagInt8);
      _d.setInt8(_offset++, v);
    } else if (v >= -32768) {
      _d.setUint8(_offset++, kTagInt16);
      _d.setInt16(_offset, v);
      _offset += 2;
    } else if (v >= -2147483648) {
      _d.setUint8(_offset++, kTagInt32);
      _d.setInt32(_offset, v);
      _offset += 4;
    } else {
      _d.setUint8(_offset++, kTagInt64);
      _setInt64(_d, _offset, v);
      _offset += 8;
    }
  }

  /// Pack [double] or `null`.
  void packDouble(double? v) {
    // 8 byte double + 1 control byte
    if (_buf.length - _offset < 9) _nextBuf();
    if (v == null) {
      _d.setUint8(_offset++, kTagNil);
      return;
    }
    _d.setUint8(_offset++, kTagFloat64);
    _d.setFloat64(_offset, v);
    _offset += 8;
  }

  /// Pack [String] or `null`.
  ///
  /// Depending on whether your distinguish empty [String] from `null` or not:
  /// - Empty and `null` is same: consider pack empty [String] to `null`, to save 1 byte on a wire.
  /// ```
  /// p.packStringEmptyIsNull(s) //or
  /// p.packString(s.isEmpty ? null : s) //or
  /// s.isEmpty ? p.packNull() : p.packString(s)
  /// ```
  /// - Empty and `null` distinguishable: no action required just save `p.packString(s)`.
  /// Throws [ArgumentError] if [String.length] exceed (2^32)-1.
  void packString(String? v) {
    // max 4 byte str header + 1 control byte
    if (_buf.length - _offset < 5) _nextBuf();
    if (v == null) {
      _d.setUint8(_offset++, kTagNil);
      return;
    }
    final encoded = _strCodec.encode(v);
    final length = encoded.length;
    if (length <= 31) {
      _d.setUint8(_offset++, 0xA0 | length);
    } else if (length <= 0xFF) {
      _d.setUint8(_offset++, kTagStr8);
      _d.setUint8(_offset++, length);
    } else if (length <= 0xFFFF) {
      _d.setUint8(_offset++, kTagStr16);
      _d.setUint16(_offset, length);
      _offset += 2;
    } else if (length <= 0xFFFFFFFF) {
      _d.setUint8(_offset++, kTagStr32);
      _d.setUint32(_offset, length);
      _offset += 4;
    } else {
      throw ArgumentError('Max String length is 0xFFFFFFFF');
    }
    _putBytes(encoded);
  }

  /// Convenient function that call [packString(v)] by passing empty [String] as `null`.
  ///
  /// Convenient when you not distinguish between empty [String] and null on msgpack wire.
  /// See [packString] method documentation for more details.
  void packStringEmptyIsNull(String? v) {
    if (v == null || v.isEmpty) {
      packNull();
    } else {
      packString(v);
    }
  }

  /// Pack `List<int>` or null.
  void packBinary(List<int>? buffer) {
    // max 4 byte binary header + 1 control byte
    if (_buf.length - _offset < 5) _nextBuf();
    if (buffer == null) {
      _d.setUint8(_offset++, kTagNil);
      return;
    }
    final length = buffer.length;
    if (length <= 0xFF) {
      _d.setUint8(_offset++, kTagBin8);
      _d.setUint8(_offset++, length);
    } else if (length <= 0xFFFF) {
      _d.setUint8(_offset++, kTagBin16);
      _d.setUint16(_offset, length);
      _offset += 2;
    } else if (length <= 0xFFFFFFFF) {
      _d.setUint8(_offset++, kTagBin32);
      _d.setUint32(_offset, length);
      _offset += 4;
    } else {
      throw ArgumentError('Max binary length is 0xFFFFFFFF');
    }
    _putBytes(buffer);
  }

  /// Pack [List.length] or `null`.
  void packListLength(int? length) {
    // max 4 length header + 1 control byte
    if (_buf.length - _offset < 5) _nextBuf();
    if (length == null) {
      _d.setUint8(_offset++, kTagNil);
    } else if (length <= 0xF) {
      _d.setUint8(_offset++, 0x90 | length);
    } else if (length <= 0xFFFF) {
      _d.setUint8(_offset++, kTagArray16);
      _d.setUint16(_offset, length);
      _offset += 2;
    } else if (length <= 0xFFFFFFFF) {
      _d.setUint8(_offset++, kTagArray32);
      _d.setUint32(_offset, length);
      _offset += 4;
    } else {
      throw ArgumentError('Max list length is 0xFFFFFFFF');
    }
  }

  /// Pack [Map.length] or `null`.
  void packMapLength(int? length) {
    // max 4 byte header + 1 control byte
    if (_buf.length - _offset < 5) _nextBuf();
    if (length == null) {
      _d.setUint8(_offset++, kTagNil);
    } else if (length <= 0xF) {
      _d.setUint8(_offset++, 0x80 | length);
    } else if (length <= 0xFFFF) {
      _d.setUint8(_offset++, kTagMap16);
      _d.setUint16(_offset, length);
      _offset += 2;
    } else if (length <= 0xFFFFFFFF) {
      _d.setUint8(_offset++, kTagMap32);
      _d.setUint32(_offset, length);
      _offset += 4;
    } else {
      throw ArgumentError('Max map length is 0xFFFFFFFF');
    }
  }

  void packMessageData(MessageData data) {
    data.pack(this);
  }

  void pack(Packet packet) {
    packet.pack(this);
  }

  /// Get bytes representation of this packer.
  /// Note: after this call do not reuse packer - create new.
  Uint8List takeBytes() {
    Uint8List bytes;
    if (_builder.isEmpty) {
      bytes = Uint8List.view(
        _buf.buffer,
        _buf.offsetInBytes,
        _offset,
      );
    } else {
      _flushBuf();
      bytes = _builder.takeBytes();
    }
    return bytes;
  }
}
