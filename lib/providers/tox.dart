import 'dart:async';
import 'dart:math';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/api/toxcore/tox_options.dart';
import 'package:btox/ffi/tox_library.dart' as ffi;
import 'package:btox/ffi/toxcore.dart' as ffi;
import 'package:btox/logger.dart';
import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/profiles.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

  final tox = ffi.Toxcore(await ref.read(ffi.toxFfiProvider.future), options);
  ref.onDispose(tox.kill);
  tox.selfSetNospam(nospam.value);
  _logger.d('Tox instance created: ${tox.selfGetAddress()}');
  return tox;
}

@riverpod
Future<(SecretKey, PublicKey)> newKeyPair(Ref ref) async {
  // Offline, since only the key is needed.
  const options = ToxOptions(udpEnabled: false, localDiscoveryEnabled: false);
  final tox = ffi.Toxcore(await ref.read(ffi.toxFfiProvider.future), options);
  try {
    return (tox.selfGetSecretKey(), tox.selfGetPublicKey());
  } finally {
    tox.kill();
  }
}

/// Bootstraps [tox] and gives [handle] its events in order, until Tox is
/// killed or [ref] is disposed.
void runTox(
  Ref ref,
  Tox tox,
  NetworkSettings network,
  void Function(Event) handle,
) {
  var disposed = false;
  ref.onDispose(() => disposed = true);

  ref.listen(bootstrapNodesProvider(network), (_, next) {
    if (next.value case final list?) {
      _bootstrap(tox, list.nodes, network);
    }
  }, fireImmediately: true);

  Future<void> iterate() async {
    while (!disposed && tox.isAlive) {
      List<Event> events;
      try {
        events = tox.iterate();
      } on Object catch (e, stackTrace) {
        // Such as a friend's event this can't read: the round's events are
        // lost, but Tox goes on.
        _logger.e('Failed to read Tox events: $e', stackTrace);
        events = const [];
      }
      for (final event in events) {
        if (event is ToxEventDhtNodesResponse) {
          continue;
        }
        _logger.d('Tox event: $event');
        try {
          handle(event);
        } on Object catch (e, stackTrace) {
          _logger.e('Failed to handle $event: $e', stackTrace);
        }
      }
      await Future.delayed(Duration(milliseconds: tox.iterationInterval()));
    }
  }

  _logger.unawaited('run Tox', iterate());
}

// How many nodes Tox starts from.
const _bootstrapNodes = 8;

// What the node list says for an address a node doesn't have.
const _noAddress = {'', '-', 'NONE'};

/// The nodes to start from: those the list last reached first, and in a
/// different order each time, so a few that are down can't take every place.
@visibleForTesting
List<BootstrapNode> bootstrapNodesToUse(
  List<BootstrapNode> nodes,
  NetworkSettings network, [
  Random? random,
]) {
  // Toxcore would resolve hostnames itself, outside the proxy.
  final usable =
      nodes
          .where(
            (node) =>
                node.tcpPorts.isNotEmpty &&
                !_noAddress.contains(node.ipv4) &&
                (!network.usesProxy || _ipv4.hasMatch(node.ipv4)),
          )
          .toList()
        ..shuffle(random);
  return [
    ...usable.where((node) => node.statusTcp),
    ...usable.where((node) => !node.statusTcp),
  ].take(_bootstrapNodes).toList(growable: false);
}

void _bootstrap(Tox tox, List<BootstrapNode> nodes, NetworkSettings network) {
  final selected = bootstrapNodesToUse(nodes, network);
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
