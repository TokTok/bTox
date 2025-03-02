// ignore_for_file: invalid_annotation_target

import 'dart:convert';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/packets/messagepack/packer.dart';
import 'package:btox/packets/messagepack/unpacker.dart';
import 'package:btox/packets/packet.dart';
import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'content.freezed.dart';
part 'content.g.dart';

const _logger = Logger(['Content']);

sealed class Content extends Packet {
  const Content();

  factory Content.decode(Uint8List data) {
    return Content.unpack(Unpacker(data));
  }

  factory Content.unpack(Unpacker unpacker) {
    final int length = unpacker.unpackListLength();
    if (length != 2) {
      throw Exception('Invalid content packet');
    }

    final int index = unpacker.unpackInt()!;
    final ContentType type =
        ContentType.values.elementAtOrNull(index) ?? ContentType.unknown;
    switch (type) {
      case ContentType.unknown:
        return UnknownContent.unpack(unpacker);
      case ContentType.text:
        return TextContent.unpack(unpacker);
      case ContentType.reaction:
        return ReactionContent.unpack(unpacker);
      case ContentType.edit:
        return EditContent.unpack(unpacker);
      case ContentType.delete:
        return DeleteContent.unpack(unpacker);
      case ContentType.media:
        return MediaContent.unpack(unpacker);
      case ContentType.file:
        return FileContent.unpack(unpacker);
      case ContentType.location:
        return LocationContent.unpack(unpacker);
    }
  }

  ContentType get type;

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packInt(type.index);
    packContent(packer);
  }

  void packContent(Packer packer);

  Map<String, dynamic> toJson();
}

final class ContentConverter extends TypeConverter<Content, String>
    with JsonTypeConverter2<Content, String, Map<String, dynamic>> {
  const ContentConverter();

  @override
  Content fromJson(Map<String, dynamic> json) {
    switch (ContentType.values.firstWhere((e) => e.name == json['_type'],
        orElse: () => ContentType.unknown)) {
      case ContentType.unknown:
        return UnknownContent.fromJson(json);
      case ContentType.text:
        return TextContent.fromJson(json);
      case ContentType.reaction:
        return ReactionContent.fromJson(json);
      case ContentType.edit:
        return EditContent.fromJson(json);
      case ContentType.delete:
        return DeleteContent.fromJson(json);
      case ContentType.media:
        return MediaContent.fromJson(json);
      case ContentType.file:
        return FileContent.fromJson(json);
      case ContentType.location:
        return LocationContent.fromJson(json);
    }
  }

  @override
  Content fromSql(String fromDb) {
    try {
      return fromJson(jsonDecode(fromDb));
    } catch (e) {
      // Fallback to rendering as text content.
      _logger.v('Failed to parse content: $e');
      return TextContent(text: fromDb);
    }
  }

  @override
  Map<String, dynamic> toJson(Content value) {
    return {
      '_type': value.type.name,
      ...value.toJson(),
    };
  }

  @override
  String toSql(Content value) => jsonEncode(toJson(value));
}

enum ContentType {
  unknown,
  text,
  reaction,
  edit,
  delete,
  media,
  file,
  location,
}

@freezed
sealed class DeleteContent extends Content with _$DeleteContent {
  @JsonSerializable(explicitToJson: true)
  const factory DeleteContent({
    required Sha256 message,
  }) = _DeleteContent;

  factory DeleteContent.fromJson(Map<String, dynamic> json) =>
      _$DeleteContentFromJson(json);

  factory DeleteContent.unpack(Unpacker unpacker) {
    return DeleteContent(message: Sha256.unpack(unpacker));
  }

  const DeleteContent._();

  @override
  ContentType get type => ContentType.delete;

  @override
  void packContent(Packer packer) {
    packer.pack(message);
  }
}

@freezed
sealed class EditContent extends Content with _$EditContent {
  @JsonSerializable(explicitToJson: true)
  const factory EditContent({
    required Sha256 message,
    required String text,
  }) = _EditContent;

  factory EditContent.fromJson(Map<String, dynamic> json) =>
      _$EditContentFromJson(json);

  factory EditContent.unpack(Unpacker unpacker) {
    final length = unpacker.unpackListLength();
    if (length != 2) {
      throw Exception('Invalid edit content');
    }
    return EditContent(
      message: Sha256.unpack(unpacker),
      text: utf8.decode(unpacker.unpackBinary()!),
    );
  }

