import 'dart:convert';

import 'package:btox/logger.dart';
import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/proxy_client.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bootstrap_nodes.g.dart';

const _logger = Logger(['BootstrapNodes']);

/// Nodes from nodes.tox.chat that accept TCP, for when bTox has no fetched
/// list.
final fallbackBootstrapNodes = BootstrapNodeList(
  nodes: [
    for (final (ip, port, key) in const [
      (
        '144.217.167.73',
        33445,
        '7E5668E0EE09E19F320AD47902419331FFEE147BB3606769CFBE921A2A2FD34C',
      ),
      (
        '49.12.229.145',
        33445,
        'B3E5FA80DC8EBD1149AD2AB35ED8B85BD546DEDE261CA593234C619249419506',
      ),
      (
        '49.13.50.193',
        33445,
        '70EA214FDE161E7432530605213F18F7427DC773E276B3E317A07531F548545F',
      ),
      (
        '172.105.109.31',
        33445,
        'D46E97CF995DC1820B92B7D899E152A217D36ABE22730FEA4B6BF1BFC06C617C',
      ),
      (
        '144.172.88.203',
        33445,
        '2016A0F2797EE3A8B004BA623F11AAFC8146F1B8F45107232A1A1AECCE856674',
      ),
      (
        '172.104.215.182',
        33445,
        'DA2BD927E01CD05EBCC2574EBE5BEBB10FF59AE0B2105A7D1E2B40E49BB20239',
      ),
      (
        '114.35.245.150',
        33445,
        '3F0A45A268367C1BEA652F258C85F4A66DA76BCAA667A49E770BCC4917AB6A25',
      ),
      (
        '51.79.254.78',
        33445,
        'F4FC9398B7167668ED2BCF85634E04D4CDCDD2F95DA5F305BD234888B6E6A771',
      ),
      (
        '188.214.122.30',
        33445,
        '2A9F7A620581D5D1B09B004624559211C5ED3D1D712E8066ACDB0896A7335705',
      ),
      (
        '165.227.194.41',
        443,
        '5D57B95EE4A7F37BA031DAD0CBD9510A9C96FFE09C1CE24A9C33746F39817D6E',
      ),
      (
        '141.95.53.16',
        33445,
        'DCD342A0D5E2AA8E35C2BD2C7988F906EEB631B35100170A7F30E77D7F596442',
      ),
      (
        '86.107.187.54',
        33445,
        '2C0F90965134C7BEFAFE72B077A19221628D7045BB51C1165A2C75CDB2B32634',
      ),
      (
        '119.59.101.63',
        33445,
        '197F746696062FA3BD07BB3BC0656ABD6692B4DAA27DACF0F474754F2B09B060',
      ),
      (
        '167.17.40.142',
        33445,
        'E84453123B44A47120FFB469CBCDEEF078D3785D7AD7F6C5B2351CB5DDE2C54C',
      ),
      (
        '172.86.77.39',
        33445,
        'AFFD3FAD3460E62A894E439534B27E5A5DCFE379C1C0FB78DEF1B150A87E900F',
      ),
      (
        '145.239.1.105',
        33445,
        '1658A9A64046C20F48FB2A47E56045233AB0AC0706974FC5904F9E74F452D908',
      ),
      (
        '5.19.249.240',
        38296,
        'DA98A4C0CD7473A133E115FEA2EBDAEEA2EF4F79FD69325FC070DA4DE4BA3238',
      ),
    ])
      BootstrapNode(
        ipv4: ip,
        port: port,
        tcpPorts: [port],
        publicKey: PublicKey.fromJson(key),
      ),
  ],
);

@Riverpod(keepAlive: true)
http.Client httpClient(Ref ref, NetworkSettings network) {
  final client = proxyClient(network);
  ref.onDispose(client.close);
  return client;
}

/// The cached (or built-in) nodes right away, then freshly fetched ones. A
/// list without nodes, as nodes.tox.chat serves when its scan finds none,
/// never takes the place of one with nodes.
@Riverpod(keepAlive: true)
Stream<BootstrapNodeList> bootstrapNodes(
  Ref ref,
  NetworkSettings network,
) async* {
  final db = await ref.watch(databaseProvider.future);
  yield switch (await db.getCachedBootstrapNodes()) {
    // Older versions cached one.
    final cached? when cached.nodes.isNotEmpty => cached,
    _ => fallbackBootstrapNodes,
  };

  final client = ref.watch(httpClientProvider(network));
  try {
    final response = await client
        .get(Uri.parse('https://nodes.tox.chat/json'))
        .timeout(const Duration(minutes: 1));
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}');
    }
    final nodes = BootstrapNodeList.fromJson(jsonDecode(response.body));
    if (nodes.nodes.isEmpty) {
      throw const FormatException('The list has no nodes');
    }
    await db.cacheBootstrapNodes(nodes);
    yield nodes;
  } catch (e) {
    _logger.w('Failed to fetch bootstrap nodes: $e');
  }
}
