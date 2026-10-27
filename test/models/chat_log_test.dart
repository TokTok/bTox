import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/messages/message_format.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/persistence.dart' show FileState;
import 'package:btox/sync/event.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_message_format.dart';

final _home = PublicKey(Uint8List(32)..fillRange(0, 32, 1));
final _carol = PublicKey(Uint8List(32)..fillRange(0, 32, 3));
final _graph = GraphId.account(_home);

(EventId, SyncEvent) _event(
  int rank,
  int time,
  EventContent content, [
  List<EventId> parents = const [],
]) {
  final event = SyncEvent(
    graph: _graph,
    author: _home,
    parents: parents,
    rank: rank,
    time: time,
    content: content,
  );
  return (EventId.of(event.encode()), event);
}

Received _received(Uint8List message, {PublicKey? from}) => Received(
  from: from,
  sender: 'Bob',
  message: message,
  kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
);

List<String> _texts(ChatLog log, List<(EventId, SyncEvent)> events) => [
  for (final entry in log.update(events)) (entry.content as TextContent).text,
];

void main() {
  test('ours says when it arrived', () {
    final send = _event(
      0,
      50,
      Send(
        sender: 'Me',
        message: utf8.encode('hi'),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      ),
    );
    final [entry] = ChatLog(MessageFormats.none)
        .update([send, _event(1, 70, Delivered(intent: send.$1))]);
    expect(
      entry.delivered,
      DateTime.fromMillisecondsSinceEpoch(70, isUtc: true),
    );
  });

  test('shows events as they come like all at once', () {
    final send = _event(
      0,
      50,
      Send(
        sender: 'Me',
        message: utf8.encode('hi'),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      ),
    );
    final events = [
      send,
      _event(1, 10, _received(utf8.encode('late clock')), [send.$1]),
      _event(1, 60, const Notice(text: 'Bob joined'), [send.$1]),
      _event(2, 70, Delivered(intent: send.$1)),
      _event(3, 80, _received(utf8.encode('newest'))),
      _event(3, 10, _received(utf8.encode('slow')), [send.$1]),
    ];
    final log = ChatLog(MessageFormats.none);
    for (var i = 1; i <= events.length; i++) {
      final prefix = events.sublist(0, i);
      expect(log.update(prefix), ChatLog(MessageFormats.none).update(prefix));
    }
    // Later events placed by the effective time of earlier ones: these two
    // tie at 50, so their IDs order them, not their own times.
    late List<(EventId, SyncEvent)> tied;
    for (var t = 20; ; t++) {
      tied = [
        for (final time in [t, t + 20])
          _event(4, time, _received(utf8.encode('tied')), [events[5].$1]),
      ];
      if (tied[0].$1.compareTo(tied[1].$1) > 0) {
        break;
      }
    }
    final later = [...events, ...tied];
    expect(log.update(later), ChatLog(MessageFormats.none).update(later));

    // Older history arriving later, and events going away.
    final older = _event(0, 0, const Notice(text: 'older'));
    for (final next in [
      [older, ...events],
      events.sublist(1),
    ]) {
      expect(log.update(next), ChatLog(MessageFormats.none).update(next));
    }
    expect(_texts(ChatLog(MessageFormats.none), events), [
      'hi',
      'late clock',
      'Bob joined',
      'slow',
      'newest',
    ]);
  });

  test('shows geo text as a location', () {
    final events = [_event(0, 0, _received(utf8.encode('geo:-33.9,18.4')))];
    expect(
      ChatLog(MessageFormats.none).update(events).single.content,
      const LocationContent(latitude: -33.9, longitude: 18.4),
    );
  });

  test('reads friends\' messages in the formats turned on', () {
    final events = [
      _event(0, 0, _received(FakeMessageFormat.encode('hi', '7'))),
      _event(1, 1, _received(FakeMessageFormat.encode('hi', '7'))),
      _event(2, 2, _received(FakeMessageFormat.encode('again', '8'))),
      _event(
        3,
        3,
        _received(FakeMessageFormat.encode('in a group', '7'), from: _carol),
      ),
    ];
    final raw = [
      for (final (_, event) in events)
        utf8.decode((event.content as Received).message, allowMalformed: true),
    ];
    // Sent again with the same key, a message shows once.
    expect(_texts(ChatLog(withFakeFormat), events), ['hi', 'again', raw[3]]);
    // Ours are plain text, whatever they look like.
    final ours = _event(
      4,
      4,
      Send(
        sender: 'Me',
        message: FakeMessageFormat.encode('mine', '9'),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      ),
    );
    expect(_texts(ChatLog(withFakeFormat), [ours]), ['mine#9']);
    expect(_texts(ChatLog(MessageFormats.none), events), raw);
  });

  test('shows how far files offered to the home device got', () {
    FileState? stateOf(List<(EventId, SyncEvent)> events) =>
        ChatLog(MessageFormats.none).update(events).single.file?.state;
    final offer = _event(
      0,
      0,
      const FileStarted(
        sender: 'Bob',
        name: 'cat.png',
        size: 3,
        incoming: true,
      ),
    );
    (EventId, SyncEvent) answer(int rank, {required bool accepted}) => _event(
      rank,
      rank,
      FileAnswered(file: offer.$1, accepted: accepted),
      [offer.$1],
    );
    final done = _event(1, 1, FileEnded(file: offer.$1, ok: true), [offer.$1]);

    expect(stateOf([offer]), FileState.offered);
    expect(stateOf([offer, answer(1, accepted: true)]), FileState.active);
    expect(stateOf([offer, answer(1, accepted: false)]), FileState.cancelled);
    // An answer after it ended changes nothing.
    expect(stateOf([offer, done, answer(2, accepted: false)]), FileState.done);
  });
}
