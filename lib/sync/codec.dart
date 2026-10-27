import 'dart:typed_data';

import 'package:btox/packets/messagepack.dart';

/// The most milliseconds from the epoch a time may be, either way, as Rust's
/// `MAX_TIME`: as far as dates go.
const maxTime = 8640000000000000;

/// [ms] as a time, which throws a [FormatException] where no date is.
int checkTime(int ms) => ms >= -maxTime && ms <= maxTime
    ? ms
    : throw const FormatException('Time out of range');

final class ArrayWriter {
  final _items = <void Function(Packer)>[];

  ArrayWriter _add(void Function(Packer) write) {
    _items.add(write);
    return this;
  }

  ArrayWriter uint(int value) {
    RangeError.checkNotNegative(value);
    return _add((p) => p.packInt(value));
  }

  ArrayWriter sint(int value) => _add((p) => p.packInt(value));

  ArrayWriter flag(bool value) => _add((p) => p.packBool(value));

  ArrayWriter bin(List<int> value) => _add((p) => p.packBinary(value));

  ArrayWriter string(String value) => _add((p) => p.packString(value));

  // tox-proto writes an absent value as [] and a present one as [value].
  ArrayWriter optBin(List<int>? value) =>
      array(value == null ? ArrayWriter() : ArrayWriter().bin(value));

  ArrayWriter optString(String? value) =>
      array(value == null ? ArrayWriter() : ArrayWriter().string(value));

  ArrayWriter optUint(int? value) =>
      array(value == null ? ArrayWriter() : ArrayWriter().uint(value));

  ArrayWriter optArray(ArrayWriter? value) =>
      array(value == null ? ArrayWriter() : ArrayWriter().array(value));

  ArrayWriter array(ArrayWriter value) => _add(value._write);

  /// A value encoded already.
  ArrayWriter raw(Uint8List value) => _add((p) => p.packRaw(value));

  void _write(Packer packer) {
    packer.packListLength(_items.length);
    for (final write in _items) {
      write(packer);
    }
  }

  Uint8List encode() {
    final packer = Packer();
    _write(packer);
    return packer.takeBytes();
  }
}

final class Fields {
  final Unpacker _unpacker;
  int _left;

  Fields(this._unpacker) : _left = _unpacker.unpackListLength();

  void _next() {
    if (_left == 0) {
      throw const FormatException('Missing field');
    }
    _left--;
  }

  T _required<T>(T? value) =>
      value ?? (throw const FormatException('Missing value'));

  int uint() {
    _next();
    final value = _required(_unpacker.unpackInt());
    if (value < 0) {
      throw const FormatException('Negative value');
    }
    return value;
  }

  int sint() {
    _next();
    return _required(_unpacker.unpackInt());
  }

  bool flag() {
    _next();
    return _required(_unpacker.unpackBool());
  }

  Uint8List bin() {
    _next();
    return _required(_unpacker.unpackBinary());
  }

  String string() {
    _next();
    return _required(_unpacker.unpackString());
  }

  /// A field written by [ArrayWriter.optBin] and the like. Missing at the
  /// end, as in older encodings, it's absent too.
  T? opt<T>(T Function(Fields) read) {
    if (_left == 0) {
      return null;
    }
    if (!_unpacker.hasList) {
      throw const FormatException('Not an option');
    }
    final option = array();
    final value = switch (option._left) {
      0 => null,
      1 => read(option),
      _ => throw const FormatException('Not an option'),
    };
    option.exact();
    return value;
  }

  Uint8List? optBin() => opt((f) => f.bin());

  String? optString() => opt((f) => f.string());

  int? optUint() => opt((f) => f.uint());

  /// A flag added to a struct later: false when missing, as in older
  /// encodings.
  bool laterFlag() => _left > 0 && flag();

  /// See [readVariant].
  T variant<T>(
    T? Function(int tag, Fields payload) known,
    T Function(int) unknown,
  ) {
    _next();
    return readVariant(_unpacker, known, unknown);
  }

  /// The next value, as it's encoded.
  Uint8List raw() {
    _next();
    return _unpacker.takeValue();
  }

