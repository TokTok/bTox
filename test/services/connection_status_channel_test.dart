import 'dart:isolate';

import 'package:btox/ffi/toxcore.dart';
import 'package:btox/services/connection_status_channel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Publishes a status, then exits once told to, without closing the publisher.
void _publisher((Tox_Connection, SendPort) args) {
  final (status, ready) = args;
  ConnectionStatusPublisher().publish(status);
  final exit = ReceivePort();
  ready.send(exit.sendPort);
  exit.first.then((_) => Isolate.exit());
}

Future<SendPort> _spawnPublisher(Tox_Connection status) async {
  final ready = ReceivePort();
  await Isolate.spawn(_publisher, (status, ready.sendPort));
  return await ready.first as SendPort;
}

/// Subscribes, then exits once told to, without cancelling the subscription.
void _subscriber(SendPort ready) {
  watchConnectionStatus().first.then((_) {
    final exit = ReceivePort();
    ready.send(exit.sendPort);
    exit.first.then((_) => Isolate.exit());
  });
}

Future<SendPort> _spawnSubscriber() async {
  final ready = ReceivePort();
  await Isolate.spawn(_subscriber, ready.sendPort);
  return await ready.first as SendPort;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Tox_Connection?> statuses;

  Future<void> untilReceived(int count) async {
    while (statuses.length < count) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() {
    statuses = [];
  });

  test('publisher exit reads as null until a new one appears', () async {
    final exit = await _spawnPublisher(Tox_Connection.TOX_CONNECTION_UDP);

    final subscription = watchConnectionStatus().listen(statuses.add);
    addTearDown(subscription.cancel);
    await untilReceived(1);

    exit.send(null);
    await untilReceived(2);

    final publisher = ConnectionStatusPublisher()
      ..publish(Tox_Connection.TOX_CONNECTION_TCP);
    addTearDown(publisher.close);
    await untilReceived(3);

    publisher.publish(Tox_Connection.TOX_CONNECTION_UDP);
    await untilReceived(4);

    expect(statuses, [
      Tox_Connection.TOX_CONNECTION_UDP,
      null,
      Tox_Connection.TOX_CONNECTION_TCP,
      Tox_Connection.TOX_CONNECTION_UDP,
    ]);
  });

  test('publisher counts subscribers until their isolates exit', () async {
    final counts = <int>[];
    final publisher = ConnectionStatusPublisher(
      onSubscribersChanged: counts.add,
    );
    addTearDown(publisher.close);

    final exit = await _spawnSubscriber();
    expect(counts, [1]);

    exit.send(null);
    while (counts.length < 2) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    expect(counts, [1, 0]);
  });
}
