import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:btox/db/database.dart';
import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/proxy_client.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _nodesJson = '''
{
  "nodes": [
    {
      "ipv4": "127.0.0.1",
      "port": 33445,
      "public_key": "0000000000000000000000000000000000000000000000000000000000000000",
      "tcp_ports": [33446],
      "ipv6": "",
      "maintainer": "test",
      "location": "test",
      "status_udp": true,
      "status_tcp": true,
      "version": "1.0",
      "motd": "test",
      "last_ping": 123456789
    }
  ],
  "last_refresh": 123,
  "last_scan": 456
}
''';

/// Accepts one connection and returns its first request, after answering the
/// SOCKS5 greeting if [socks5].
Future<(int, Future<List<int>>)> _fakeProxy({required bool socks5}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final request = server.first.then((client) async {
    final received = <int>[];
    final done = Completer<List<int>>();
    client.listen((data) {
      received.addAll(data);
      if (socks5 && received.length == 3) {
        client.add([5, 0]);
        received.clear();
      } else if (!done.isCompleted &&
          (socks5
              ? received.length > 4 && received.length >= 7 + received[4]
              : utf8.decode(received).contains('\r\n'))) {
        done.complete(received);
      }
    });
    final bytes = await done.future;
    client.destroy();
    await server.close();
    return bytes;
  });
  return (server.port, request);
}

void main() {
  test('bootstrapNodes starts from the cache and refreshes it', () async {
    final db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    const network = NetworkSettings();

    Future<List<BootstrapNodeList>> run(http.Client client) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((ref) => db),
          httpClientProvider.overrideWith((ref, network) => client),
        ],
      );
      addTearDown(container.dispose);
      final lists = <BootstrapNodeList>[];
      final done = Completer<void>();
      container.listen(bootstrapNodesProvider(network), (_, next) {
        if (next.value case final list?) {
          lists.add(list);
        }
        if (lists.length == 2) {
          done.complete();
        }
      }, fireImmediately: true);
      await done.future.timeout(const Duration(seconds: 1), onTimeout: () {});
      return lists;
    }

    final first = await run(
      MockClient((_) async => http.Response(_nodesJson, 200)),
    );
    expect(first.first, fallbackBootstrapNodes);
    expect(first.last.nodes.single.ipv4, '127.0.0.1');

    final offline = await run(MockClient((_) async => throw 'offline'));
    expect(offline.single, first.last);
  });

  test('a SOCKS5 proxy resolves the host name', () async {
    final (port, request) = await _fakeProxy(socks5: true);
    final client = proxyClient(
      NetworkSettings(proxyType: ProxyType.socks5, proxyPort: port),
    );
    addTearDown(client.close);
    unawaited(
      client
          .get(Uri.parse('https://nodes.tox.chat/json'))
          .catchError((_) => http.Response('', 500)),
    );

    final name = utf8.encode('nodes.tox.chat');
    expect(await request, [5, 1, 0, 3, name.length, ...name, 1, 187]);
  });

  test('an HTTP proxy tunnels to the host name', () async {
    final (port, request) = await _fakeProxy(socks5: false);
    final client = proxyClient(
      NetworkSettings(proxyType: ProxyType.http, proxyPort: port),
    );
    addTearDown(client.close);
    unawaited(
      client
          .get(Uri.parse('https://nodes.tox.chat/json'))
          .catchError((_) => http.Response('', 500)),
    );

    expect(
      utf8.decode(await request),
      startsWith('CONNECT nodes.tox.chat:443 '),
    );
  });
}
