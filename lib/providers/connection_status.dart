import 'package:btox/models/connection_status.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/services/connection_status_channel.dart';
import 'package:btox/services/tox_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _publishedConnectionStatusesProvider =
    StreamProvider<ConnectionStatuses?>((ref) => watchConnectionStatuses());

/// Null while the background service isn't running.
final connectionStatusesProvider = Provider<ConnectionStatuses?>((ref) {
  if (AnyPlatform.instance.isMobile) {
    return ref.watch(_publishedConnectionStatusesProvider).value;
  }
  return ref.watch(toxSessionsProvider);
});

/// The status of the profile the UI shows.
final connectionStatusProvider = Provider<ConnectionStatus?>((ref) {
  final profile = ref.watch(currentProfileProvider);
  return profile == null
      ? null
      : ref.watch(connectionStatusesProvider)?[profile.id];
});
