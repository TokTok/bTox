import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_api.dart';
import 'package:btox/api/toxcore/tox_av.dart';
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_File_Control;

export 'package:btox/api/toxcore/tox_api.dart';

/// A running Tox: toxcore's functions, plus its events and its end.
abstract class Tox implements ToxApi {
  const Tox();

  bool get isAlive;

  List<Event> iterate();

  /// Started on first use. It ends with this Tox.
  ToxAv startAv();

  void kill();
}

abstract interface class ToxFiles {
  void chunk(int friendNumber, int fileNumber, int position, Uint8List data);
  void requested(int friendNumber, int fileNumber, int position, int length);
  void controlled(int friendNumber, int fileNumber, Tox_File_Control control);
}
