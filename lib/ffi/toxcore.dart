import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart' as api;
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/api/toxcore/tox_options.dart' as api;
import 'package:btox/ffi/tox_library.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/packets/messagepack.dart';

export 'package:btox/ffi/tox_library.dart' hide ToxLibrary, toxFfiProvider;

final _logger = Logger(['Tox']);

U _handleError<T extends Enum, U>(
  Allocator allocator,
  T Function(int) toEnum,
  U Function(Pointer<CEnum>) callback, [
  String? functionName,
  List<Object?> args = const [],
]) {
  return _scoped(allocator.free, allocator<CEnum>(), (err) {
    final result = callback(err);
    if (err.value != 0) {
      final exn = api.ApiException(toEnum(err.value), functionName, args);
      _logger.e(exn.toString());
      throw exn;
    }
    return result;
  });
}

U _scoped<T extends NativeType, U>(
  void Function(Pointer<T>) cleanup,
  Pointer<T> ptr,
  U Function(Pointer<T>) f,
) {
  try {
    return f(ptr);
  } finally {
    cleanup(ptr);
  }
}

final class Toxcore extends api.Tox {
  final ToxLibrary _lib;
  Pointer<Tox> _tox;

  factory Toxcore(ToxLibrary lib, api.ToxOptions options) {
    _logger.d('Creating Tox instance');
    return options.withNative(lib, (options) {
      _logger.d('Tox options: $options');
      final ptr = _handleError(
        lib.allocator,
        Tox_Err_New.fromValue,
        (err) => lib.ffi.tox_new(options, err),
      );
      lib.ffi.tox_events_init(ptr);
      return Toxcore._(lib, ptr);
    });
  }

  Toxcore._(this._lib, this._tox);

  @override
  ToxAddress get address {
    return _scoped(
      _lib.allocator.free,
      _lib.allocator<Uint8>(_lib.ffi.tox_address_size()),
      (ptr) {
        _lib.ffi.tox_self_get_address(_tox, ptr);
        return ToxAddress(ptr.asTypedList(_lib.ffi.tox_address_size()).clone());
      },
    );
  }

  @override
  bool get isAlive => _tox != nullptr;

  @override
  int get iterationInterval => _lib.ffi.tox_iteration_interval(_tox);

  @override
  set name(String value) {
    value.scopedBytes(_lib.allocator, (ptr, length) {
      _handleError(
        _lib.allocator,
        Tox_Err_Set_Info.fromValue,
        (err) => _lib.ffi.tox_self_set_name(_tox, ptr, length, err),
      );
    });
  }

  @override
  set statusMessage(String value) {
    value.scopedBytes(_lib.allocator, (ptr, length) {
      _handleError(
        _lib.allocator,
        Tox_Err_Set_Info.fromValue,
        (err) => _lib.ffi.tox_self_set_status_message(_tox, ptr, length, err),
      );
    });
  }

  @override
  ToxAddressNospam get nospam =>
      ToxAddressNospam(_lib.ffi.tox_self_get_nospam(_tox));

  @override
  set nospam(ToxAddressNospam value) =>
      _lib.ffi.tox_self_set_nospam(_tox, value.value);

  @override
  void addTcpRelay(String host, int port, PublicKey publicKey) {
    _bootstrap(
      host,
      port,
      publicKey,
      _lib.ffi.tox_add_tcp_relay,
      'tox_add_tcp_relay',
    );
  }

  @override
  void bootstrap(String host, int port, PublicKey publicKey) {
    _bootstrap(host, port, publicKey, _lib.ffi.tox_bootstrap, 'tox_bootstrap');
  }

  @override
  List<Event> iterate() {
    return _handleError(
      _lib.allocator,
      Tox_Err_Iterate_Options_New.fromValue,
      (optErr) => _scoped(
        _lib.ffi.tox_iterate_options_free,
        _lib.ffi.tox_iterate_options_new(optErr),
        (options) {
          _lib.ffi.tox_iterate_options_set_fail_hard(options, true);
          return _iterate(options);
        },
      ),
    );
  }