  /// Reads a struct of fields, and skips the ones this version doesn't know.
  T fields<T>(T Function(Fields) read) {
    final fields = array();
    final value = read(fields);
    fields.end();
    return value;
  }

  /// Reads a tuple, which has exactly the items [read] reads.
  T tuple<T>(T Function(Fields) read) {
    final items = array();
    final value = read(items);
    items.exact();
    return value;
  }

  /// Call [end] on it before reading on here.
  Fields array() {
    _next();
    return Fields(_unpacker);
  }

  List<T> list<T>(T Function(Fields) item) {
    final list = array();
    final items = <T>[];
    while (list._left > 0) {
      items.add(item(list));
    }
    return items;
  }

  /// Skips the fields this version doesn't know.
  void end() {
    while (_left > 0) {
      _left--;
      _unpacker.skip();
    }
  }

  /// For tuples and variants, which never gain fields.
  void exact() {
    if (_left != 0) {
      throw const FormatException('Unexpected fields');
    }
  }
}

/// A tox-proto enum value: a bare tag, or `[tag, payload]`. [known] reads a
/// payload from the [Fields] it's given, or returns null for a tag it doesn't
/// know, whose payload is then skipped for [unknown].
T readVariant<T>(
  Unpacker unpacker,
  T? Function(int tag, Fields payload) known,
  T Function(int tag) unknown,
) {
  if (!unpacker.hasList) {
    return unknown(
      unpacker.unpackInt() ?? (throw const FormatException('Missing tag')),
    );
  }
  final variant = Fields(unpacker);
  final tag = variant.uint();
  final value = known(tag, variant);
  if (value == null) {
    variant.end();
    return unknown(tag);
  }
  variant.exact();
  return value;
}

/// A `#[tox(lenient)]` enum value: `[kind, [fields]]`. [known] reads the
/// fields of a kind it knows. A kind whose fields don't decode is [unknown],
/// as one it doesn't know.
T readLenient<T>(
  Unpacker unpacker,
  T? Function(int kind, Fields fields) known,
  T Function(int kind) unknown,
) => readVariant(unpacker, (kind, payload) {
  if (payload._left != 1) {
    return null;
  }
  payload._next();
  try {
    return decodeExact(payload._unpacker.takeValue(), (unpacker) {
      final fields = Fields(unpacker);
      final value = known(kind, fields);
      fields.end();
      return value;
    });
  } on FormatException {
    return null;
  }
}, unknown);

/// A value with the bytes it was read from, which it's written as, so what
/// this version doesn't know of it is kept. Equal by value.
final class Kept<T> {
  final T value;
  final Uint8List? bytes;

  const Kept(this.value) : bytes = null;

  const Kept.read(this.value, Uint8List this.bytes);

  @override
  bool operator ==(Object other) => other is Kept<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Kept($value)';
}

/// [edited], the encoding of a struct, with the fields of [old], an encoding
/// of it by a version that knows more of them, after its own.
Uint8List carry(Uint8List old, Uint8List edited) {
  final (oldFields, newFields) = (Unpacker(old), Unpacker(edited));
  final (had, has) = (
    oldFields.unpackListLength(),
    newFields.unpackListLength(),
  );
  if (had <= has) {
    return edited;
  }
  for (var i = 0; i < has; i++) {
    oldFields.skip();
  }
  final packer = Packer()..packListLength(had);
  for (final fields in [newFields, oldFields]) {
    while (!fields.isDone) {
      packer.packRaw(fields.takeValue());
    }
  }
  return packer.takeBytes();
}

/// Decodes a whole value from [bytes], with nothing after it.
T decodeExact<T>(Uint8List bytes, T Function(Unpacker) read) {
  final unpacker = Unpacker(bytes);
  final T value;
  try {
    value = read(unpacker);
  } on ArgumentError catch (e) {
    // Such as a key of the wrong length.
    throw FormatException('Invalid value: ${e.message}');
  }
  if (!unpacker.isDone) {
    throw const FormatException('Trailing bytes after value');
  }
  return value;
}
