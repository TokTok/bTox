import 'package:btox/models/connection_status.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/services/tox_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tox_session.g.dart';

/// Runs Tox for one profile.
@riverpod
ConnectionStatus toxSession(
  Ref ref,
  Id<Profiles> profileId,
  SecretKey secretKey,
  ToxAddressNospam nospam,
) {
  ref.watch(toxSyncProvider(profileId, secretKey, nospam));
  return ref.watch(selfConnectionStatusProvider(secretKey, nospam));
}

/// Runs Tox for every signed-in profile, so only the Tox owner may watch this.
final toxSessionsProvider = Provider<Map<Id<Profiles>, ConnectionStatus>>((
  ref,
) {
  return {
    for (final profile in ref.watch(signedInProfilesProvider))
      profile.id: ref.watch(
        toxSessionProvider(profile.id, profile.secretKey, profile.nospam),
      ),
  };
});
