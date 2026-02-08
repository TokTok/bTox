import 'dart:convert';

import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile_settings.g.dart';
part 'profile_settings.freezed.dart';

@freezed
abstract class ProfileSettings with _$ProfileSettings {
  const factory ProfileSettings({
    required String nickname,
    required String statusMessage,
  }) = _ProfileSettings;

  factory ProfileSettings.fromJson(Map<String, dynamic> json) =>
      _$ProfileSettingsFromJson(json);
}

final class ProfileSettingsConverter
    extends TypeConverter<ProfileSettings, String>
    with JsonTypeConverter2<ProfileSettings, String, Map<String, dynamic>> {
  const ProfileSettingsConverter();

  @override
  ProfileSettings fromJson(Map<String, dynamic> json) {
    return ProfileSettings.fromJson(json);
  }

  @override
  ProfileSettings fromSql(String fromDb) {
    return fromJson(jsonDecode(fromDb));
  }

  @override
  Map<String, dynamic> toJson(ProfileSettings value) {
    return value.toJson();
  }

  @override
  String toSql(ProfileSettings value) {
    return jsonEncode(toJson(value));
  }
}
