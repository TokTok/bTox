import 'package:btox/db/database.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final profilesProvider = StreamProvider<List<Profile>>(
  (ref) => watchDb(ref, (db) => db.watchProfiles()),
);

final appSettingsProvider = StreamProvider<AppSetting>(
  (ref) => watchDb(ref, (db) => db.watchAppSettings()),
);

final signedInProfilesProvider = Provider<List<Profile>>((ref) {
  final profiles = ref.watch(profilesProvider).value ?? const [];
  return [...profiles.where((p) => p.signedIn)];
});

/// The signed-in profile the UI shows.
final currentProfileProvider = Provider<Profile?>((ref) {
  final signedIn = ref.watch(signedInProfilesProvider);
  final current = ref.watch(appSettingsProvider).value?.currentProfile;
  return signedIn.where((p) => p.id == current).firstOrNull ??
      signedIn.firstOrNull;
});

final profileProvider = StreamProvider.family<Profile, Id<Profiles>>(
  (ref, id) => watchDb(ref, (db) => db.watchProfile(id)),
);

/// Null until the profile is loaded.
final networkSettingsProvider = Provider.family<NetworkSettings?, SecretKey>(
  (ref, secretKey) => ref.watch(
    profilesProvider.select(
      (profiles) => profiles.value
          ?.where((p) => p.secretKey == secretKey)
          .firstOrNull
          ?.settings
          .network,
    ),
  ),
);
