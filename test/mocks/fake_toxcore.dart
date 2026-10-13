// Fake implementation of the Tox class for testing purposes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart' as api;
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/ffi/toxcore.dart' as ffi;
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';

const _logger = Logger(['FakeToxcore']);

final _address = ToxAddress.fromString(
  '52602D8D81573725A77F602A53CD1CD8C2156595E8C3310EAC3552E99B7FB50D897BC532A375',
);

/// Implements the parts of toxcore that tests use; the rest throws.
final class FakeToxcore extends api.Tox {
  String name = 'Yanciman';

  String statusMessage = 'Producing works of art in Kannywood';

  @override
  bool isAlive = true;

  bool throwOnBootstrap = false;
  final List<Event> _events = [];

  final List<PublicKey> friends = [];

  final List<(ToxAddress, String)> friendRequests = [];

  final List<int> deletedFriends = [];

  /// (friend number, message ID, text)
  final List<(int, int, String)> sentMessages = [];

  final Set<int> unreachableFriends = {};

  final List<(int, int, ffi.Tox_File_Control)> fileControls = [];
  final List<(int, int, String)> fileSends = [];
  final List<(int, int, int, Uint8List)> fileChunks = [];

  int _nextMessageId = 0;

  void pushEvent(Event event) {
    _events.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  int iterationInterval() => 20;

  @override
  ToxAddress selfGetAddress() => _address;

  @override
  void selfSetNospam(int nospam) {}

  @override
  void selfSetName(Uint8List name) => this.name = utf8.decode(name);

  @override
  void selfSetStatusMessage(Uint8List statusMessage) =>
      this.statusMessage = utf8.decode(statusMessage);

  @override
  int friendAdd(ToxAddress address, Uint8List message) {
    final friendNumber = friendAddNorequest(address.publicKey);
    friendRequests.add((address, utf8.decode(message)));
    return friendNumber;
  }

  @override
  int friendAddNorequest(PublicKey publicKey) {
    if (friends.contains(publicKey)) {
      throw api.ApiException(
        ffi.Tox_Err_Friend_Add.TOX_ERR_FRIEND_ADD_ALREADY_SENT,
      );
    }
    friends.add(publicKey);
    return friends.length - 1;
  }

  @override
  void addTcpRelay(String host, int port, PublicKey publicKey) {
    if (throwOnBootstrap) {
      throw api.ApiException(ffi.Tox_Err_Bootstrap.TOX_ERR_BOOTSTRAP_BAD_HOST);
    }
  }

  @override
  void bootstrap(String host, int port, PublicKey publicKey) {
    if (throwOnBootstrap) {
      throw api.ApiException(ffi.Tox_Err_Bootstrap.TOX_ERR_BOOTSTRAP_BAD_HOST);
    }
  }

  @override
  void friendDelete(int friendNumber) => deletedFriends.add(friendNumber);

  @override
  PublicKey friendGetPublicKey(int friendNumber) {
    if (friendNumber < friends.length) {
      return friends[friendNumber];
    }
    return PublicKey(Uint8List.fromList(List.filled(32, friendNumber + 1)));
  }

  @override
  List<Event> iterate() {
    final result = List<Event>.from(_events);
    _events.clear();
    return result;
  }

  @override
  void kill() {
    _logger.d('Killing Tox instance');
    isAlive = false;
  }

  @override
  int friendSendMessage(
    int friendNumber,
    ffi.Tox_Message_Type type,
    Uint8List message,
  ) {
    if (friendNumber >= friends.length) {
      throw api.ApiException(
        ffi
            .Tox_Err_Friend_Send_Message
            .TOX_ERR_FRIEND_SEND_MESSAGE_FRIEND_NOT_FOUND,
      );
    }
    if (unreachableFriends.contains(friendNumber)) {
      throw api.ApiException(
        ffi
            .Tox_Err_Friend_Send_Message
            .TOX_ERR_FRIEND_SEND_MESSAGE_FRIEND_NOT_CONNECTED,
      );
    }
    final messageId = _nextMessageId++;
    sentMessages.add((friendNumber, messageId, utf8.decode(message)));
    return messageId;
  }

  @override
  void fileControl(
    int friendNumber,
    int fileNumber,
    ffi.Tox_File_Control control,
  ) => fileControls.add((friendNumber, fileNumber, control));

  @override
  int fileSend(
    int friendNumber,
    int kind,
    int fileSize,
    Uint8List fileId,
    Uint8List filename,
  ) {
    fileSends.add((friendNumber, fileSize, utf8.decode(filename)));
    return fileSends.length - 1;
  }

  @override
  void fileSendChunk(
    int friendNumber,
    int fileNumber,
    int position,
    Uint8List data,
  ) => fileChunks.add((friendNumber, fileNumber, position, data));
}
