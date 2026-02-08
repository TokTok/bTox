import 'package:btox/models/crypto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'bootstrap_nodes.freezed.dart';
part 'bootstrap_nodes.g.dart';

@freezed
abstract class BootstrapNode with _$BootstrapNode {
  // ignore: invalid_annotation_target
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory BootstrapNode({
    required String ipv4,
    required String ipv6,
    required int port,
    required List<int> tcpPorts,
    required PublicKey publicKey,
    required String maintainer,
    required String location,
    required bool statusUdp,
    required bool statusTcp,
    required String version,
    required String motd,
    required int lastPing,
  }) = _BootstrapNode;
  factory BootstrapNode.fromJson(Map<String, dynamic> json) =>
      _$BootstrapNodeFromJson(json);

  const BootstrapNode._();
}

@freezed
abstract class BootstrapNodeList with _$BootstrapNodeList {
  // ignore: invalid_annotation_target
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory BootstrapNodeList({
    required int lastScan,
    required int lastRefresh,
    required List<BootstrapNode> nodes,
  }) = _BootstrapNodeList;
  factory BootstrapNodeList.fromJson(Map<String, dynamic> json) =>
      _$BootstrapNodeListFromJson(json);

  const BootstrapNodeList._();
}
