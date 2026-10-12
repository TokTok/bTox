import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/api/toxcore/tox_options.dart';
import 'package:btox/ffi/tox_constants.dart' as ffi;
import 'package:btox/ffi/tox_library.dart' as ffi;
import 'package:btox/ffi/toxcore.dart' as ffi;
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tox.g.dart';

const _logger = Logger(['ToxProvider']);

@riverpod
Future<Tox> tox(Ref ref, SecretKey secretKey, ToxAddressNospam nospam) async {
  _logger.d('Creating Tox instance with nospam $nospam');

  final options = ToxOptions(
    savedata: secretKey.bytes,
    savedataType: ffi.Tox_Savedata_Type.TOX_SAVEDATA_TYPE_SECRET_KEY,
  );

  // ignore: argument_type_not_assignable
  final tox = ffi.Toxcore(await ref.read(ffi.toxFfiProvider.future), options);
  ref.onDispose(tox.kill);
  tox.nospam = nospam;
  _logger.d('Tox instance created: ${tox.address}');
  return tox;
}

@riverpod
Future<ToxConstants> toxConstants(Ref ref) async {
  return ffi.toxcoreConstants(await ref.read(ffi.toxFfiProvider.future));
}

@riverpod
class ToxEvents extends _$ToxEvents {
  @override
  Stream<Event> build(SecretKey secretKey, ToxAddressNospam nospam) async* {
    bool disposed = false;
    ref.onDispose(() => disposed = true);

    final tox = await ref.watch(toxProvider(secretKey, nospam).future);

    final nodes = (await ref.watch(bootstrapNodesProvider.future)).nodes
        .where((node) => node.tcpPorts.isNotEmpty)
        .toList(growable: false);
    final selectedNodes = nodes.take(8);
    _logger.d(
      'Got ${nodes.length} bootstrap nodes; '
      'using ${selectedNodes.length}...',
    );
    try {
      for (final node in selectedNodes) {
        tox.bootstrap(node.ipv4, node.port, node.publicKey);
        tox.addTcpRelay(node.ipv4, node.tcpPorts.first, node.publicKey);
      }
    } on ApiException catch (_) {
      _logger.e('Failed to bootstrap');
    }

    while (!disposed && tox.isAlive) {
      for (final event in tox.iterate()) {
        if (event is ToxEventDhtNodesResponse) {
          continue;
        }
        _logger.d('Tox event: $event');
        yield event;
      }
      await Future.delayed(Duration(milliseconds: tox.iterationInterval));
    }
  }

  // Equal events, e.g. the same message twice, are still separate events.
  @override
  bool updateShouldNotify(AsyncValue<Event> previous, AsyncValue<Event> next) =>
      true;
}

@riverpod
class SelfConnectionStatus extends _$SelfConnectionStatus {
  @override
  ffi.Tox_Connection build(SecretKey secretKey, ToxAddressNospam nospam) {
    ref.listen(toxEventsProvider(secretKey, nospam), (_, next) {
      if (next.hasError) {
        _logger.e('Tox events failed: ${next.error}');
      }
      if (next.value case ToxEventSelfConnectionStatus(
        :final connectionStatus,
      )) {
        state = connectionStatus;
      }
    });
    return ffi.Tox_Connection.TOX_CONNECTION_NONE;
  }
}
