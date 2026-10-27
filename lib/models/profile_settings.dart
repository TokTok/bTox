import 'dart:convert';

import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile_settings.g.dart';
part 'profile_settings.freezed.dart';

enum ProxyType { none, http, socks5 }

@freezed
abstract class NetworkSettings with _$NetworkSettings {
  const factory NetworkSettings({
    @Default(true) bool udpEnabled,
    @Default(true) bool ipv6Enabled,
    @Default(true) bool localDiscoveryEnabled,
    @Default(ProxyType.none) ProxyType proxyType,
    @Default('127.0.0.1') String proxyHost,
    @Default(9050) int proxyPort,
  }) = _NetworkSettings;

  factory NetworkSettings.fromJson(Map<String, dynamic> json) =>
      _$NetworkSettingsFromJson(json);

  const NetworkSettings._();

  bool get usesProxy => proxyType != ProxyType.none;
}

@freezed
abstract class ProfileSettings with _$ProfileSettings {
  // ignore: invalid_annotation_target
  @JsonSerializable(explicitToJson: true)
  const factory ProfileSettings({
    required String nickname,
    required String statusMessage,
    @Default(NetworkSettings()) NetworkSettings network,
    @Default([]) List<String> messageFormatsOff,
  }) = _ProfileSettings;

  factory ProfileSettings.fromJson(Map<String, dynamic> json) =>
      _$ProfileSettingsFromJson(json);
}

final class ProfileSettingsConverter
    extends TypeConverter<ProfileSettings, String>
    with JsonTypeConverter2<ProfileSettings, String, Map<String, dynamic>> {
  const ProfileSettingsConverter();

  @override
  ProfileSettings fromJson(Map<String, dynamic> json) =>
      ProfileSettings.fromJson(json);
  @override
  ProfileSettings fromSql(String fromDb) => fromJson(jsonDecode(fromDb));
  @override
  Map<String, dynamic> toJson(ProfileSettings value) => value.toJson();
  @override
  String toSql(ProfileSettings value) => jsonEncode(toJson(value));
}
