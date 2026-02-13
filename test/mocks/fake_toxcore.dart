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

  void pushEvent(Event event) {
    _events.add(event);
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
  PublicKey getFriendPublicKey(int friendNumber) {
    if (missingFriendNumbers.contains(friendNumber)) {
      throw api.ApiException(
        ffi
            .Tox_Err_Friend_Get_Public_Key
            .TOX_ERR_FRIEND_GET_PUBLIC_KEY_FRIEND_NOT_FOUND,
      );
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
  ToxAddressNospam get nospam => address.nospam;

  @override
  set nospam(ToxAddressNospam value) {}
}
