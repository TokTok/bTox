import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:btox/logger.dart';

const _logger = Logger(['IsolateChannel']);

// How long between asks of a publisher that hasn't answered.
const _subscribeRetry = Duration(milliseconds: 500);

/// Registered as [portName], sends what it publishes under each topic to the
/// isolates whose [watchPublisher] subscribed to it, until they exit or
/// unsubscribe. Other messages to its port go to [onMessage].
final class Publisher {
  final String portName;
  final Object? Function(String topic) _current;
  final void Function(String topic, int count)? _subscribersChanged;
  final void Function(Object? message)? _onMessage;
  final _port = ReceivePort('publisher');
  final _topics = <String, Set<SendPort>>{};
  // The subscribers of each isolate, by its control port: an isolate's exit
  // is told once, so all of them go then.
  final _isolates = <SendPort, Set<SendPort>>{};

  /// What a topic has now is [current]'s, which a new subscriber gets first.
  Publisher(
    this.portName, {
    required Object? Function(String topic) current,
    void Function(String topic, int count)? subscribersChanged,
    void Function(Object? message)? onMessage,
  }) : _current = current,
       _subscribersChanged = subscribersChanged,
       _onMessage = onMessage {
    _port.listen((message) {
      try {
        _receive(message);
      } on Exception catch (e) {
        _logger.w('Failed to handle $message: $e');
      }
    });
    IsolateNameServer.removePortNameMapping(portName);
    IsolateNameServer.registerPortWithName(_port.sendPort, portName);
  }

  void _receive(Object? message) {
    switch (message) {
      case ['subscribe', String topic, SendPort subscriber, SendPort control]:
        if ((_topics[topic] ??= {}).add(subscriber)) {
          if (_isolates[control] case final subscribers?) {
            subscribers.add(subscriber);
          } else {
            _isolates[control] = {subscriber};
            Isolate(
              control,
            ).addOnExitListener(_port.sendPort, response: ['exited', control]);
          }
          _subscribersChanged?.call(topic, _topics[topic]!.length);
        }
        subscriber.send([
          'hello',
          Isolate.current.controlPort,
          _current(topic),
        ]);
      case ['unsubscribe', SendPort subscriber]:
        _unsubscribe(subscriber);
      case ['exited', SendPort control]:
        _isolates.remove(control)?.forEach(_unsubscribe);
      default:
        if (_onMessage case final onMessage?) {
          onMessage(message);
        } else {
          _logger.w('Unknown message: $message');
        }
    }
  }

  void _unsubscribe(SendPort subscriber) {
    for (final MapEntry(key: topic, value: subscribers) in _topics.entries) {
      if (subscribers.remove(subscriber)) {
        _subscribersChanged?.call(topic, subscribers.length);
      }
    }
  }

  /// Sends each of [topic]'s subscribers a [message] of its own, as one with
  /// transferable data can go to only one.
  void publish(String topic, Object? Function() message) {
    for (final subscriber in _topics[topic] ?? const <SendPort>{}) {
      subscriber.send([topic, message()]);
    }
  }

  void close() {
    IsolateNameServer.removePortNameMapping(portName);
    _port.close();
  }
}

/// What the [Publisher] registered as [portName], which another isolate may
/// run, publishes as [topic], each read by [parse]. Null while no publisher
/// runs. [whenMissing] is called while none answers for [missingAfter], as
/// when the service stopped just as this subscriber started. With [leave],
/// it unsubscribes when no longer listened to, else when its isolate exits.
Stream<T?> watchPublisher<T>(
  String portName,
  String topic,
  T Function(Object? message) parse, {
  bool leave = false,
  void Function()? whenMissing,
  Duration missingAfter = const Duration(seconds: 2),
}) {
  late final StreamController<T?> controller;
  late final ReceivePort port;
  SendPort? publisher;
  Timer? retry;
  var unanswered = Duration.zero;

  // Resends until the publisher answers: after it exits, the name server may
  // still hold its dead port until a new publisher replaces it.
  void subscribe() {
    retry?.cancel();
    if (unanswered >= missingAfter) {
      unanswered = Duration.zero;
      whenMissing?.call();
    }
    IsolateNameServer.lookupPortByName(
      portName,
    )?.send(['subscribe', topic, port.sendPort, Isolate.current.controlPort]);
    retry = Timer(_subscribeRetry, () {
      unanswered += _subscribeRetry;
      subscribe();
    });
  }

  controller = StreamController(
    onListen: () {
      port = ReceivePort(portName);
      port.listen((message) {
        switch (message) {
          case ['hello', SendPort publisherControl, final message]:
            retry?.cancel();
            unanswered = Duration.zero;
            if (publisherControl != publisher) {
              publisher = publisherControl;
              Isolate(publisherControl).addOnExitListener(
                port.sendPort,
                response: ['exited', publisherControl],
              );
            }
            controller.add(parse(message));
          case [final String kind, final message] when kind == topic:
            controller.add(parse(message));
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
      if (leave) {
        IsolateNameServer.lookupPortByName(portName)
            ?.send(['unsubscribe', port.sendPort]);
      }
      port.close();
    },
  );
  return controller.stream;
}
