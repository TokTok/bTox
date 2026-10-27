import 'dart:isolate';

import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/connection_status.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/services/connection_status_channel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Publishes a status, then exits once told to, without closing the publisher.
void _publisher((Tox_Connection, SendPort) args) {
  final (connection, ready) = args;
  ConnectionStatusPublisher().publish({
    Id<Profiles>(1): ConnectionStatus(connection: connection),
  });
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
  watchConnectionStatuses().first.then((_) {
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

  late List<ConnectionStatuses?> statuses;

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

    final subscription = watchConnectionStatuses().listen(statuses.add);
    addTearDown(subscription.cancel);
    await untilReceived(1);

    exit.send(null);
    await untilReceived(2);

    const tcp = ConnectionStatus(connection: Tox_Connection.TOX_CONNECTION_TCP);
    final publisher = ConnectionStatusPublisher()
      ..publish({Id<Profiles>(1): tcp});
    addTearDown(publisher.close);
    await untilReceived(3);

    const unreachable = ConnectionStatus(
      connection: Tox_Connection.TOX_CONNECTION_NONE,
      proxyProblem: ProxyProblem.unreachable,
      proxy: '127.0.0.1:9050',
    );
    publisher.publish({Id<Profiles>(1): tcp, Id<Profiles>(2): unreachable});
    await untilReceived(4);

    expect(statuses, [
      {
        Id<Profiles>(1): const ConnectionStatus(
          connection: Tox_Connection.TOX_CONNECTION_UDP,
        ),
      },
      null,
      {Id<Profiles>(1): tcp},
      {Id<Profiles>(1): tcp, Id<Profiles>(2): unreachable},
    ]);
  });

  test('with no publisher for a while, it asks for one', () async {
    var asked = 0;
    final subscription = watchConnectionStatuses(
      whenMissing: () => asked++,
      missingAfter: const Duration(milliseconds: 500),
    ).listen(statuses.add);
    addTearDown(subscription.cancel);
    while (asked == 0) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    final publisher = ConnectionStatusPublisher()..publish({});
    addTearDown(publisher.close);
    await untilReceived(1);
    asked = 0;
    await Future.delayed(const Duration(seconds: 1));
    expect(asked, 0);
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
