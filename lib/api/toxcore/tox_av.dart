import 'package:btox/api/toxcore/tox_api.dart';
import 'package:btox/api/toxcore/tox_av_events.dart';

export 'package:btox/api/toxcore/tox_av_events.dart';

abstract class ToxAv implements ToxAvApi {
  const ToxAv();

  /// The callbacks since the last call, toxcore's too.
  List<AvEvent> iterate();
}
