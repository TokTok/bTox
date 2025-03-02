import 'package:btox/models/bytes.dart';
import 'package:btox/packets/messagepack.dart';
import 'package:btox/packets/packet.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:sodium/sodium.dart';

final class NospamConverter extends TypeConverter<ToxAddressNospam, int>
    with JsonTypeConverter2<ToxAddressNospam, int, int> {
  const NospamConverter();

  @override
  ToxAddressNospam fromJson(int json) => ToxAddressNospam(json);
  @override
  ToxAddressNospam fromSql(int fromDb) => fromJson(fromDb);
  @override
  int toJson(ToxAddressNospam value) => value.value;
  @override
  int toSql(ToxAddressNospam value) => toJson(value);
}

final class PublicKey extends _CryptoBytes with Packet {
  static const kLength = 32;

  PublicKey(super.bytes);

  factory PublicKey.fromJson(String value) {
    return PublicKey(Uint8List.fromList(hex.decode(value)));
  }

  factory PublicKey.unpack(Unpacker unpacker) {
    return PublicKey(unpacker.unpackBinary()!);
  }

  @override
  int get length => PublicKey.kLength;

  @override
  void pack(Packer packer) {
    packer.packBinary(bytes);
  }
}

final class PublicKeyConverter extends TypeConverter<PublicKey, String>
    with JsonTypeConverter2<PublicKey, String, String> {
  const PublicKeyConverter();

  @override
  PublicKey fromJson(String json) => PublicKey.fromJson(json);
  @override
  PublicKey fromSql(String fromDb) => fromJson(fromDb);
  @override
  String toJson(PublicKey value) => value.toJson();
  @override
  String toSql(PublicKey value) => toJson(value);
}

final class SecretKey extends _CryptoBytes {
  static const kLength = 32;

  SecretKey(super.bytes);

  factory SecretKey.fromJson(String value) {
    return SecretKey(Uint8List.fromList(hex.decode(value)));
  }

  factory SecretKey.fromSodium(SecureKey value) {
    return SecretKey(Uint8List.fromList(value.extractBytes()));
  }

  @override
  int get length => SecretKey.kLength;
}

final class SecretKeyConverter extends TypeConverter<SecretKey, String>
    with JsonTypeConverter2<SecretKey, String, String> {
  const SecretKeyConverter();

  @override
  SecretKey fromJson(String json) => SecretKey.fromJson(json);
  @override
  SecretKey fromSql(String fromDb) => fromJson(fromDb);
  @override
  String toJson(SecretKey value) => value.toJson();
  @override
  String toSql(SecretKey value) => toJson(value);
}

final class Sha256 extends _CryptoBytes with Packet {
  static const kLength = 32;

  Sha256(super.bytes);

  factory Sha256.fromDigest(Digest digest) {
    return Sha256(Uint8List.fromList(digest.bytes));
  }

  factory Sha256.fromJson(String value) {
    return Sha256(Uint8List.fromList(hex.decode(value)));
  }

  factory Sha256.unpack(Unpacker unpacker) {
    return Sha256(unpacker.unpackBinary()!);
  }

  @override
  int get length => Sha256.kLength;

  @override
  void pack(Packer packer) {
    packer.packBinary(bytes);
  }
}

final class Sha256Converter extends TypeConverter<Sha256, String>
    with JsonTypeConverter2<Sha256, String, String> {
  const Sha256Converter();

  @override
  Sha256 fromJson(String json) => Sha256.fromJson(json);
  @override
  Sha256 fromSql(String fromDb) => fromJson(fromDb);
  @override
  String toJson(Sha256 value) => value.toJson();
  @override
  String toSql(Sha256 value) => toJson(value);
}

final class ToxAddress extends _CryptoBytes {
  static const kLength = 38;

  ToxAddress(super.bytes);

  factory ToxAddress.fromString(String value) {
    return ToxAddress(Uint8List.fromList(hex.decode(value)));
  }

  ToxAddressHash get hash => ToxAddressHash(bytes.buffer
      .asByteData()
      .getUint16(PublicKey.kLength + ToxAddressNospam.kLength));

  @override
  int get length => ToxAddress.kLength;
  ToxAddressNospam get nospam =>
      ToxAddressNospam(bytes.buffer.asByteData().getUint32(PublicKey.kLength));
  PublicKey get publicKey =>
      PublicKey(Uint8List.view(bytes.buffer, 0, PublicKey.kLength));
}

final class ToxAddressHash extends _CryptoNumber {
  static const kLength = 2;

  ToxAddressHash(super.value) {
    if (value < 0 || value > 0xFFFF) {
      throw ArgumentError('Tox address hash must be a 16-bit unsigned integer');
    }
  }
}

final class ToxAddressNospam extends _CryptoNumber {
  static const kLength = 4;

  ToxAddressNospam(super.value) {
    if (value < 0 || value > 0xFFFFFFFF) {
      throw ArgumentError('Nospam must be a 32-bit unsigned integer');
    }
  }
}

sealed class _CryptoBytes {
  Uint8List _bytes;

  _CryptoBytes(Uint8List bytes) : _bytes = bytes.asUnmodifiableView() {
    if (_bytes.length != length) {
      throw ArgumentError('Invalid $runtimeType length: ${_bytes.length}');
    }
  }

  Uint8List get bytes => _bytes;

  @override
  int get hashCode => memHash(_bytes);

  int get length;

  @override
  bool operator ==(Object other) {
    if (other is _CryptoBytes &&
        other.runtimeType == runtimeType &&
        memEquals(_bytes, other._bytes)) {
      // Speed up future comparisons by making equality a pointer comparison.
      _bytes = other._bytes;
      return true;
    }
    return false;
  }

  String toJson() {
    return hex.encode(_bytes).toUpperCase();
  }

  @override
  String toString() {
    return '$runtimeType(${toJson()})';
  }
}

sealed class _CryptoNumber {
  final int value;

  const _CryptoNumber(this.value);

  @override
  int get hashCode => value;

  @override
  bool operator ==(Object other) {
    return other is _CryptoNumber &&
        other.runtimeType == runtimeType &&
        other.value == value;
  }

  @override
  String toString() {
    return '$runtimeType($value)';
  }
}
