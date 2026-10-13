import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/api/toxcore/tox_options.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart' as gen;
import 'package:btox/ffi/tox_library.ffi.dart' as tox_lib;
import 'package:btox/ffi/toxcore.dart' show Toxcore;
import 'package:btox/models/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

// Events from real toxcore rather than from our own packer.
void main() {
  test('decodes events from toxcore', () async {
    final lib = tox_lib.ToxLibrary(
      malloc,
      gen.ToxFfi(DynamicLibrary.open('linux/vendored/libtoxcore.so')),
    );
    final f = lib.ffi;
    final err = malloc<UnsignedInt>();
    final options = f.tox_options_new(err);
    f.tox_options_set_local_discovery_enabled(options, false);
    final friend = f.tox_new(options, err);
    f.tox_options_free(options);
    addTearDown(() => f.tox_kill(friend));

    // ignore: argument_type_not_assignable
    final tox = Toxcore(lib, const ToxOptions(localDiscoveryEnabled: false));
    addTearDown(tox.kill);
    expect(
      ToxAddress.of(
        tox.selfGetPublicKey(),
        ToxAddressNospam(tox.selfGetNospam()),
      ),
      tox.selfGetAddress(),
    );

    Uint8List read(void Function(Pointer<Uint8>) get) {
      final ptr = malloc<Uint8>(PublicKey.kLength);
      get(ptr);
      final bytes = Uint8List.fromList(ptr.asTypedList(PublicKey.kLength));
      malloc.free(ptr);
      return bytes;
    }

    void withBytes(List<int> bytes, void Function(Pointer<Uint8>, int) f) {
      final ptr = malloc<Uint8>(bytes.length);
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      f(ptr, bytes.length);
      malloc.free(ptr);
    }

    final events = <Event>[];
    Future<T> next<T extends Event>() async {
      for (var i = 0; i < 1500; i++) {
        f.tox_iterate(friend, nullptr);
        events.addAll(tox.iterate());
        final index = events.indexWhere((e) => e is T);
        if (index >= 0) {
          return events.removeAt(index) as T;
        }
        await Future.delayed(const Duration(milliseconds: 20));
      }
      throw TimeoutException('No $T');
    }

    tox.bootstrap(
      '127.0.0.1',
      f.tox_self_get_udp_port(friend, err),
      PublicKey(read((ptr) => f.tox_self_get_dht_id(friend, ptr))),
    );
    final friendKey = PublicKey(
      read((ptr) => f.tox_self_get_public_key(friend, ptr)),
    );

    withBytes(tox.selfGetAddress().bytes, (address, _) {
      withBytes(utf8.encode('Add me'), (message, length) {
        f.tox_friend_add(friend, address, message, length, err);
      });
    });
    final request = await next<ToxEventFriendRequest>();
    expect(request.publicKey, friendKey);
    expect(utf8.decode(request.message), 'Add me');

    tox.selfSetName(utf8.encode('Me'));
    withBytes(utf8.encode('Friend'), (name, length) {
      f.tox_self_set_name(friend, name, length, err);
    });
    final friendNumber = tox.friendAddNorequest(request.publicKey);
    final connection = await next<ToxEventFriendConnectionStatus>();
    expect(connection.friendNumber, friendNumber);
    expect(
      connection.connectionStatus,
      isNot(gen.Tox_Connection.TOX_CONNECTION_NONE),
    );

    final name = await next<ToxEventFriendName>();
    expect(utf8.decode(name.name), 'Friend');
    for (var i = 0; i < 500; i++) {
      if (f.tox_friend_get_name_size(friend, 0, err) == 2) {
        break;
      }
      f.tox_iterate(friend, nullptr);
      events.addAll(tox.iterate());
      await Future.delayed(const Duration(milliseconds: 20));
    }
    expect(
      utf8.decode(
        read((ptr) => f.tox_friend_get_name(friend, 0, ptr, err)).sublist(0, 2),
      ),
      'Me',
    );

    withBytes(utf8.encode('Grüße'), (message, length) {
      f.tox_friend_send_message(
        friend,
        0,
        gen.Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
        message,
        length,
        err,
      );
    });
    final message = await next<ToxEventFriendMessage>();
    expect(message.friendNumber, friendNumber);
    expect(utf8.decode(message.message), 'Grüße');
  }, timeout: const Timeout(Duration(seconds: 90)));
}
