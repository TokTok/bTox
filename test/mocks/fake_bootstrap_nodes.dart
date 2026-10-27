import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:riverpod/riverpod.dart';

Stream<BootstrapNodeList> fakeBootstrapNodesProvider(
  Ref ref,
  NetworkSettings network,
) => Stream.value(
  BootstrapNodeList(
    nodes: [
      BootstrapNode(
        ipv4: '127.0.0.1',
        port: 33445,
        publicKey: PublicKey.fromJson(
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        ),
        tcpPorts: [33446],
      ),
    ],
  ),
);
