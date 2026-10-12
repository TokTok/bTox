import 'package:btox/ffi/toxcore.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class ConnectionStatusIcon extends ConsumerWidget {
  const ConnectionStatusIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = switch (ref.watch(connectionStatusProvider)) {
      null || Tox_Connection.TOX_CONNECTION_NONE => false,
      Tox_Connection.TOX_CONNECTION_TCP ||
      Tox_Connection.TOX_CONNECTION_UDP => true,
    };
    return Icon(
      online ? Icons.online_prediction : Icons.offline_bolt_outlined,
      color: online ? Colors.green : Colors.red,
    );
  }
}
