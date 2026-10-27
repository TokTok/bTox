import 'package:btox/db/database.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/database.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles.g.dart';

@Riverpod(keepAlive: true)
Stream<List<Profile>> profiles(Ref ref) =>
    watchDb(ref, (db) => db.watchProfiles());

@Riverpod(keepAlive: true)
Stream<AppSetting> appSettings(Ref ref) =>
    watchDb(ref, (db) => db.watchAppSettings());

@Riverpod(keepAlive: true)
List<Profile> signedInProfiles(Ref ref) {
  final profiles = ref.watch(profilesProvider).value ?? const [];
  return [...profiles.where((p) => p.signedIn)];
}

/// The signed-in profile the UI shows.
@Riverpod(keepAlive: true)
Profile? currentProfile(Ref ref) {
  final signedIn = ref.watch(signedInProfilesProvider);
  final current = ref.watch(appSettingsProvider).value?.currentProfile;
  return signedIn.where((p) => p.id == current).firstOrNull ??
      signedIn.firstOrNull;
}

@riverpod
Stream<Profile> profile(Ref ref, Id<Profiles> id) =>
    watchDb(ref, (db) => db.watchProfile(id));

/// Null until the profile is loaded.
@riverpod
NetworkSettings? networkSettings(Ref ref, SecretKey secretKey) => ref.watch(
  profilesProvider.select(
    (profiles) => profiles.value
        ?.where((p) => p.secretKey == secretKey)
        .firstOrNull
        ?.settings
        .network,
  ),
);