  List<Event> _iterate(Pointer<Tox_Iterate_Options> options) {
    return _handleError(_lib.allocator, Tox_Err_Events_Iterate.fromValue, (
      err,
    ) {
      return _scoped(
        _lib.ffi.tox_events_free,
        _lib.ffi.tox_events_iterate(_tox, options, err),
        (events) {
          return _scoped(
            _lib.allocator.free,
            _lib.allocator<Uint8>(_lib.ffi.tox_events_bytes_size(events)),
            (ptr) {
              if (!_lib.ffi.tox_events_get_bytes(events, ptr)) {
                throw Exception('Failed to get events bytes');
              }
              return Event.unpackList(
                Unpacker(
                  ptr.asTypedList(_lib.ffi.tox_events_bytes_size(events)),
                ),
              );
            },
          );
        },
      );
    });
  }

  @override
  void kill() {
    _logger.d('Killing Tox instance: $address');
    final ptr = _tox;
    _tox = nullptr;
    _lib.ffi.tox_kill(ptr);
  }

  void _bootstrap(
    String host,
    int port,
    PublicKey publicKey,
    bool Function(
      Pointer<Tox> tox,
      Pointer<CChar> host,
      int port,
      Pointer<Uint8> publicKey,
      Pointer<CEnum> error,
    )
    f,
    String functionName,
  ) {
    host.scopedCString(_lib.allocator, (hostPtr) {
      publicKey.bytes.scoped(_lib.allocator, (publicKeyPtr, length) {
        assert(length == _lib.ffi.tox_public_key_size());
        _handleError(
          _lib.allocator,
          Tox_Err_Bootstrap.fromValue,
          (err) => f(_tox, hostPtr, port, publicKeyPtr, err),
          functionName,
          [host, port, publicKey],
        );
      });
    });
  }
}

extension on api.ToxOptions {
  T withNative<T>(ToxLibrary lib, T Function(Pointer<Tox_Options>) callback) {
    return _scoped(
      lib.ffi.tox_options_free,
      _handleError(
        lib.allocator,
        Tox_Err_Options_New.fromValue,
        lib.ffi.tox_options_new,
      ),
      (options) {
        lib.ffi.tox_options_set_ipv6_enabled(options, ipv6Enabled);
        lib.ffi.tox_options_set_udp_enabled(options, udpEnabled);
        lib.ffi.tox_options_set_local_discovery_enabled(
          options,
          localDiscoveryEnabled,
        );

        return savedata.scoped(lib.allocator, (ptr, length) {
          lib.ffi.tox_options_set_savedata_type(options, savedataType);
          lib.ffi.tox_options_set_savedata_data(options, ptr, length);
          return callback(options);
        });
      },
    );
  }
}

extension on Uint8List {
  Uint8List clone() {
    return Uint8List.fromList(this);
  }
}

extension on Uint8List? {
  T scoped<T>(Allocator allocator, T Function(Pointer<Uint8>, int length) f) {
    if (this == null) {
      return f(nullptr, 0);
    }
    return _scoped(allocator.free, allocator.allocate<Uint8>(this!.length), (
      ptr,
    ) {
      ptr.asTypedList(this!.length).setAll(0, this!);
      return f(ptr, this!.length);
    });
  }
}

extension on String {
  T scopedBytes<T>(Allocator allocator, T Function(Pointer<Uint8>, int) f) {
    final units = utf8.encode(this);
    return _scoped(allocator.free, allocator.allocate<Uint8>(units.length), (
      ptr,
    ) {
      for (var i = 0; i < units.length; i++) {
        ptr[i] = units[i];
      }
      return f(ptr, units.length);
    });
  }

  T scopedCString<T>(Allocator allocator, T Function(Pointer<CChar>) f) {
    final units = utf8.encode(this);
    return _scoped(allocator.free, allocator<Uint8>(units.length + 1), (ptr) {
      final nativeString = ptr.asTypedList(units.length + 1);
      nativeString.setAll(0, units);
      nativeString[units.length] = 0;
      _logger.v('Scoped C string: ${utf8.decode(nativeString)}');
      assert(utf8.decode(nativeString).substring(0, length) == this);
      return f(ptr.cast<CChar>());
    });
  }
}
