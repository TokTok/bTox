import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:btox/models/profile_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// An HTTPS client that connects through [network]'s proxy, if any. The proxy
/// also resolves the host names, so no DNS query bypasses it.
http.Client proxyClient(NetworkSettings network) {
  final NetworkSettings(proxyHost: host, proxyPort: port) = network;
  return switch (network.proxyType) {
    ProxyType.none => http.Client(),
    ProxyType.http => IOClient(
      HttpClient()..findProxy = (_) => 'PROXY $host:$port',
    ),
    ProxyType.socks5 => IOClient(
      HttpClient()
        ..connectionFactory = (uri, _, _) async {
          if (uri.scheme != 'https') {
            throw UnsupportedError('Only HTTPS goes through a SOCKS5 proxy');
          }
          final socket = await SecureSocket.secure(
            await _socks5Connect(host, port, uri.host, uri.port),
            host: uri.host,
          );
          return ConnectionTask.fromSocket(
            Future.value(socket),
            socket.destroy,
          );
        },
    ),
  };
}

Future<bool> canReachProxy(NetworkSettings network) async {
  try {
    final socket = await Socket.connect(
      network.proxyHost,
      network.proxyPort,
      timeout: const Duration(seconds: 10),
    );
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  }
}

Future<Socket> _socks5Connect(
  String proxyHost,
  int proxyPort,
  String host,
  int port,
) async {
  final socket = await Socket.connect(proxyHost, proxyPort);
  final reader = _Reader(socket);
  try {
    socket.add([5, 1, 0]);
    final method = await reader.take(2);
    if (method[0] != 5 || method[1] != 0) {
      throw const SocketException('SOCKS5 proxy refused the connection');
    }
    final name = utf8.encode(host);
    socket.add([5, 1, 0, 3, name.length, ...name, port >> 8, port & 0xff]);
    final reply = await reader.take(4);
    if (reply[1] != 0) {
      throw SocketException('SOCKS5 connect failed with error ${reply[1]}');
    }
    final addressLength = switch (reply[3]) {
      1 => 4,
      4 => 16,
      _ => (await reader.take(1))[0],
    };
    await reader.take(addressLength + 2);
    // TLS takes over the socket from here.
    reader.pause();
    return socket;
  } catch (_) {
    socket.destroy();
    rethrow;
  }
}

final class _Reader {
  final _buffer = <int>[];
  late final StreamSubscription<Uint8List> _subscription;
  Completer<void>? _waiting;
  Object? _error;

  _Reader(Socket socket) {
    _subscription = socket.listen(
      (data) {
        _buffer.addAll(data);
        _wake();
      },
      onError: (Object e) {
        _error = e;
        _wake();
      },
      onDone: () {
        _error ??= const SocketException('SOCKS5 proxy closed the connection');
        _wake();
      },
    );
  }

  void _wake() {
    _waiting?.complete();
    _waiting = null;
  }

  Future<List<int>> take(int count) async {
    while (_buffer.length < count) {
      if (_error case final error?) {
        throw error;
      }
      await (_waiting = Completer()).future;
    }
    final bytes = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return bytes;
  }

  void pause() => _subscription.pause();
}
