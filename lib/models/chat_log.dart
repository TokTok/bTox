import 'package:btox/messages/message_format.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/persistence.dart' show FileState;
import 'package:btox/sync/event.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/sync/store.dart';

/// The key [formats] give a message, which stays the same when it's sent
/// again.
MessageKey? keyOf(EventContent content, MessageFormats formats) =>
    switch (content) {
      Received(from: null, :final message) => formats.keyOf(
        message,
        friend: true,
      ),
      _ => null,
    };

/// Whether [content] is someone else's message or file, which counts as
/// unread until read and notifies.
bool isIncoming(EventContent content) => switch (content) {
  Received() || FileStarted(incoming: true) => true,
  _ => false,
};

/// A message a chat's notification lists, with its [sender] where that isn't
/// the chat's friend, as in a group.
typedef NotifiedMessage = ({String? sender, String text, DateTime time});

/// Whether [text] names one of [names], as a word, in any case.
bool mentions(String text, Iterable<String> names) => names.any(
  (name) =>
      name.isNotEmpty &&
      RegExp(
        '(?<![\\p{L}\\p{N}_])${RegExp.escape(name)}(?![\\p{L}\\p{N}_])',
        caseSensitive: false,
        unicode: true,
      ).hasMatch(text),
);

/// Of [messages], those that notify at [now] in a chat [mute] mutes: all
/// where it doesn't hold, else those naming one of [names] where it lets
/// mentions through.
List<NotifiedMessage> notifying(
  List<NotifiedMessage> messages,
  Mute? mute,
  DateTime now,
  Iterable<String> names,
) => switch (mute) {
  final mute? when mute.holdsAt(now) =>
    mute.mentions
        ? [
            for (final message in messages)
              if (mentions(message.text, names)) message,
          ]
        : const [],
  _ => messages,
};

/// What a notification of incoming [content] says, without its sender.
String notificationText(EventContent content, MessageFormats formats) =>
    switch (content) {
      Received(:final from, :final message) =>
        formats.read(message, friend: from == null).text,
      FileStarted(:final name) => '📎 $name',
      _ => '',
    };

/// Spots messages that repeat an earlier one: the first message with a key
/// shows, and later ones with it don't, aren't unread and don't notify.
final class Repeats {
  final _seen = <MessageKey>{};

  bool isRepeat(MessageKey? key) => key != null && !_seen.add(key);
}

/// Spots messages that repeat an earlier one of their chat in a store,
/// whatever order they came in: it keeps the first message with each key
/// of each chat, reading the chat's events as they're added.
final class EarlierRepeats {
  final EventStore _store;
  MessageFormats? _formats;
  final _first = <GraphId, Map<MessageKey, (int, EventId)>>{};
  // How many of each chat's events have been read.
  final _read = <GraphId, int>{};

  EarlierRepeats(this._store);

  /// Whether [event] repeats an earlier message of its chat as [formats]
  /// read them.
  bool repeats(EventId id, SyncEvent event, MessageFormats formats) {
    if (formats != _formats) {
      _formats = formats;
      _first.clear();
      _read.clear();
    }
    final key = keyOf(event.content, formats);
    if (key == null) {
      return false;
    }
    final graph = event.graph;
    final first = _first.putIfAbsent(graph, () => {});
    for (final (earlierId, earlier) in _store.eventsFrom(
      graph,
      _read[graph] ?? 0,
    )) {
      if (keyOf(earlier.content, formats) case final earlierKey?) {
        if (first[earlierKey] case final known?
            when compareRanks(known, (earlier.rank, earlierId)) < 0) {
          continue;
        }
        first[earlierKey] = (earlier.rank, earlierId);
      }
    }
    _read[graph] = _store.countIn(graph);
    return compareRanks(first[key]!, (event.rank, id)) < 0;
  }

  /// Forgets [graph]'s messages, as its store did.
  void forget(GraphId graph) {
    _first.remove(graph);
    _read.remove(graph);
  }
}

typedef _Placed = ({EventId id, SyncEvent event, int time});

/// A chat's entries, from its events in display order: by rank, then
/// effective time, then ID. An event's effective time is never before its
/// parents', so a fast clock can't move it back in history. Events that come
/// after those already shown are added, and anything else shows them again.
final class ChatLog {
  final MessageFormats _formats;
  final _effective = <EventId, int>{};
  final _index = <EventId, int>{};
  var _entries = <ChatEntry>[];
  var _shown = const <ChatEntry>[];
  var _repeats = Repeats();
  _Placed? _last;

