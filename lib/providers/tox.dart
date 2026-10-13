import 'dart:async';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/api/toxcore/tox_options.dart';
import 'package:btox/ffi/tox_library.dart' as ffi;
import 'package:btox/ffi/toxcore.dart' as ffi;
import 'package:btox/logger.dart';
import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/connection_status.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/providers/proxy_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tox.g.dart';

const _logger = Logger(['ToxProvider']);

final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

@riverpod
Future<Tox> tox(Ref ref, SecretKey secretKey, ToxAddressNospam nospam) async {
  final network = ref.watch(networkSettingsProvider(secretKey));
  if (network == null) {
    // Never start without the profile's proxy settings. This provider runs
    // again once they're known.
    return Completer<Tox>().future;
  }

  _logger.d('Creating Tox instance with nospam $nospam');
  // Toxcore only sends TCP through the proxy.
  final options = ToxOptions(
    ipv6Enabled: network.ipv6Enabled,
    udpEnabled: network.udpEnabled && !network.usesProxy,
    localDiscoveryEnabled: network.localDiscoveryEnabled && !network.usesProxy,
    proxyType: switch (network.proxyType) {
      ProxyType.none => ffi.Tox_Proxy_Type.TOX_PROXY_TYPE_NONE,
      ProxyType.http => ffi.Tox_Proxy_Type.TOX_PROXY_TYPE_HTTP,
      ProxyType.socks5 => ffi.Tox_Proxy_Type.TOX_PROXY_TYPE_SOCKS5,
    },
    proxyHost: network.proxyHost,
    proxyPort: network.proxyPort,
    savedata: secretKey.bytes,
    savedataType: ffi.Tox_Savedata_Type.TOX_SAVEDATA_TYPE_SECRET_KEY,
  );

  // ignore: argument_type_not_assignable
  final tox = ffi.Toxcore(await ref.read(ffi.toxFfiProvider.future), options);
  ref.onDispose(tox.kill);
  tox.selfSetNospam(nospam.value);
  _logger.d('Tox instance created: ${tox.selfGetAddress()}');
  return tox;
}

@riverpod
class ToxEvents extends _$ToxEvents {
  @override
  Stream<Event> build(SecretKey secretKey, ToxAddressNospam nospam) async* {
    bool disposed = false;
    ref.onDispose(() => disposed = true);

    // Runs again once Tox has started.
    final toxState = ref.watch(toxProvider(secretKey, nospam));
    if (toxState is! AsyncData<Tox>) {
      return;
    }
    final tox = toxState.value;
    final network = ref.watch(networkSettingsProvider(secretKey))!;

    ref.listen(bootstrapNodesProvider(network), (_, next) {
      if (next.value case final list?) {
        _bootstrap(tox, list.nodes, network);
      }
    }, fireImmediately: true);

    while (!disposed && tox.isAlive) {
      for (final event in tox.iterate()) {
        if (event is ToxEventDhtNodesResponse) {
          continue;
        }
        _logger.d('Tox event: $event');
        yield event;
      }
      await Future.delayed(Duration(milliseconds: tox.iterationInterval()));
    }
  }

  void _bootstrap(Tox tox, List<BootstrapNode> nodes, NetworkSettings network) {
    // Toxcore would resolve hostnames itself, outside the proxy.
    final selected = nodes
        .where(
          (node) =>
              node.tcpPorts.isNotEmpty &&
              (!network.usesProxy || _ipv4.hasMatch(node.ipv4)),
        )
        .take(8)
        .toList(growable: false);
    _logger.d('Got ${nodes.length} bootstrap nodes; using ${selected.length}');
    for (final node in selected) {
      try {
        tox.bootstrap(node.ipv4, node.port, node.publicKey);
        tox.addTcpRelay(node.ipv4, node.tcpPorts.first, node.publicKey);
      } on ApiException catch (e) {
        _logger.w('Failed to bootstrap from ${node.ipv4}: $e');
      }
    }
  }

  // Equal events, e.g. the same message twice, are still separate events.
  @override
  bool updateShouldNotify(AsyncValue<Event> previous, AsyncValue<Event> next) =>
      true;
}

/// How long to wait for a connection before checking the proxy.
final proxyCheckDelayProvider = Provider((_) => const Duration(seconds: 20));

const _proxyErrors = {
  ffi.Tox_Err_New.TOX_ERR_NEW_PROXY_BAD_TYPE,
  ffi.Tox_Err_New.TOX_ERR_NEW_PROXY_BAD_HOST,
  ffi.Tox_Err_New.TOX_ERR_NEW_PROXY_BAD_PORT,
  ffi.Tox_Err_New.TOX_ERR_NEW_PROXY_NOT_FOUND,
};

@riverpod
class SelfConnectionStatus extends _$SelfConnectionStatus {
  Timer? _proxyCheck;

  @override
  ConnectionStatus build(SecretKey secretKey, ToxAddressNospam nospam) {
    final network = ref.watch(networkSettingsProvider(secretKey));
    final delay = ref.watch(proxyCheckDelayProvider);
    final usesProxy = network != null && network.usesProxy;
    ref.onDispose(() => _proxyCheck?.cancel());

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

    // Failing to start Tox is retried, so it never reaches toxEvents.
    ref.listen(toxProvider(secretKey, nospam), (_, next) {
      if (next.error case ApiException(:final error)
          when _proxyErrors.contains(error)) {
        state = state.copyWith(proxyProblem: ProxyProblem.rejected);
      }
    });
    ref.listen(toxEventsProvider(secretKey, nospam), (_, next) {
      if (next.error case final error?) {
        _logger.e('Tox events failed: $error');
      } else if (next.value case ToxEventSelfConnectionStatus(
        :final connectionStatus,
      )) {
        state = state.copyWith(
          connection: connectionStatus,
          proxyProblem: null,
        );
        if (!state.online) {
          checkProxyLater();
        }
      }
    });

    checkProxyLater();
    return ConnectionStatus(
      connection: ffi.Tox_Connection.TOX_CONNECTION_NONE,
      proxy: usesProxy ? '${network.proxyHost}:${network.proxyPort}' : '',
    );
  }
}
