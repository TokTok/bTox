import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:btox/models/connection_status.dart';
import 'package:btox/models/id.dart';

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

Stream<ConnectionStatuses?> watchConnectionStatuses() {
  late final StreamController<ConnectionStatuses?> controller;
  late final ReceivePort port;
  SendPort? publisher;
  Timer? retry;

  // Resends until the publisher answers: after it exits, the name server may
  // still hold its dead port until a new publisher replaces it.
  void subscribe() {
    retry?.cancel();
    IsolateNameServer.lookupPortByName(_portName)
        ?.send([port.sendPort, Isolate.current.controlPort]);
    retry = Timer(const Duration(milliseconds: 500), subscribe);
  }

  controller = StreamController(
    onListen: () {
      port = ReceivePort('connection status subscriber');
      port.listen((message) {
        switch (message) {
          case [
            'hello',
            SendPort publisherControl,
            Map<int, List<Object?>>? statuses,
          ]:
            retry?.cancel();
            if (publisherControl != publisher) {
              publisher = publisherControl;
              Isolate(publisherControl).addOnExitListener(
                port.sendPort,
                response: ['exited', publisherControl],
              );
            }
            controller.add(_parse(statuses));
          case ['status', Map<int, List<Object?>>? statuses]:
            controller.add(_parse(statuses));
          case ['exited', SendPort publisherControl]:
            if (publisherControl == publisher) {
              publisher = null;
              controller.add(null);
              subscribe();
            }
        }
      });
      subscribe();
    },
    onCancel: () {
      retry?.cancel();
      port.close();
    },
  );
  return controller.stream;
}
