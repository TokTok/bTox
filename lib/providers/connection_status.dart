import 'package:btox/ffi/toxcore.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/services/connection_status_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Watching this runs Tox, so only the Tox owner may watch it.
final ownConnectionStatusProvider = Provider<Tox_Connection?>((ref) {
  final profile = ref.watch(activeProfileProvider);
  if (profile == null) {
    return null;
  }
  return ref.watch(
    selfConnectionStatusProvider(profile.secretKey, profile.nospam),
  );
});

final _publishedConnectionStatusProvider = StreamProvider<Tox_Connection?>(
  (ref) => watchConnectionStatus(),
);

final connectionStatusProvider = Provider<Tox_Connection?>((ref) {
  if (AnyPlatform.instance.isMobile) {
    return ref.watch(_publishedConnectionStatusProvider).value;
  }
  return ref.watch(ownConnectionStatusProvider);
});
