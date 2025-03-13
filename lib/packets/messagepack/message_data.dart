import 'dart:typed_data';

import 'package:btox/models/bytes.dart';
import 'package:btox/packets/messagepack/message_data_json_converter.dart';
import 'package:btox/packets/messagepack/packer.dart';

/// Represents dynamic data unpacked from messagepack.
///
/// This is slower than a well-known data structure, but it's useful for
/// representing arbitrary data.
sealed class MessageData<T extends MessageData<T>> {
  const MessageData();

  @override
  int get hashCode => _hashCode;
  int get _hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is T && _equals(other);

  void pack(Packer packer);

  String toJson() => const MessageDataJsonConverter().toJson(this);

  bool _equals(T other);

  static MessageData fromJson(String json) =>
      const MessageDataJsonConverter().fromJson(json);
}

final class MessageDataBinary extends MessageData<MessageDataBinary> {
  final Uint8List value;

  const MessageDataBinary(this.value);

  @override
  int get _hashCode => memHash(value);

  @override
  void pack(Packer packer) {
    packer.packBinary(value);
  }

  @override
  String toString() => 'MessageDataBinary($value)';

  @override
  bool _equals(MessageDataBinary other) => memEquals(value, other.value);
}

final class MessageDataBool extends MessageData<MessageDataBool> {
  final bool value;

  const MessageDataBool(this.value);

  @override
  int get _hashCode => value.hashCode;

  @override
  void pack(Packer packer) {
    packer.packBool(value);
  }

  @override
  String toString() => 'MessageDataBool($value)';

  @override
  bool _equals(MessageDataBool other) => value == other.value;
}

final class MessageDataDouble extends MessageData<MessageDataDouble> {
  final double value;

  const MessageDataDouble(this.value);

  @override
  int get _hashCode => value.hashCode;

  @override
  void pack(Packer packer) {
    packer.packDouble(value);
  }

  @override
  String toString() => 'MessageDataDouble($value)';

  @override
  bool _equals(MessageDataDouble other) => value == other.value;
}

final class MessageDataInt extends MessageData<MessageDataInt> {
  final int value;

  const MessageDataInt(this.value);

  @override
  int get _hashCode => value.hashCode;

  @override
  void pack(Packer packer) {
    packer.packInt(value);
  }

  @override
  String toString() => 'MessageDataInt($value)';

  @override
  bool _equals(MessageDataInt other) => value == other.value;
}

final class MessageDataList extends MessageData<MessageDataList> {
  final List<MessageData> value;

  const MessageDataList(this.value);

  @override
  int get _hashCode => value.hashCode;

  @override
  void pack(Packer packer) {
    packer.packListLength(value.length);
    for (final e in value) {
      e.pack(packer);
    }
  }

  @override
  String toString() => 'MessageDataList($value)';

  @override
  bool _equals(MessageDataList other) =>
      value.length == other.value.length &&
      List.generate(value.length, (i) => value[i]._equals(other.value[i]))
          .every((e) => e);
}

final class MessageDataMap extends MessageData<MessageDataMap> {
  final Map<MessageData, MessageData> value;

  const MessageDataMap(this.value);

  @override
  int get _hashCode => value.hashCode;

  @override
  void pack(Packer packer) {
    packer.packMapLength(value.length);
    for (final entry in value.entries) {
      entry.key.pack(packer);
      entry.value.pack(packer);
    }
  }

  @override
  String toString() => 'MessageDataMap($value)';

  @override
  bool _equals(MessageDataMap other) =>
      value.length == other.value.length &&
      value.entries
          .map((e) => other.value[e.key]?._equals(e.value) ?? false)
          .every((e) => e);
}

final class MessageDataNull extends MessageData<MessageDataNull> {
  const MessageDataNull();

  @override
  int get _hashCode => 0;

  @override
  void pack(Packer packer) {
    packer.packNull();
  }

  @override
  String toString() => 'MessageDataNull()';

  @override
  bool _equals(MessageDataNull other) => true;
}

final class MessageDataString extends MessageData<MessageDataString> {
  final String value;

  const MessageDataString(this.value);

  @override
  int get _hashCode => value.hashCode;

  @override
  void pack(Packer packer) {
    packer.packString(value);
  }

  @override
  String toString() => 'MessageDataString($value)';

  @override
  bool _equals(MessageDataString other) => value == other.value;
}