  ChatLog(this._formats);

  List<ChatEntry> update(List<(EventId, SyncEvent)> events) {
    final fresh = [
      for (final e in events)
        if (!_effective.containsKey(e.$1)) e,
    ];
    var placed = _place(fresh);
    final last = _last;
    if (events.length != _effective.length + fresh.length ||
        (last != null &&
            placed.isNotEmpty &&
            _compare(placed.first, last) < 0)) {
      _effective.clear();
      _index.clear();
      _entries = [];
      _repeats = Repeats();
      _last = null;
      placed = _place(events);
    } else if (placed.isEmpty) {
      return _shown;
    }
    for (final p in placed) {
      _effective[p.id] = p.time;
      _add(p.id, p.event);
    }
    _last = placed.lastOrNull;
    return _shown = List.unmodifiable(_entries);
  }

  List<_Placed> _place(List<(EventId, SyncEvent)> events) {
    final byRank = events.toList()
      ..sort((a, b) {
        final rank = a.$2.rank.compareTo(b.$2.rank);
        return rank != 0 ? rank : a.$1.compareTo(b.$1);
      });
    final times = <EventId, int>{};
    final placed = <_Placed>[];
    for (final (id, event) in byRank) {
      var time = event.time;
      for (final parent in event.parents) {
        if ((times[parent] ?? _effective[parent]) case final t? when t > time) {
          time = t;
        }
      }
      times[id] = time;
      placed.add((id: id, event: event, time: time));
    }
    return placed..sort(_compare);
  }

  static int _compare(_Placed a, _Placed b) {
    final rank = a.event.rank.compareTo(b.event.rank);
    if (rank != 0) {
      return rank;
    }
    final time = a.time.compareTo(b.time);
    return time != 0 ? time : a.id.compareTo(b.id);
  }

  void _add(EventId id, SyncEvent event) {
    final entry = entryOf(id, event, _formats);
    if (entry != null && !_repeats.isRepeat(keyOf(event.content, _formats))) {
      _index[id] = _entries.length;
      _entries.add(entry);
    }
    void update(EventId target, ChatEntry Function(ChatEntry) change) {
      if (_index[target] case final i?) {
        _entries[i] = change(_entries[i]);
      }
    }

    switch (event.content) {
      case Sent(:final intent):
        update(intent, (e) => e.copyWith(state: ChatContentState.sent));
      case Delivered(:final intent):
        update(
          intent,
          (e) => e.copyWith(
            state: ChatContentState.delivered,
            delivered: _timeOf(event),
          ),
        );
      case FileEnded(:final file, :final ok):
        update(
          file,
          (e) => e.copyWith(
            delivered: ok && e.mine ? _timeOf(event) : null,
            file: FileProgress(
              state: ok ? FileState.done : FileState.cancelled,
            ),
          ),
        );
      default:
        break;
    }
  }
}

DateTime _timeOf(SyncEvent event) =>
    DateTime.fromMillisecondsSinceEpoch(event.time, isUtc: true);

/// The entry [event] shows as in its chat, if it shows as one, with friends'
/// messages read in [formats].
ChatEntry? entryOf(EventId id, SyncEvent event, MessageFormats formats) {
  final timestamp = _timeOf(event);
  return switch (event.content) {
    // Only group senders have keys. In friend chats it's the friend.
    Received(:final from, :final sender, :final message) => ChatEntry(
      event: id,
      sender: from == null ? null : sender,
      from: from,
      mine: false,
      content: contentOfMessage(
        formats.read(message, friend: from == null).text,
      ),
      timestamp: timestamp,
    ),
    Send(:final message) => ChatEntry(
      event: id,
      mine: true,
      content: contentOfMessage(plainText(message)),
      timestamp: timestamp,
      state: ChatContentState.pending,
    ),
    Notice(:final text) => ChatEntry(
      event: id,
      mine: false,
      notice: true,
      content: TextContent(text: text),
      timestamp: timestamp,
    ),
    FileStarted(:final name, :final size, :final incoming) => ChatEntry(
      event: id,
      mine: !incoming,
      content: FileContent(name: name, size: size),
      timestamp: timestamp,
      file: FileProgress(state: incoming ? FileState.offered : null),
    ),
    _ => null,
  };
}
