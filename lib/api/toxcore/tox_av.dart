import 'package:btox/api/toxcore/tox_api.dart';
import 'package:btox/api/toxcore/tox_av_events.dart';

export 'package:btox/api/toxcore/tox_av_events.dart';

/// toxav for a running Tox. It ends with its Tox.
abstract class ToxAv implements ToxAvApi {
  const ToxAv();

  /// toxav's callbacks since the last time, also those of toxcore's
  /// iterations, such as calls starting.
  List<AvEvent> iterate();
}
