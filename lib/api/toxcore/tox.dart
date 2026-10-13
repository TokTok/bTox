import 'package:btox/api/toxcore/tox_api.dart';
import 'package:btox/api/toxcore/tox_events.dart';

export 'package:btox/api/toxcore/tox_api.dart';

/// A running Tox: toxcore's functions, plus its events and its end.
abstract class Tox implements ToxApi {
  const Tox();

  bool get isAlive;

  List<Event> iterate();

  void kill();
}
