import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart' as api;
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/api/toxcore/tox_av.dart' as api;
import 'package:btox/api/toxcore/tox_options.dart' as api;
import 'package:btox/ffi/tox_av.dart';
import 'package:btox/ffi/tox_library.dart';
import 'package:btox/logger.dart';
import 'package:btox/packets/messagepack.dart';

export 'package:btox/ffi/tox_library.dart' hide ToxLibrary, toxFfiProvider;

final _logger = Logger(['Tox']);

U _handleError<T extends Enum, U>(
  Allocator allocator,
  T Function(int) toEnum,
  U Function(Pointer<CEnum>) callback, [
  String? functionName,
]) {
  return _scoped(allocator.free, allocator<CEnum>(), (err) {
    final result = callback(err);
    if (err.value != 0) {
      final exn = api.ApiException(toEnum(err.value), functionName);
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

final class Toxcore extends api.Tox with api.ToxFfiApi {
  @override
  final ToxLibrary lib;

  Pointer<Tox> _pointer;

  /// Calls after [kill] throw, rather than pass toxcore a null Tox.
  @override
  Pointer<Tox> get pointer =>
      _pointer == nullptr ? throw StateError('The Tox was killed') : _pointer;

  factory Toxcore(ToxLibrary lib, api.ToxOptions options) {
    _logger.d('Creating Tox instance');
    return _scoped(
      lib.ffi.tox_options_free,
      _handleError(
        lib.allocator,
        Tox_Err_Options_New.fromValue,
        lib.ffi.tox_options_new,
      ),
      (native) {
        options.applyTo(lib, native);
        final ptr = _handleError(
          lib.allocator,
          Tox_Err_New.fromValue,
          (err) => lib.ffi.tox_new(native, err),
        );
        lib.ffi.tox_events_init(ptr);
        return Toxcore._(lib, ptr);
      },
    );
  }

  ToxAvFfi? _av;

  Toxcore._(this.lib, this._pointer);

  @override
  bool get isAlive => _pointer != nullptr;

  @override
  List<Event> iterate() {
    return _handleError(
      lib.allocator,
      Tox_Err_Iterate_Options_New.fromValue,
      (optErr) => _scoped(
        lib.ffi.tox_iterate_options_free,
        lib.ffi.tox_iterate_options_new(optErr),
        (options) {
          lib.ffi.tox_iterate_options_set_fail_hard(options, true);
          return _iterate(options);
        },
      ),
    );
  }

  List<Event> _iterate(Pointer<Tox_Iterate_Options> options) {
    return _handleError(lib.allocator, Tox_Err_Events_Iterate.fromValue, (err) {
      return _scoped(
        lib.ffi.tox_events_free,
        lib.ffi.tox_events_iterate(pointer, options, err),
        (events) {
          final size = lib.ffi.tox_events_bytes_size(events);
          return _scoped(lib.allocator.free, lib.allocator<Uint8>(size), (ptr) {
            if (!lib.ffi.tox_events_get_bytes(events, ptr)) {
              throw Exception('Failed to get events bytes');
            }
            // The events keep views of these bytes, so copy them out of
            // the native buffer we free.
            return unpackEvents(Unpacker(ptr.asTypedList(size).clone()));
          });
        },
      );
    });
  }

  @override
  api.ToxAv startAv() => _av ??= ToxAvFfi(lib, pointer);

  @override
  void kill() {
    _logger.d('Killing Tox instance: ${selfGetAddress()}');
    _av?.kill();
    _av = null;
    final ptr = pointer;
    _pointer = nullptr;
    lib.ffi.tox_kill(ptr);
  }
}

bool isToxSaveEncrypted(ToxLibrary lib, Uint8List save) =>
    save.length >= lib.ffi.tox_pass_encryption_extra_length() &&
    save.scoped(lib.allocator, (ptr, _) => lib.ffi.tox_is_data_encrypted(ptr));

Uint8List decryptToxSave(ToxLibrary lib, Uint8List save, String passphrase) {
  final plainLength = save.length - lib.ffi.tox_pass_encryption_extra_length();
  return save.scoped(lib.allocator, (savePtr, length) {
    return utf8.encode(passphrase).scoped(lib.allocator, (passPtr, passLength) {
      return _scoped(lib.allocator.free, lib.allocator<Uint8>(plainLength), (
        plain,
      ) {
        _handleError(
          lib.allocator,
          Tox_Err_Decryption.fromValue,
          (err) => lib.ffi.tox_pass_decrypt(
            savePtr,
            length,
            passPtr,
            passLength,
            plain,
            err,
          ),
          'tox_pass_decrypt',
        );
        return plain.asTypedList(plainLength).clone();
      });
    });
  });
}

Uint8List passEncrypt(ToxLibrary lib, Uint8List data, String passphrase) {
  final length = data.length + lib.ffi.tox_pass_encryption_extra_length();
  return data.scoped(lib.allocator, (dataPtr, dataLength) {
    return utf8.encode(passphrase).scoped(lib.allocator, (passPtr, passLength) {
      return _scoped(lib.allocator.free, lib.allocator<Uint8>(length), (
        encrypted,
      ) {
        _handleError(
          lib.allocator,
          Tox_Err_Encryption.fromValue,
          (err) => lib.ffi.tox_pass_encrypt(
            dataPtr,
            dataLength,
            passPtr,
            passLength,
            encrypted,
            err,
          ),
          'tox_pass_encrypt',
        );
        return encrypted.asTypedList(length).clone();
      });
    });
  });
}

extension on Uint8List {
  Uint8List clone() => Uint8List.fromList(this);

  T scoped<T>(Allocator allocator, T Function(Pointer<Uint8>, int length) f) {
    return _scoped(allocator.free, allocator.allocate<Uint8>(length), (ptr) {
      ptr.asTypedList(length).setAll(0, this);
      return f(ptr, length);
    });
  }
}
