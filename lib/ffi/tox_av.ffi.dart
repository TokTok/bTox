import 'package:btox/api/toxcore/tox_api.dart' as api;
import 'package:btox/api/toxcore/tox_av.dart' as api;

import 'dart:ffi' as native;

import 'package:btox/api/toxcore/tox_av_callbacks.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart' as native;
import 'package:btox/ffi/tox_library.dart';

final class ToxAvFfi extends api.ToxAv with api.ToxAvFfiApi {
  @override
  final ToxLibrary lib;

  Pointer<ToxAV> _pointer;

  /// Calls after [kill] throw, rather than pass toxav a null ToxAV.
  @override
  Pointer<ToxAV> get pointer =>
      _pointer == nullptr ? throw StateError('The ToxAV was killed') : _pointer;

  final AvEventCollector _events;

  factory ToxAvFfi(ToxLibrary lib, Pointer<Tox> tox) {
    final err = lib.allocator<CEnum>();
    try {
      final av = lib.ffi.toxav_new(tox, err);
      if (err.value != 0) {
        throw api.ApiException(Toxav_Err_New.fromValue(err.value), 'toxav_new');
      }
      return ToxAvFfi._(lib, av);
    } finally {
      lib.allocator.free(err);
    }
  }

  // The analyzer sees tox_library's web version. Natively, its types are
  // dart:ffi's, as the collector's are.
  ToxAvFfi._(this.lib, this._pointer)
    : _events = AvEventCollector(
        lib.ffi as native.ToxFfi,
        _pointer as native.Pointer<native.ToxAV>,
      );

  @override
  List<api.AvEvent> iterate() {
    lib.ffi.toxav_iterate(pointer);
    final events = [..._events.events];
    _events.events.clear();
    return events;
  }

  /// Before its Tox is killed.
  void kill() {
    lib.ffi.toxav_kill(pointer);
    _pointer = nullptr;
    _events.close();
  }
}
