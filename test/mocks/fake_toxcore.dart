// Fake implementation of the Tox class for testing purposes.
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart' as api;
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/ffi/toxcore.dart' as ffi;
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';

const _logger = Logger(['FakeToxcore']);

final class FakeToxcore extends api.Tox {
  @override
  String name = 'Yanciman';

  @override
  String statusMessage = 'Producing works of art in Kannywood';

  @override
  ToxAddress get address {
    return ToxAddress.fromString(
      '52602D8D81573725A77F602A53CD1CD8C2156595E8C3310EAC3552E99B7FB50D897BC532A375',
    );
  }

  @override
  bool isAlive = true;

  @override
  int get iterationInterval => 20;

  bool throwOnBootstrap = false;
  final Set<int> missingFriendNumbers = {};
  final List<Event> _events = [];

  final List<PublicKey> friends = [];

  final List<(ToxAddress, String)> friendRequests = [];

  final List<int> deletedFriends = [];

  /// (friend number, message ID, text)
  final List<(int, int, String)> sentMessages = [];

  final Set<int> unreachableFriends = {};

  int _nextMessageId = 0;

  void pushEvent(Event event) {
    _events.add(event);
  }

  @override
  int addFriend(ToxAddress address, String message) {
    final friendNumber = addFriendNorequest(address.publicKey);
    friendRequests.add((address, message));
    return friendNumber;
  }

  @override
  int addFriendNorequest(PublicKey publicKey) {
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
  void deleteFriend(int friendNumber) => deletedFriends.add(friendNumber);

  @override
  List<int> get friendList => List.generate(friends.length, (i) => i);

  @override
  SecretKey get secretKey => SecretKey(Uint8List(32));

  @override
  String getFriendName(int friendNumber) => '';

  @override
  PublicKey getFriendPublicKey(int friendNumber) {
    if (missingFriendNumbers.contains(friendNumber)) {
      throw api.ApiException(
        ffi
            .Tox_Err_Friend_Get_Public_Key
            .TOX_ERR_FRIEND_GET_PUBLIC_KEY_FRIEND_NOT_FOUND,
      );
    }
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
  int sendFriendMessage(int friendNumber, String message) {
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
    sentMessages.add((friendNumber, messageId, message));
    return messageId;
  }

  @override
  ToxAddressNospam get nospam => address.nospam;

  @override
  set nospam(ToxAddressNospam value) {}
}
