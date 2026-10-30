import 'package:btox/models/connection_status.dart';
import 'package:btox/models/id.dart';
import 'package:btox/services/isolate_channel.dart';

const _portName = 'btox-connection-status';
const _topic = 'status';

ConnectionStatuses? _parse(Map<int, List<Object?>>? message) => message == null
    ? null
    : {
        for (final MapEntry(:key, :value) in message.entries)
          Id(key): ConnectionStatus.fromMessage(value),
      };

Map<int, List<Object?>>? _message(ConnectionStatuses? statuses) =>
    statuses == null
    ? null
    : {
        for (final MapEntry(:key, :value) in statuses.entries)
          key.value: value.toMessage(),
      };

final class ConnectionStatusPublisher {
  late final Publisher _publisher;
  ConnectionStatuses? _statuses;

  ConnectionStatusPublisher({void Function(int count)? onSubscribersChanged}) {
    _publisher = Publisher(
      _portName,
      current: (_) => _message(_statuses),
      subscribersChanged: onSubscribersChanged == null
          ? null
          : (_, count) => onSubscribersChanged(count),
    );
  }

  void publish(ConnectionStatuses? statuses) {
    _statuses = statuses;
    _publisher.publish(_topic, () => _message(statuses));
  }

  void close() => _publisher.close();
}

Stream<ConnectionStatuses?> watchConnectionStatuses({
  void Function()? whenMissing,
  Duration missingAfter = const Duration(seconds: 2),
}) => watchPublisher<ConnectionStatuses?>(
  _portName,
  _topic,
  (message) => _parse(message as Map<int, List<Object?>>?),
  whenMissing: whenMissing,
  missingAfter: missingAfter,
);
