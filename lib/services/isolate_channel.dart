import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

// How long between asks of a publisher that hasn't answered.
const _subscribeRetry = Duration(milliseconds: 500);

/// What the publisher registered as [portName], which another isolate may
/// run, sends the port [request] gives it: first `['hello', its control
/// port, message]`, then `[update, message]`, each read by [parse]. Null
/// while no publisher runs. [whenMissing] is called while none answers for
/// [missingAfter], as when the service stopped just as this subscriber
/// started. What [cancel] gives is sent when the stream is no longer
/// listened to.
Stream<T?> watchPublisher<T>(
  String portName, {
  required List<Object?> Function(SendPort port) request,
  required String update,
  required T Function(Object? message) parse,
  List<Object?> Function(SendPort port)? cancel,
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
    IsolateNameServer.lookupPortByName(portName)?.send(request(port.sendPort));
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
          case [final String kind, final message] when kind == update:
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
      if (cancel != null) {
        IsolateNameServer.lookupPortByName(portName)
            ?.send(cancel(port.sendPort));
      }
      port.close();
    },
  );
  return controller.stream;
}
