import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:btox/models/connection_status.dart';
import 'package:btox/models/id.dart';
import 'package:btox/services/isolate_channel.dart';

const _portName = 'btox-connection-status';

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
  final _port = ReceivePort('connection status');
  final _subscribers = <SendPort>{};
  ConnectionStatuses? _statuses;

  final void Function(int count)? onSubscribersChanged;

  ConnectionStatusPublisher({this.onSubscribersChanged}) {
    _port.listen((message) {
      switch (message) {
        case [SendPort subscriber, SendPort subscriberControl]:
          if (_subscribers.add(subscriber)) {
            Isolate(subscriberControl)
                .addOnExitListener(_port.sendPort, response: subscriber);
            onSubscribersChanged?.call(_subscribers.length);
          }
          subscriber.send([
            'hello',
            Isolate.current.controlPort,
            _message(_statuses),
          ]);
        case SendPort exitedSubscriber:
          if (_subscribers.remove(exitedSubscriber)) {
            onSubscribersChanged?.call(_subscribers.length);
          }
      }
    });
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(_port.sendPort, _portName);
  }

  void publish(ConnectionStatuses? statuses) {
    _statuses = statuses;
    for (final subscriber in _subscribers) {
      subscriber.send(['status', _message(statuses)]);
    }
  }

  void close() {
    IsolateNameServer.removePortNameMapping(_portName);
    _port.close();
  }
}

Stream<ConnectionStatuses?> watchConnectionStatuses({
  void Function()? whenMissing,
  Duration missingAfter = const Duration(seconds: 2),
}) => watchPublisher<ConnectionStatuses?>(
  _portName,
  request: (port) => [port, Isolate.current.controlPort],
  update: 'status',
  parse: (message) => _parse(message as Map<int, List<Object?>>?),
  whenMissing: whenMissing,
  missingAfter: missingAfter,
);