  const EditContent._();

  @override
  ContentType get type => ContentType.edit;

  @override
  void packContent(Packer packer) {
    packer
      ..packListLength(2)
      ..pack(message)
      ..packBinary(utf8.encode(text));
  }
}

@freezed
sealed class FileContent extends Content with _$FileContent {
  const factory FileContent({
    required String url,
  }) = _FileContent;

  factory FileContent.fromJson(Map<String, dynamic> json) =>
      _$FileContentFromJson(json);

  factory FileContent.unpack(Unpacker unpacker) {
    return FileContent(url: utf8.decode(unpacker.unpackBinary()!));
  }

  const FileContent._();

  @override
  ContentType get type => ContentType.file;

  @override
  void packContent(Packer packer) {
    packer.packBinary(utf8.encode(url));
  }
}

@freezed
sealed class LocationContent extends Content with _$LocationContent {
  const factory LocationContent({
    required double latitude,
    required double longitude,
  }) = _LocationContent;

  factory LocationContent.fromJson(Map<String, dynamic> json) =>
      _$LocationContentFromJson(json);

  factory LocationContent.unpack(Unpacker unpacker) {
    final length = unpacker.unpackListLength();
    if (length != 2) {
      throw Exception('Invalid location content');
    }
    return LocationContent(
      latitude: unpacker.unpackDouble()!,
      longitude: unpacker.unpackDouble()!,
    );
  }

  const LocationContent._();

  @override
  ContentType get type => ContentType.location;

  @override
  void packContent(Packer packer) {
    packer
      ..packListLength(2)
      ..packDouble(latitude)
      ..packDouble(longitude);
  }
}

@freezed
sealed class MediaContent extends Content with _$MediaContent {
  const factory MediaContent({
    required String url,
  }) = _MediaContent;

  factory MediaContent.fromJson(Map<String, dynamic> json) =>
      _$MediaContentFromJson(json);

  factory MediaContent.unpack(Unpacker unpacker) {
    return MediaContent(url: utf8.decode(unpacker.unpackBinary()!));
  }

  const MediaContent._();

  @override
  ContentType get type => ContentType.media;

  @override
  void packContent(Packer packer) {
    packer.packBinary(utf8.encode(url));
  }
}

@freezed
sealed class ReactionContent extends Content with _$ReactionContent {
  @JsonSerializable(explicitToJson: true)
  const factory ReactionContent({
    required Sha256 message,
    required String emoji,
  }) = _ReactionContent;

  factory ReactionContent.fromJson(Map<String, dynamic> json) =>
      _$ReactionContentFromJson(json);

  factory ReactionContent.unpack(Unpacker unpacker) {
    final length = unpacker.unpackListLength();
    if (length != 2) {
      throw Exception('Invalid reaction content');
    }
    return ReactionContent(
      message: Sha256.unpack(unpacker),
      emoji: utf8.decode(unpacker.unpackBinary()!),
    );
  }

  const ReactionContent._();

  @override
  ContentType get type => ContentType.reaction;

  @override
  void packContent(Packer packer) {
    packer
      ..packListLength(2)
      ..pack(message)
      ..packBinary(utf8.encode(emoji));
  }
}

@freezed
sealed class TextContent extends Content with _$TextContent {
  const factory TextContent({required String text}) = _TextContent;

  factory TextContent.fromJson(Map<String, dynamic> json) =>
      _$TextContentFromJson(json);

  factory TextContent.unpack(Unpacker unpacker) {
    return TextContent(text: utf8.decode(unpacker.unpackBinary()!));
  }

  const TextContent._();

  @override
  ContentType get type => ContentType.text;

  @override
  void packContent(Packer packer) {
    packer.packBinary(utf8.encode(text));
  }
}

@freezed
sealed class UnknownContent extends Content with _$UnknownContent {
  @Uint8ListConverter()
  const factory UnknownContent({required Uint8List data}) = _UnknownContent;

  factory UnknownContent.fromJson(Map<String, dynamic> json) =>
      _$UnknownContentFromJson(json);

  factory UnknownContent.unpack(Unpacker unpacker) {
    return UnknownContent(data: unpacker.unpackBinary()!);
  }

  const UnknownContent._();

  @override
  ContentType get type => ContentType.unknown;

  @override
  void packContent(Packer packer) {
    packer.packBinary(data);
  }
}
