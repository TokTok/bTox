// Fake implementation of the Tox class for testing purposes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart' as api;
import 'package:btox/api/toxcore/tox_av.dart' as api;
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/ffi/toxcore.dart' as ffi;
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';

import 'fake_tox_av.dart';

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
  // Thrown by the next iterate, as for events that can't be read.
  Object? iterateError;
  final List<Event> _events = [];

  final List<PublicKey> friends = [];

  final List<(ToxAddress, String)> friendRequests = [];

  final List<int> deletedFriends = [];

  /// (friend number, message ID, text)
  final List<(int, int, String)> sentMessages = [];

  final Set<int> unreachableFriends = {};
  // Friends Tox doesn't see online yet, so it takes no packets for them.
  final Set<int> unconnectedFriends = {};

  /// How many more messages Tox takes before its queue is full, if limited.
  int? sendQueueRoom;

  final List<(int, int, ffi.Tox_File_Control)> fileControls = [];
  final List<(int, int, String)> fileSends = [];
  // By file number, as fileSends.
  final List<(int, Uint8List)> fileSendKinds = [];
  final List<(int, int, int, Uint8List)> fileChunks = [];
  final List<(int, int, int)> fileSeeks = [];
  // Of files friends send, by friend number and file number, else made up
  // from those.
  final Map<(int, int), Uint8List> fileIds = {};
  // How many more chunks find the send queue full.
  int fullChunkQueues = 0;
  // Where each file's next chunk must start, as Tox takes them in order.
  final _nextChunk = <(int, int), int>{};
  final List<(int, Uint8List)> losslessPackets = [];

  int _nextMessageId = 0;

  var _connection = ffi.Tox_Connection.TOX_CONNECTION_NONE;

  void pushEvent(Event event) {
    if (event case ToxEventSelfConnectionStatus(:final connectionStatus)) {
      _connection = connectionStatus;
    }
    _events.add(event);
  }

  final av = FakeToxAv();

  @override
  api.ToxAv startAv() => av;

  @override
  ffi.Tox_Connection selfGetConnectionStatus() => _connection;

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
    final existing = friends.indexOf(publicKey);
    if (existing != -1 && !deletedFriends.contains(existing)) {
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
    if (iterateError case final error?) {
      iterateError = null;
      throw error;
    }
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
  void friendSendLosslessPacket(int friendNumber, Uint8List data) {
    if (unconnectedFriends.contains(friendNumber)) {
      throw const api.ApiException(
        ffi
            .Tox_Err_Friend_Custom_Packet
            .TOX_ERR_FRIEND_CUSTOM_PACKET_FRIEND_NOT_CONNECTED,
      );
    }
    losslessPackets.add((friendNumber, data));
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
    if (sendQueueRoom case final room?) {
      if (room == 0) {
        throw api.ApiException(
          ffi.Tox_Err_Friend_Send_Message.TOX_ERR_FRIEND_SEND_MESSAGE_SENDQ,
        );
      }
      sendQueueRoom = room - 1;
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
    fileSendKinds.add((kind, fileId));
    _nextChunk[(friendNumber, fileSends.length - 1)] = 0;
    return fileSends.length - 1;
  }

  @override
  void fileSeek(int friendNumber, int fileNumber, int position) =>
      fileSeeks.add((friendNumber, fileNumber, position));

  @override
  Uint8List fileGetFileId(int friendNumber, int fileNumber) =>
      fileIds[(friendNumber, fileNumber)] ??
      (Uint8List(32)
        ..[0] = friendNumber
        ..[1] = fileNumber);

  @override
  void fileSendChunk(
    int friendNumber,
    int fileNumber,
    int position,
    Uint8List data,
  ) {
    final key = (friendNumber, fileNumber);
    if (position != (_nextChunk[key] ?? position)) {
      throw const api.ApiException(
        ffi.Tox_Err_File_Send_Chunk.TOX_ERR_FILE_SEND_CHUNK_WRONG_POSITION,
      );
    }
    if (fullChunkQueues > 0) {
      fullChunkQueues--;
      throw const api.ApiException(
        ffi.Tox_Err_File_Send_Chunk.TOX_ERR_FILE_SEND_CHUNK_SENDQ,
      );
    }
    _nextChunk[key] = position + data.length;
    fileChunks.add((friendNumber, fileNumber, position, data));
  }
}
