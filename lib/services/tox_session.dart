import 'dart:async';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/ffi/toxcore.dart' as ffi;
import 'package:btox/models/connection_status.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/providers/proxy_client.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/services/tox_sync.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tox_session.g.dart';

/// Runs Tox for one profile.
@riverpod
ConnectionStatus toxSession(
  Ref ref,
  Id<Profiles> profileId,
  SecretKey secretKey,
  ToxAddressNospam nospam,
) => ref.watch(selfConnectionStatusProvider(profileId, secretKey, nospam));

/// Runs Tox for every signed-in profile, so only the Tox owner may watch this.
@riverpod
Map<Id<Profiles>, ConnectionStatus> toxSessions(Ref ref) => {
  for (final profile in ref.watch(signedInProfilesProvider))
    profile.id: ref.watch(
      toxSessionProvider(profile.id, profile.secretKey, profile.nospam),
    ),
};

/// How long to wait for a connection before checking the proxy.
@Riverpod(keepAlive: true)
Duration proxyCheckDelay(Ref ref) => const Duration(seconds: 20);

const _proxyErrors = {
  ffi.Tox_Err_New.TOX_ERR_NEW_PROXY_BAD_TYPE,
  ffi.Tox_Err_New.TOX_ERR_NEW_PROXY_BAD_HOST,
  ffi.Tox_Err_New.TOX_ERR_NEW_PROXY_BAD_PORT,
  ffi.Tox_Err_New.TOX_ERR_NEW_PROXY_NOT_FOUND,
};

@riverpod
class SelfConnectionStatus extends _$SelfConnectionStatus {
  Timer? _proxyCheck;
  ToxSync? _sync;
  StreamSubscription<ffi.Tox_Connection>? _changes;

  @override
  ConnectionStatus build(
    Id<Profiles> profileId,
    SecretKey secretKey,
    ToxAddressNospam nospam,
  ) {
    final network = ref.watch(networkSettingsProvider(secretKey));
    final delay = ref.watch(proxyCheckDelayProvider);
    final usesProxy = network != null && network.usesProxy;
    ref.onDispose(() {
      _proxyCheck?.cancel();
      _changes?.cancel();
    });

    // Toxcore doesn't tell us when it can't reach the proxy.
    void checkProxyLater() {
      _proxyCheck?.cancel();
      if (usesProxy) {
        _proxyCheck = Timer(delay, () async {
          final reachable = await canReachProxy(network);
          if (ref.mounted &&
              !reachable &&
              !state.online &&
              state.proxyProblem == null) {
            state = state.copyWith(proxyProblem: ProxyProblem.unreachable);
          }
        });
      }
    }

    void connected(ffi.Tox_Connection connection) {
      state = state.copyWith(connection: connection, proxyProblem: null);
      if (!state.online) {
        checkProxyLater();
      }
    }

    // The connection of the Tox that [sync] runs, from now on.
    ffi.Tox_Connection follow(ToxSync sync) {
      _sync = sync;
      _changes?.cancel();
      _changes = sync.connectionChanges.listen(connected);
      return sync.connection;
    }

    // Failing to start Tox is retried, so it never reaches the sync.
    ref.listen(toxProvider(secretKey, nospam), (_, next) {
      if (next.error case ApiException(:final error)
          when _proxyErrors.contains(error)) {
        state = state.copyWith(proxyProblem: ProxyProblem.rejected);
      }
    });
    final sync = ref.listen(toxSyncProvider(profileId, secretKey, nospam), (
      _,
      next,
    ) {
      if (next case AsyncData(value: final sync) when sync != _sync) {
        connected(follow(sync));
      }
    });

    checkProxyLater();
    return ConnectionStatus(
      connection: switch (sync.read()) {
        AsyncData(value: final sync) => follow(sync),
        _ => ffi.Tox_Connection.TOX_CONNECTION_NONE,
      },
      proxy: usesProxy ? '${network.proxyHost}:${network.proxyPort}' : '',
    );
  }
}
