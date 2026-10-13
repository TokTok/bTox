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

/// Stores keys and hashes as hex strings.
final class HexConverter<T extends CryptoBytes> extends TypeConverter<T, String>
    with JsonTypeConverter2<T, String, String> {
  final T Function(String) _fromJson;

  const HexConverter(this._fromJson);

  @override
  T fromJson(String json) => _fromJson(json);
  @override
  T fromSql(String fromDb) => fromJson(fromDb);
  @override
  String toJson(T value) => value.toJson();
  @override
  String toSql(T value) => toJson(value);
}

final class PublicKey extends CryptoBytes {
  static const kLength = 32;

  PublicKey(super.bytes);

  factory PublicKey.fromJson(String value) =>
      PublicKey(Uint8List.fromList(hex.decode(value)));

  factory PublicKey.unpack(Unpacker unpacker) =>
      PublicKey(unpacker.unpackBinary()!);

  @override
  int get length => PublicKey.kLength;
}

final class SecretKey extends CryptoBytes {
  static const kLength = 32;

  SecretKey(super.bytes);

  factory SecretKey.fromJson(String value) =>
      SecretKey(Uint8List.fromList(hex.decode(value)));

  factory SecretKey.fromSodium(SecureKey value) =>
      SecretKey(Uint8List.fromList(value.extractBytes()));

  @override
  int get length => SecretKey.kLength;
}

final class Sha256 extends CryptoBytes with Packet {
  static const kLength = 32;

  Sha256(super.bytes);

  factory Sha256.fromDigest(Digest digest) =>
      Sha256(Uint8List.fromList(digest.bytes));

  factory Sha256.fromJson(String value) =>
      Sha256(Uint8List.fromList(hex.decode(value)));

  factory Sha256.unpack(Unpacker unpacker) => Sha256(unpacker.unpackBinary()!);

  @override
  int get length => Sha256.kLength;

  @override
  void pack(Packer packer) {
    packer.packBinary(bytes);
  }
}

final class ToxAddress extends CryptoBytes {
  static const kLength = 38;
  static const kChecksumLength = 2;

  ToxAddress(super.bytes);

  factory ToxAddress.fromString(String value) =>
      ToxAddress(Uint8List.fromList(hex.decode(value)));

  factory ToxAddress.of(PublicKey publicKey, ToxAddressNospam nospam) {
    final bytes = Uint8List(kLength)..setAll(0, publicKey.bytes);
    bytes.buffer.asByteData().setUint32(PublicKey.kLength, nospam.value);
    bytes.setAll(kLength - kChecksumLength, _checksum(bytes));
    return ToxAddress(bytes);
  }

  bool get hasValidChecksum {
    final checksum = _checksum(bytes);
    final end = kLength - kChecksumLength;
    return bytes[end] == checksum[0] && bytes[end + 1] == checksum[1];
  }

  static List<int> _checksum(Uint8List bytes) {
    final checksum = [0, 0];
    for (var i = 0; i < PublicKey.kLength + ToxAddressNospam.kLength; i++) {
      checksum[i % 2] ^= bytes[i];
    }
    return checksum;
  }

  @override
  int get length => ToxAddress.kLength;
  ToxAddressNospam get nospam =>
      ToxAddressNospam(bytes.buffer.asByteData().getUint32(PublicKey.kLength));
  PublicKey get publicKey =>
      PublicKey(Uint8List.view(bytes.buffer, 0, PublicKey.kLength));
}

final class ToxAddressNospam {
  static const kLength = 4;

  final int value;

  ToxAddressNospam(this.value) {
    if (value < 0 || value > 0xFFFFFFFF) {
      throw ArgumentError('Nospam must be a 32-bit unsigned integer');
    }
  }

  @override
  int get hashCode => value;

  @override
  bool operator ==(Object other) =>
      other is ToxAddressNospam && other.value == value;

  @override
  String toString() => 'ToxAddressNospam($value)';
}

sealed class CryptoBytes {
  Uint8List _bytes;

  CryptoBytes(Uint8List bytes) : _bytes = bytes.asUnmodifiableView() {
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
    if (other is CryptoBytes &&
        other.runtimeType == runtimeType &&
        memEquals(_bytes, other._bytes)) {
      // Speed up future comparisons by making equality a pointer comparison.
      _bytes = other._bytes;
      return true;
    }
    return false;
  }

  String toJson() => hex.encode(_bytes).toUpperCase();

  @override
  String toString() => '$runtimeType(${toJson()})';
}
