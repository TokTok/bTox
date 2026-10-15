import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart' show Profiles;
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/map_tile.dart';
import 'package:btox/providers/profiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;

void main() {
  test("a chat's map tiles go through its profile's proxy, and none come "
      'before that is known', () async {
    const proxy = NetworkSettings(proxyType: ProxyType.socks5);
    final used = <NetworkSettings>[];
    final container = ProviderContainer(
      overrides: [
        profileProvider(const Id(2)).overrideWith(
          (ref) => Stream.value(
            Profile(
              id: const Id(2),
              signedIn: true,
              settings: ProfileSettings(
                nickname: 'Bob',
                statusMessage: '',
                network: proxy,
              ),
              secretKey: SecretKey(Uint8List(32)),
              publicKey: PublicKey(Uint8List(32)),
              nospam: ToxAddressNospam(0),
            ),
          ),
        ),
        // Still loading.
        profileProvider(const Id(3))
            .overrideWith((ref) => const Stream.empty()),
        httpClientProvider.overrideWith((ref, network) {
          used.add(network);
          return http.Client();
        }),
      ],
    );
    addTearDown(container.dispose);
    for (final id in const [Id<Profiles>(2), Id<Profiles>(3)]) {
      container.listen(mapTileProvider(id), (_, _) {});
    }
    await Future<void>.delayed(Duration.zero);

    expect(container.read(mapTileProvider(const Id(2))), isNotNull);
    expect(container.read(mapTileProvider(const Id(3))), isNull);
    expect(used, [proxy]);
  });
}
