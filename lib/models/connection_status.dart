import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'connection_status.freezed.dart';

enum ProxyProblem { rejected, unreachable }

typedef ConnectionStatuses = Map<Id<Profiles>, ConnectionStatus>;

@freezed
abstract class ConnectionStatus with _$ConnectionStatus {
  const factory ConnectionStatus({
    required Tox_Connection connection,
    ProxyProblem? proxyProblem,
    @Default('') String proxy,
  }) = _ConnectionStatus;

  const ConnectionStatus._();

  factory ConnectionStatus.fromMessage(List<Object?> message) {
    final [connection as String, problem as String?, proxy as String] = message;
    return ConnectionStatus(
      connection: Tox_Connection.values.byName(connection),
      proxyProblem: problem == null
          ? null
          : ProxyProblem.values.byName(problem),
      proxy: proxy,
    );
  }

  bool get online => connection != Tox_Connection.TOX_CONNECTION_NONE;

  List<Object?> toMessage() => [connection.name, proxyProblem?.name, proxy];
}

String connectionStatusText(ConnectionStatus? status) => switch (status) {
  null => 'Offline',
  ConnectionStatus(proxyProblem: ProxyProblem.rejected, :final proxy) =>
    "Can't use proxy $proxy",
  ConnectionStatus(proxyProblem: ProxyProblem.unreachable, :final proxy) =>
    "Can't reach proxy at $proxy",
  ConnectionStatus(online: false) => 'Connecting…',
  ConnectionStatus(connection: Tox_Connection.TOX_CONNECTION_TCP) =>
    'Online via TCP relay',
  ConnectionStatus() => 'Online',
};

/// One line for all accounts, e.g. for the background service's notification.
String connectionSummaryText(Iterable<ConnectionStatus>? statuses) {
  final all = statuses?.toList() ?? const [];
  if (all.length <= 1) {
    return connectionStatusText(all.firstOrNull);
  }
  if (all.where((s) => s.proxyProblem != null).firstOrNull case final s?) {
    return connectionStatusText(s);
  }
  final online = all.where((s) => s.online).length;
  return online == all.length
      ? '$online accounts online'
      : '$online of ${all.length} accounts online';
}

/// Each account's status, when there's more than one.
List<String> connectionStatusLines(
  ConnectionStatuses statuses,
  Map<Id<Profiles>, String> names,
) => statuses.length < 2
    ? const []
    : [
        for (final MapEntry(:key, :value) in statuses.entries)
          '${names[key] ?? key.value}: ${connectionStatusText(value)}',
      ];
