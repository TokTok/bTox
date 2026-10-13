import 'package:btox/models/crypto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'bootstrap_nodes.freezed.dart';
part 'bootstrap_nodes.g.dart';

@freezed
abstract class BootstrapNode with _$BootstrapNode {
  // ignore: invalid_annotation_target
  @JsonSerializable(explicitToJson: true, fieldRename: FieldRename.snake)
  const factory BootstrapNode({
    required String ipv4,
    required int port,
    required List<int> tcpPorts,
    required PublicKey publicKey,
  }) = _BootstrapNode;
  factory BootstrapNode.fromJson(Map<String, dynamic> json) =>
      _$BootstrapNodeFromJson(json);
}

@freezed
abstract class BootstrapNodeList with _$BootstrapNodeList {
  // ignore: invalid_annotation_target
  @JsonSerializable(explicitToJson: true, fieldRename: FieldRename.snake)
  const factory BootstrapNodeList({required List<BootstrapNode> nodes}) =
      _BootstrapNodeList;
  factory BootstrapNodeList.fromJson(Map<String, dynamic> json) =>
      _$BootstrapNodeListFromJson(json);
}
