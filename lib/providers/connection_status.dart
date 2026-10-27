import 'package:btox/background_service.dart';
import 'package:btox/models/connection_status.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/services/connection_status_channel.dart';
import 'package:btox/services/tox_session.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connection_status.g.dart';

@riverpod
Stream<ConnectionStatuses?> _publishedConnectionStatuses(Ref ref) =>
    watchConnectionStatuses(whenMissing: ensureServiceRunning);

/// Null while the background service isn't running.
@riverpod
ConnectionStatuses? connectionStatuses(Ref ref) {
  if (AnyPlatform.instance.isMobile) {
    return ref.watch(_publishedConnectionStatusesProvider).value;
  }
  return ref.watch(toxSessionsProvider);
}

/// The status of the profile the UI shows.
@riverpod
ConnectionStatus? connectionStatus(Ref ref) {
  final profile = ref.watch(currentProfileProvider);
  return profile == null
      ? null
      : ref.watch(connectionStatusesProvider)?[profile.id];
}
