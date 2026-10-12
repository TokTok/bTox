import 'package:btox/ffi/toxcore.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/services/tox_message_service.dart';
import 'package:btox/services/tox_outbox.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The background service does this on mobile.
void runToxOwner(
  ProviderContainer container,
  void Function(Tox_Connection? status) onStatus,
) {
  container.listen(toxMessageServiceProvider, (_, _) {});
  container.listen(activeToxOutboxProvider, (_, _) {});
  container.listen(
    ownConnectionStatusProvider,
    (_, status) => onStatus(status),
    fireImmediately: true,
  );
}
