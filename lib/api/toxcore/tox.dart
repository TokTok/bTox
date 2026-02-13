import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/models/crypto.dart';

final class ApiException<T extends Enum> implements Exception {
  final T error;
  final String? functionName;
  final List<Object?> args;

  const ApiException(this.error, [this.functionName, this.args = const []]);

  @override
  String toString() {
    if (functionName != null) {
      return 'ApiException: $error in $functionName with args $args';
    }
    return 'ApiException: $error';
  }
}

abstract class Tox {
  const Tox();

  ToxAddress get address;

  bool get isAlive;

  int get iterationInterval;

  set name(String value);

  ToxAddressNospam get nospam;

  set nospam(ToxAddressNospam value);

  set statusMessage(String value);

  void addTcpRelay(String host, int port, PublicKey publicKey);

  void bootstrap(String host, int port, PublicKey publicKey);

  PublicKey getFriendPublicKey(int friendNumber);

  List<Event> iterate();

  void kill();
}

final class ToxConstants {
  final int addressSize;
  final int conferenceIdSize;
  final int fileIdLength;
  final int groupChatIdSize;
  final int groupMaxCustomLosslessPacketLength;
  final int groupMaxCustomLossyPacketLength;
  final int groupMaxGroupNameLength;
  final int groupMaxMessageLength;
  final int groupMaxPartLength;
  final int groupMaxPasswordSize;
  final int groupMaxTopicLength;
  final int groupPeerPublicKeySize;
  final int hashLength;
  final int maxCustomPacketSize;
  final int maxFilenameLength;
  final int maxFriendRequestLength;
  final int maxHostnameLength;
  final int maxMessageLength;
  final int maxNameLength;
  final int maxStatusMessageLength;
  final int nospamSize;
  final int publicKeySize;
  final int secretKeySize;

  const ToxConstants({
    required this.addressSize,
    required this.conferenceIdSize,
    required this.fileIdLength,
    required this.groupChatIdSize,
    required this.groupMaxCustomLosslessPacketLength,
    required this.groupMaxCustomLossyPacketLength,
    required this.groupMaxGroupNameLength,
    required this.groupMaxMessageLength,
    required this.groupMaxPartLength,
    required this.groupMaxPasswordSize,
    required this.groupMaxTopicLength,
    required this.groupPeerPublicKeySize,
    required this.hashLength,
    required this.maxCustomPacketSize,
    required this.maxFilenameLength,
    required this.maxFriendRequestLength,
    required this.maxHostnameLength,
    required this.maxMessageLength,
    required this.maxNameLength,
    required this.maxStatusMessageLength,
    required this.nospamSize,
    required this.publicKeySize,
    required this.secretKeySize,
  });
}
