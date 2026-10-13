import 'package:btox/models/connection_status.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class ConnectionStatusIcon extends ConsumerWidget {
  const ConnectionStatusIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider);
    return Tooltip(
      message: connectionStatusText(status),
      child: switch (status) {
        ConnectionStatus(proxyProblem: _?) => const Icon(
          Icons.warning_amber,
          color: Colors.orange,
        ),
        ConnectionStatus(online: true) => const Icon(
          Icons.online_prediction,
          color: Colors.green,
        ),
        _ => const Icon(Icons.offline_bolt_outlined, color: Colors.red),
      },
    );
  }
}
