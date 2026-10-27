import 'dart:convert';

import 'package:btox/logger.dart';
import 'package:drift/drift.dart' show JsonTypeConverter2, TypeConverter;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'content.freezed.dart';
part 'content.g.dart';

const _logger = Logger(['Content']);

const _maxLatitude = 90;
const _maxLongitude = 180;

final _geo = RegExp(r'^geo:(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$');

/// [content] as a message's text, where it can be one. Until clients can
/// agree on richer content, locations travel as text.
String? messageTextOf(Content content) => switch (content) {
  TextContent(:final text) => text,
  LocationContent(:final latitude, :final longitude) =>
    'geo:$latitude,$longitude',
  FileContent() => null,
};

/// [text] as Tox clients quote it: each line after "> ".
String quoted(String text) =>
    [for (final line in text.split('\n')) '> $line'].join('\n');

/// The content a message's [text] stands for: a place on Earth, or else the
/// text as it is.
Content contentOfMessage(String text) {
  if (_geo.firstMatch(text) case final match?) {
    final latitude = double.parse(match[1]!);
    final longitude = double.parse(match[2]!);
    if (latitude.abs() <= _maxLatitude && longitude.abs() <= _maxLongitude) {
      return LocationContent(latitude: latitude, longitude: longitude);
    }
  }
  return TextContent(text: text);
}

sealed class Content {
  const Content();

  ContentType get type;

  Map<String, dynamic> toJson();

  /// What the message says, e.g. for copying it.
  String get plainText => switch (this) {
    TextContent(:final text) => text,
    FileContent(:final name) => name,
    LocationContent() => messageTextOf(this)!,
  };
}

/// Content as drafts keep it.
final class ContentConverter extends TypeConverter<Content, String>
    with JsonTypeConverter2<Content, String, Map<String, dynamic>> {
  const ContentConverter();

  @override
  Content fromJson(Map<String, dynamic> json) =>
      switch (ContentType.values.asNameMap()[json['_type']]) {
        ContentType.text => TextContent.fromJson(json),
        ContentType.file => FileContent.fromJson(json),
        ContentType.location => LocationContent.fromJson(json),
        null => throw FormatException('Unknown content ${json['_type']}'),
      };

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
  Map<String, dynamic> toJson(Content value) => {
    '_type': value.type.name,
    ...value.toJson(),
  };

  @override
  String toSql(Content value) => jsonEncode(toJson(value));
}

final class ContentListConverter extends TypeConverter<List<Content>, String> {
  const ContentListConverter();

  /// Leaves out what this version can't read, as a newer one's.
  @override
  List<Content> fromSql(String fromDb) => [
    for (final json in jsonDecode(fromDb) as List) ?_read(json),
  ];

  static Content? _read(Object? json) {
    try {
      return const ContentConverter().fromJson(json as Map<String, dynamic>);
    } on Object catch (e) {
      _logger.w('Left out content this version can\'t read: $e');
      return null;
    }
  }

  @override
  String toSql(List<Content> value) => jsonEncode([
    for (final content in value) const ContentConverter().toJson(content),
  ]);
}

enum ContentType { text, file, location }

@freezed
sealed class FileContent extends Content with _$FileContent {
  // Defaults keep placeholder file messages from older versions loading.
  const factory FileContent({
    @Default('') String name,
    @Default(0) int size,
    @Default('') String path,
  }) = _FileContent;

  factory FileContent.fromJson(Map<String, dynamic> json) =>
      _$FileContentFromJson(json);

  const FileContent._();

  @override
  ContentType get type => ContentType.file;
}

@freezed
sealed class LocationContent extends Content with _$LocationContent {
  const factory LocationContent({
    required double latitude,
    required double longitude,
  }) = _LocationContent;

  factory LocationContent.fromJson(Map<String, dynamic> json) =>
      _$LocationContentFromJson(json);

  const LocationContent._();

  @override
  ContentType get type => ContentType.location;
}

@freezed
sealed class TextContent extends Content with _$TextContent {
  const factory TextContent({required String text}) = _TextContent;

  factory TextContent.fromJson(Map<String, dynamic> json) =>
      _$TextContentFromJson(json);

  const TextContent._();

  @override
  ContentType get type => ContentType.text;
}
