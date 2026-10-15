import 'package:btox_call_media/btox_call_media.dart';

/// Browsers have no calls: toxcore can't reach peers there.
BtoxCallMedia platformCallMedia() =>
    throw UnsupportedError('No calls on the web');
