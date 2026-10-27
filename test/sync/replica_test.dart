import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/models/crypto.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/replica.dart';
import 'package:btox/sync/session.dart' as session;
import 'package:btox/sync/session_message.dart';
import 'package:btox/sync/store.dart';
import 'package:flutter_test/flutter_test.dart';

final _home = PublicKey(Uint8List(32)..fillRange(0, 32, 1));
final _bob = PublicKey(Uint8List(32)..fillRange(0, 32, 2));
final _device = PublicKey(Uint8List(32)..fillRange(0, 32, 3));

final _account = GraphId.account(_home);
final _chat = GraphId.friend(_home, _bob);

/// Adds an event to the home's [store] after its heads.
Uint8List _write(EventStore store, GraphId graph, EventContent content) {
  final (_, _, bytes) = store.author(
    graph,
    _home,
    DateTime.fromMillisecondsSinceEpoch(0),
    content,
  );
  store.insert(bytes);
  return bytes;
}

/// Up to [limit] ancestors of [before] in [graph], newest first, as the home
/// device answers History.
List<Uint8List> _history(
  EventStore home,
  GraphId graph,
  List<EventId> before,
  int limit,
) {
  final queue = SplayTreeSet<(int, EventId)>(
    (a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : b.$2.compareTo(a.$2),
  );
  final seen = <EventId>{};
  void push(EventId id) {
    if (home[id] case final event? when seen.add(id)) {
      queue.add((event.rank, id));
    }
  }

  for (final id in before) {
    home[id]?.parents.forEach(push);
  }
  final found = <Uint8List>[];
  while (found.length < limit && queue.isNotEmpty) {
    final (_, id) = queue.first;
    queue.remove(queue.first);
    home[id]!.parents.forEach(push);
    if (home[id]!.graph == graph) {
      found.add(home.bytes(id)!);
    }
  }
  return found;
}

/// Runs a session until neither side has anything left to say, returning
/// how many round trips it took. The home answers from its store, and takes
/// the events it's sent.
int _converse(EventStore home, Replica replica, List<SessionMessage> start) {
  var toReplica = start;
  var rounds = 0;
  while (toReplica.isNotEmpty) {
    rounds++;
    final next = <SessionMessage>[];
    for (final message in toReplica) {
      for (final reply in replica.received(message).replies) {
        switch (reply) {
          case Events(:final events):
            events.forEach(home.insert);
          case History(:final graph, :final before, :final limit):
            next.addAll(session.batches(_history(home, graph, before, limit)));
          default:
            next.addAll(session.answer(home, reply));
        }
      }
    }
    toReplica = next;
  }
  return rounds;
}

void main() {
  test('keeps the account whole and conversations from their latest', () {
    final home = EventStore();
    for (final name in ['Bo', 'Bob']) {
      _write(
        home,
        _account,
        FactContent(subject: Subject.friend(_bob), value: FactValue.name(name)),
      );
    }
    _write(home, _chat, const Notice(text: 'Bob joined'));
    final replica = Replica(device: _device, home: _home);

    // Nothing before the home's Hello.
    expect(replica.received(session.summary(home)).replies, isEmpty);

    _converse(home, replica, [Replica.hello, session.summary(home)]);
    expect(replica.state.friends[_bob]!.name, 'Bob');
    expect(replica.store.eventsIn(_chat), hasLength(1));

    // A conversation's latest page is asked for once per session.
    final later = _write(home, _chat, const Notice(text: 'Bob left'));
    final asked = replica.received(Events([later])).replies;
    expect(asked, isEmpty);
    replica.offline();
    replica.received(Replica.hello);
    expect(replica.received(Events([later])).replies, isEmpty);
    final newer = _write(home, _chat, const Notice(text: 'Bob is back'));
    expect(replica.received(Events([newer])).replies, [
      History(graph: _chat, before: [EventId.of(newer)], limit: historyPage),
    ]);
  });

  test('gets a parent further back than History goes', () {
    final home = EventStore();
    final early = EventStore();
    final other = PublicKey(Uint8List(32)..fillRange(0, 32, 4));
    for (var i = 0; i < 600; i++) {
      final bytes = _write(
        home,
        _account,
        FactContent(subject: Subject.friend(_bob), value: FactValue.name('$i')),
      );
      if (i < 10) {
        early.insert(bytes);
      }
    }
    final replica = Replica(device: _device, home: _home);
    _converse(home, replica, [Replica.hello, session.summary(home)]);

    // Another device, offline long, writes after the home's 10th event.
    final (missed, _, bytes) = early.author(
      _account,
      other,
      DateTime.fromMillisecondsSinceEpoch(0),
      const FactContent(
        subject: Subject.account(),
        value: FactValue.name('Me'),
      ),
    );
    home.insert(bytes);
    final joined = _write(home, _account, const Notice(text: 'merged'));
    _converse(home, replica, [
      Events([joined]),
    ]);

    expect(replica.store.contains(missed), isTrue);
    expect(replica.state.name, 'Me');
  });

  test('goes by its nickname in chats that give it one', () {
    final home = EventStore();
    final group = GroupChatId(Uint8List(32));
    _write(
      home,
      _account,
      const FactContent(
        subject: Subject.account(),
        value: FactValue.name('Me'),
      ),
    );
    for (final value in [FactValue.joined(true), FactValue.selfName('iphy')]) {
      _write(
        home,
        _account,
        FactContent(subject: Subject.chat(GroupChat(group)), value: value),
      );
    }
    final replica = Replica(device: _device, home: _home);
    _converse(home, replica, [Replica.hello, session.summary(home)]);

    expect(replica.selfNameIn(GraphId.group(group)), 'iphy');
    expect(replica.selfNameIn(_chat), 'Me');
  });

  test('fills the gap left while offline, however long', () {
    final home = EventStore();
    _write(home, _chat, const Notice(text: '0'));
    final replica = Replica(device: _device, home: _home);
    _converse(home, replica, [Replica.hello, session.summary(home)]);

    replica.offline();
    for (var i = 1; i <= 120; i++) {
      _write(home, _chat, Notice(text: '$i'));
    }
    _converse(home, replica, [Replica.hello, session.summary(home)]);
    expect(replica.store.eventsIn(_chat), hasLength(121));
    expect(replica.store.headsOf(_chat), home.headsOf(_chat));
  });

  test('catches up on a new Hello without going offline', () {
    final home = EventStore();
    _write(home, _chat, const Notice(text: '0'));
    final replica = Replica(device: _device, home: _home);
    _converse(home, replica, [Replica.hello, session.summary(home)]);

    // Written while this device wasn't allowed, so never pushed to it.
    for (var i = 1; i <= 3; i++) {
      _write(home, _chat, Notice(text: '$i'));
    }
    _converse(home, replica, [Replica.hello, session.summary(home)]);
    expect(replica.store.eventsIn(_chat), hasLength(4));
  });

  test('a new conversation starts from its latest page', () {
    final home = EventStore();
    for (var i = 0; i < 120; i++) {
      _write(home, _chat, Notice(text: '$i'));
    }
    final replica = Replica(device: _device, home: _home);
    _converse(home, replica, [Replica.hello, session.summary(home)]);
    expect(replica.store.eventsIn(_chat), hasLength(1 + historyPage));
  });

  test('gets a long account in a few round trips', () {
    final home = EventStore();
    for (var i = 0; i < 1200; i++) {
      _write(
        home,
        _account,
        FactContent(subject: Subject.friend(_bob), value: FactValue.name('$i')),
      );
    }
    final replica = Replica(device: _device, home: _home);
    final rounds = _converse(home, replica, [
      Replica.hello,
      session.summary(home),
    ]);
    expect(replica.store.eventsIn(_account), hasLength(1200));
    expect(replica.state.friends[_bob]!.name, '1199');
    expect(rounds, lessThan(10));
  });

  test("this device's events reach the home", () {
    final home = EventStore();
    final hello = _write(home, _chat, const Notice(text: 'hi'));
    final replica = Replica(device: _device, home: _home);
    _converse(home, replica, [Replica.hello, session.summary(home)]);

    final send = Send(
      sender: 'Me',
      message: utf8.encode('live'),
      kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
    );
    final live = replica.author(
      _chat,
      DateTime.fromMillisecondsSinceEpoch(1),
      send,
    );
    expect(live.$2.author, _device);
    expect(live.$2.parents, [EventId.of(hello)]);
    final push = replica.written(live);
    expect(push, [
      Events([live.$3]),
    ]);
    home.insert(live.$3);

    // Outside a session, the next one's summaries carry it.
    replica.offline();
    final offline = replica.author(
      _chat,
      DateTime.fromMillisecondsSinceEpoch(2),
      send,
    );
    expect(replica.written(offline), isEmpty);
    expect(offline.$2.parents, [live.$1]);
    _converse(home, replica, [Replica.hello, session.summary(home)]);
    expect(home.contains(live.$1), isTrue);
    expect(home.contains(offline.$1), isTrue);
  });
}
