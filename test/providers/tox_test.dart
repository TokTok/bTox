import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/ffi/toxcore.dart' as ffi;
import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/tox.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_toxcore.dart';

void main() {
  test('toxEvents yields events from tox.iterate()', () async {
    final fakeTox = FakeToxcore();
    final secretKey = SecretKey(Uint8List(32));
    final nospam = ToxAddressNospam(0);

    final container = ProviderContainer(
      overrides: [
        bootstrapNodesProvider.overrideWith(
          (ref) => BootstrapNodeList(
            nodes: [
              BootstrapNode(
                ipv4: '127.0.0.1',
                port: 33445,
                publicKey: PublicKey(Uint8List(32)),
                tcpPorts: [33446],
                ipv6: '',
                maintainer: '',
                location: '',
                statusUdp: true,
                statusTcp: true,
                version: '',
                motd: '',
                lastPing: 0,
              ),
            ],
            lastRefresh: 0,
            lastScan: 0,
          ),
        ),
        toxProvider(secretKey, nospam).overrideWith((ref) => fakeTox),
      ],
    );

    final events = <Event>[];
    final subscription = container.listen(
      toxEventsProvider(secretKey, nospam),
      (previous, next) {
        next.whenData((event) => events.add(event));
      },
      fireImmediately: true,
    );

    final event = ToxEventSelfConnectionStatus(
      connectionStatus: ffi.Tox_Connection.TOX_CONNECTION_UDP,
    );
    fakeTox.pushEvent(event);

    // Give it a bit of time to iterate
    await Future.delayed(const Duration(milliseconds: 50));

    expect(events, contains(event));

    subscription.close();
    fakeTox.kill();
  });

  test('toxEvents handles bootstrap failure gracefully', () async {
    final fakeTox = FakeToxcore()..throwOnBootstrap = true;
    final secretKey = SecretKey(Uint8List(32));
    final nospam = ToxAddressNospam(0);

    final container = ProviderContainer(
      overrides: [
        bootstrapNodesProvider.overrideWith(
          (ref) => BootstrapNodeList(
            nodes: [
              BootstrapNode(
                ipv4: '127.0.0.1',
                port: 33445,
                publicKey: PublicKey(Uint8List(32)),
                tcpPorts: [33446],
                ipv6: '',
                maintainer: '',
                location: '',
                statusUdp: true,
                statusTcp: true,
                version: '',
                motd: '',
                lastPing: 0,
              ),
            ],
            lastRefresh: 0,
            lastScan: 0,
          ),
        ),
        toxProvider(secretKey, nospam).overrideWith((ref) => fakeTox),
      ],
    );

    final events = <Event>[];
    final subscription = container.listen(
      toxEventsProvider(secretKey, nospam),
      (previous, next) {
        next.whenData((event) => events.add(event));
      },
    );

    fakeTox.kill();
    await Future.delayed(const Duration(milliseconds: 50));
    subscription.close();
  });

  test('toxEvents ignores ToxEventDhtNodesResponse', () async {
    final fakeTox = FakeToxcore();
    final secretKey = SecretKey(Uint8List(32));
    final nospam = ToxAddressNospam(0);

    final container = ProviderContainer(
      overrides: [
        bootstrapNodesProvider.overrideWith(
          (ref) => BootstrapNodeList(nodes: [], lastRefresh: 0, lastScan: 0),
        ),
        toxProvider(secretKey, nospam).overrideWith((ref) => fakeTox),
      ],
    );

    final events = <Event>[];
    final subscription = container.listen(
      toxEventsProvider(secretKey, nospam),
      (previous, next) {
        next.whenData((event) => events.add(event));
      },
    );

    fakeTox.pushEvent(
      ToxEventDhtNodesResponse(
        publicKey: PublicKey(Uint8List(32)),
        ip: Uint8List.fromList([127, 0, 0, 1]),
        port: 33445,
      ),
    );

    final event = ToxEventSelfConnectionStatus(
      connectionStatus: ffi.Tox_Connection.TOX_CONNECTION_UDP,
    );
    fakeTox.pushEvent(event);

    await Future.delayed(const Duration(milliseconds: 50));

    expect(events, isNot(contains(isA<ToxEventDhtNodesResponse>())));
    expect(events, contains(event));

    subscription.close();
    fakeTox.kill();
  });
}
