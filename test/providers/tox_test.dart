// The analyzer resolves ToxLibrary's conditional export to the stub.
// ignore_for_file: argument_type_not_assignable

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart' as gen;
import 'package:btox/ffi/tox_library.ffi.dart' as tox_lib;
import 'package:btox/ffi/toxcore.dart' as ffi;
import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/connection_status.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/providers/tox.dart';
import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_bootstrap_nodes.dart';
import '../mocks/fake_toxcore.dart';

void main() {
  test('tox restarts with the profile network settings', () async {
    final db = Database(NativeDatabase.memory());
    final secretKey = SecretKey(Uint8List.fromList(List.filled(32, 1)));
    final nospam = ToxAddressNospam(0);
    final id = await db.addProfile(
      ProfilesCompanion.insert(
        settings: const ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: secretKey,
        publicKey: PublicKey(Uint8List(32)),
        nospam: nospam,
      ),
    );
    final lib = tox_lib.ToxLibrary(
      malloc,
      gen.ToxFfi(DynamicLibrary.open('linux/vendored/libtoxcore.so')),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        tox_lib.toxFfiProvider.overrideWith((ref) => lib),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final provider = toxProvider(secretKey, nospam);
    container.listen(provider, (_, _) {});

    Future<AsyncValue<Tox>> restart(NetworkSettings network) async {
      final previous = container.read(provider).value;
      await db.updateProfileSettings(
        id,
        ProfileSettings(nickname: 'Me', statusMessage: '', network: network),
      );
      for (var i = 0; i < 100; i++) {
        await Future.delayed(const Duration(milliseconds: 10));
        final state = container.read(provider);
        if (state.hasError ||
            (!state.isLoading && !identical(state.value, previous))) {
          return state;
        }
      }
      fail('Tox did not restart');
    }

    await container.read(provider.future);
    final first = await restart(
      const NetworkSettings(udpEnabled: false, localDiscoveryEnabled: false),
    );
    expect(first.requireValue.isAlive, isTrue);

    final second = await restart(
      const NetworkSettings(proxyType: ProxyType.socks5, proxyPort: 0),
    );
    expect(first.requireValue.isAlive, isFalse);
    expect(second.error, isA<ApiException>());
  });

  test('toxEvents yields events from tox.iterate()', () async {
    final fakeTox = FakeToxcore();
    final secretKey = SecretKey(Uint8List(32));
    final nospam = ToxAddressNospam(0);

    final container = ProviderContainer(
      overrides: [
        bootstrapNodesProvider.overrideWith(
          (ref, network) => Stream.value(
            BootstrapNodeList(
              nodes: [
                BootstrapNode(
                  ipv4: '127.0.0.1',
                  port: 33445,
                  publicKey: PublicKey(Uint8List(32)),
                  tcpPorts: [33446],
                ),
              ],
            ),
          ),
        ),
        toxProvider(secretKey, nospam).overrideWith((ref) => fakeTox),
        networkSettingsProvider(secretKey)
            .overrideWithValue(const NetworkSettings()),
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
          (ref, network) => Stream.value(
            BootstrapNodeList(
              nodes: [
                BootstrapNode(
                  ipv4: '127.0.0.1',
                  port: 33445,
                  publicKey: PublicKey(Uint8List(32)),
                  tcpPorts: [33446],
                ),
              ],
            ),
          ),
        ),
        toxProvider(secretKey, nospam).overrideWith((ref) => fakeTox),
        networkSettingsProvider(secretKey)
            .overrideWithValue(const NetworkSettings()),
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
          (ref, network) => Stream.value(const BootstrapNodeList(nodes: [])),
        ),
        toxProvider(secretKey, nospam).overrideWith((ref) => fakeTox),
        networkSettingsProvider(secretKey)
            .overrideWithValue(const NetworkSettings()),
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
        ip: '127.0.0.1',
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

  group('proxy problems', () {
    final secretKey = SecretKey(Uint8List(32));
    final nospam = ToxAddressNospam(0);

    Future<List<ConnectionStatus>> watch(
      List<Override> overrides,
      bool Function(List<ConnectionStatus>) until,
    ) async {
      final container = ProviderContainer(
        overrides: [
          bootstrapNodesProvider.overrideWith(fakeBootstrapNodesProvider),
          proxyCheckDelayProvider.overrideWithValue(Duration.zero),
          ...overrides,
        ],
      );
      addTearDown(container.dispose);
      final statuses = <ConnectionStatus>[];
      container.listen(
        selfConnectionStatusProvider(secretKey, nospam),
        (_, status) => statuses.add(status),
        fireImmediately: true,
      );
      for (var i = 0; i < 200 && !until(statuses); i++) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      return statuses;
    }

    test('an unreachable proxy shows until Tox connects', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      final fakeTox = FakeToxcore();
      addTearDown(fakeTox.kill);

      final statuses = await watch([
        toxProvider(secretKey, nospam).overrideWith((ref) => fakeTox),
        networkSettingsProvider(secretKey).overrideWithValue(
          NetworkSettings(proxyType: ProxyType.socks5, proxyPort: port),
        ),
      ], (statuses) => statuses.last.proxyProblem != null);
      expect(statuses.last.proxyProblem, ProxyProblem.unreachable);
      expect(
        connectionStatusText(statuses.last),
        "Can't reach proxy at 127.0.0.1:$port",
      );

      fakeTox.pushEvent(
        ToxEventSelfConnectionStatus(
          connectionStatus: ffi.Tox_Connection.TOX_CONNECTION_TCP,
        ),
      );
      for (var i = 0; i < 100 && !statuses.last.online; i++) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      expect(statuses.last.proxyProblem, isNull);
      expect(statuses.last.online, isTrue);
    });

    test('a proxy toxcore rejects shows as rejected', () async {
      final statuses = await watch([
        toxProvider(secretKey, nospam).overrideWith(
          (ref) => throw const ApiException(
            ffi.Tox_Err_New.TOX_ERR_NEW_PROXY_BAD_HOST,
          ),
        ),
        networkSettingsProvider(secretKey).overrideWithValue(
          const NetworkSettings(
            proxyType: ProxyType.socks5,
            proxyHost: 'no.such.host',
          ),
        ),
      ], (statuses) => statuses.last.proxyProblem == ProxyProblem.rejected);
      expect(statuses.last.proxyProblem, ProxyProblem.rejected);
      expect(
        connectionStatusText(statuses.last),
        "Can't use proxy no.such.host:9050",
      );
    });
  });
}
