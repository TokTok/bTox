import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:btox/ffi/toxcore.dart';

const _portName = 'btox-connection-status';

Tox_Connection? _parse(String? name) =>
    name == null ? null : Tox_Connection.values.byName(name);

final class ConnectionStatusPublisher {
  final _port = ReceivePort('connection status');
  final _subscribers = <SendPort>{};
  Tox_Connection? _status;

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
            _status?.name,
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

  void publish(Tox_Connection? status) {
    _status = status;
    for (final subscriber in _subscribers) {
      subscriber.send(['status', status?.name]);
    }
  }

  void close() {
    IsolateNameServer.removePortNameMapping(_portName);
    _port.close();
  }
}

Stream<Tox_Connection?> watchConnectionStatus() {
  late final StreamController<Tox_Connection?> controller;
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
          case ['hello', SendPort publisherControl, String? name]:
            retry?.cancel();
            if (publisherControl != publisher) {
              publisher = publisherControl;
              Isolate(publisherControl).addOnExitListener(
                port.sendPort,
                response: ['exited', publisherControl],
              );
            }
            controller.add(_parse(name));
          case ['status', String? name]:
            controller.add(_parse(name));
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
