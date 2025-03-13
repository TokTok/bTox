import 'package:btox/packets/converters.dart';
import 'package:btox/packets/messagepack.dart';
import 'package:btox/packets/messagepack/message_data.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

/// Just use msgpack to serialize the data. We care about round-trip safety,
/// not whether the JSON output is readable.
final class MessageDataJsonConverter
    extends JsonConverter<MessageData, String> {
  const MessageDataJsonConverter();

  @override
  MessageData fromJson(String json) {
    return Unpacker(Uint8ListConverter().fromJson(json)).unpack();
  }

  @override
  String toJson(MessageData object) {
    return Uint8ListConverter()
        .toJson((Packer()..packMessageData(object)).takeBytes());
  }
}
