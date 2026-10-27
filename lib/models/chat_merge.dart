import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/messages/message_format.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_merge.freezed.dart';

/// How long a bot may take to relay a message.
const _relayDelay = Duration(minutes: 1);

/// One of the chats shown as one.
@freezed
abstract class MergeSide with _$MergeSide {
  const factory MergeSide({
    required GraphId graph,
    required Set<PublicKey> bots,
  }) = _MergeSide;
}

/// Chats shown as one: the chat into which they merge first, then the rest.
@freezed
abstract class ChatMerge with _$ChatMerge {
  const factory ChatMerge(List<MergeSide> sides) = _ChatMerge;
}

/// The [account]'s merges, by the chat in which they show. Merges into a
/// chat not joined, or itself merged, are left out. A relay bot's chat merged
/// with none is a merge of one.
Map<GraphId, ChatMerge> mergedChats(AccountState account) {
  final into = <ChatId, Set<PublicKey>>{};
  final merged = <ChatId, List<MergeSide>>{};
  for (final MapEntry(key: chat, value: merge) in account.merges.entries) {
    if ((account.chats[merge.into]?.joined ?? false) &&
        !account.merges.containsKey(merge.into)) {
      (into[merge.into] ??= {}).add(merge.intoBot);
      (merged[merge.into] ??= []).add(
        MergeSide(graph: chat.graph, bots: {merge.bot}),
      );
    }
  }
  return {
    for (final MapEntry(key: chat, value: sides) in merged.entries)
      chat.graph: ChatMerge([
        MergeSide(graph: chat.graph, bots: into[chat]!),
        ...sides,
      ]),
    for (final MapEntry(key: chat, value: bot) in account.relayBots.entries)
      if ((account.chats[chat]?.joined ?? false) &&
          !merged.containsKey(chat) &&
          !account.merges.containsKey(chat))
        chat.graph: ChatMerge([
          MergeSide(graph: chat.graph, bots: {bot}),
        ]),
  };
}

/// The sender and text of a relayed `<name> text`. Names may hold "> ", so
/// the longest of [names] that fits wins.
(String, String)? relayed(String text, {Iterable<String> names = const []}) {
  if (!text.startsWith('<')) {
    return null;
  }
  String? known;
  for (final name in names) {
    if (text.startsWith('<$name> ') && name.length > (known?.length ?? -1)) {
      known = name;
    }
  }
  final end = known == null ? text.indexOf('> ') : known.length + 1;
  return end > 1 ? (text.substring(1, end), text.substring(end + 2)) : null;
}

typedef SeenName = ({String name, DateTime last});

/// The names a relay [bot], last called [name], has relayed, last seen first.
@freezed
abstract class RelayedNames with _$RelayedNames {
  const factory RelayedNames({
    required PublicKey bot,
    required String name,
    required List<SeenName> seen,
  }) = _RelayedNames;
}

RelayedNames? relayedNames(
  Iterable<(EventId, SyncEvent)> events,
  PublicKey bot,
) {
  final speakers = _speakersOf(events, {bot}).toSet();
  String? botName;
  final last = <String, int>{};
  for (final (_, event) in events) {
    if (event.content case Received(:final from, :final sender, :final message)
        when from == bot) {
      botName = sender;
      if (relayed(plainText(message), names: speakers) case (final name, _)) {
        last[name] = event.time;
      }
    }
  }
  return switch (botName) {
    final name? when last.isNotEmpty => RelayedNames(
      bot: bot,
      name: name,
      seen: [
        for (final MapEntry(key: name, value: time) in last.entries)
          (name: name, last: DateTime.fromMillisecondsSinceEpoch(time)),
      ]..sort((a, b) => b.last.compareTo(a.last)),
    ),
    _ => null,
  };
}

/// [event] as a bot would relay it, to match it with its copy.
(Tox_Message_Type, String)? _said(
  SyncEvent event,
  Set<PublicKey> bots,
  MessageFormats formats,
) => switch (event.content) {
  Received(from: final from?, :final sender, :final message, :final kind) =>
    switch (formats.read(message, friend: false).text) {
      final text when bots.contains(from) => (kind, text),
      final text => (kind, '<$sender> $text'),
    },
  Send(:final sender, :final message, :final kind) => (
    kind,
    '<$sender> ${plainText(message)}',
  ),
  _ => null,
};

Iterable<String> _speakersOf(
  Iterable<(EventId, SyncEvent)> events,
  Set<PublicKey> bots,
) sync* {
  for (final (_, event) in events) {
    switch (event.content) {
      case Received(:final from, :final sender) when !bots.contains(from):
        yield sender;
      case Send(:final sender):
        yield sender;
      default:
        break;
    }
  }
}

typedef _Said = ({
  int side,
  EventId id,
  int time,
  (Tox_Message_Type, String) said,
  bool copy,
});

/// The messages of a merge that repeat one on another side: a relayed copy,
/// even where clocks put it first, or the second of two copies. One older
/// than the last starts over.
final class Echoes {
  final MessageFormats _formats;
  ChatMerge? _merge;
  final _seen = <EventId>{};
  final _waiting = <(Tox_Message_Type, String), List<_Said>>{};
  final _repeats = <EventId>{};
  // When the home device sent messages written offline, so when their copies
  // come.
  final _sentAt = <EventId, int>{};
  _Said? _last;

  Echoes(this._formats);

  Set<EventId> update(
    ChatMerge merge,
    List<Iterable<(EventId, SyncEvent)>> events,
  ) {
    var said = merge == _merge
        ? _saidIn(merge, events, fresh: true)
        : const <_Said>[];
    if (merge != _merge ||
        (said.isNotEmpty && _last != null && _bySaid(said.first, _last!) < 0)) {
      _merge = merge;
      _seen.clear();
      _waiting.clear();
      _repeats.clear();
      _sentAt.clear();
      _last = null;
      said = _saidIn(merge, events, fresh: false);
    }
    for (final current in said) {
      final unmatched = [
        for (final w in _waiting[current.said] ?? const <_Said>[])
          if (_sent(w).time >= current.time - _relayDelay.inMilliseconds)
            _sent(w),
      ];
      _waiting[current.said] = unmatched;
      final i = unmatched.indexWhere((w) => w.side != current.side);
      if (i < 0) {
        unmatched.add(current);
      } else {
        final earlier = unmatched.removeAt(i);
        _repeats.add(earlier.copy && !current.copy ? earlier.id : current.id);
      }
      _last = current;
    }
    return {..._repeats};
  }

  /// What each side's messages say, of those not seen yet if [fresh], in
  /// the order they were said.
  List<_Said> _saidIn(
    ChatMerge merge,
    List<Iterable<(EventId, SyncEvent)>> events, {
    required bool fresh,
  }) {
    final said = <_Said>[];
    for (final (side, MergeSide(:bots)) in merge.sides.indexed) {
      for (final (id, event) in events[side]) {
        if (!_seen.add(id) && fresh) {
          continue;
        }
        if (event.content case Sent(:final intent)) {
          _sentAt[intent] = event.time;
        } else if (_said(event, bots, _formats) case final message?) {
          said.add((
            side: side,
            id: id,
            time: event.time,
            said: message,
            copy: switch (event.content) {
              Received(:final from) => bots.contains(from),
              _ => false,
            },
          ));
        }
      }
    }
    return said.map(_sent).toList()..sort(_bySaid);
  }

  /// [said] as of when it was sent, where that came later.
  _Said _sent(_Said said) => switch (_sentAt[said.id]) {
    final sent? when sent > said.time => (
      side: said.side,
      id: said.id,
      time: sent,
      said: said.said,
      copy: said.copy,
    ),
    _ => said,
  };

  static int _bySaid(_Said a, _Said b) =>
      a.time != b.time ? a.time.compareTo(b.time) : a.id.compareTo(b.id);
}

typedef MergedEntry = ({ChatEntry entry, GraphId graph, int rank});

int unreadIn(List<MergedEntry> entries, Map<GraphId, (int, EventId)> read) =>
    entries
        .where(
          (e) =>
              !e.entry.mine &&
              !e.entry.notice &&
              e.rank > (read[e.graph]?.$1 ?? -1),
        )
        .length;

/// The entries of a merge by time, relayed messages shown as their senders',
/// without [Echoes].
final class MergedLog {
  final MessageFormats _formats;
  final _logs = <GraphId, ChatLog>{};
  late final _echoes = Echoes(_formats);
  ChatMerge? _merge;
  // The names that speak other than through bots, and the events read for
  // them.
  final _speakers = <String>{};
  final _spoken = <EventId>{};
  // Merged entries by event, while [_speakers] stays.
  final _merged = <EventId, (ChatEntry, MergedEntry)>{};

  MergedLog(this._formats);

  List<MergedEntry> update(
    ChatMerge merge,
    List<List<(EventId, SyncEvent)>> events,
  ) {
    final count = events.fold(0, (n, side) => n + side.length);
    if (merge != _merge || count < _spoken.length) {
      _merge = merge;
      _speakers.clear();
      _spoken.clear();
      _merged.clear();
    }
    final repeats = _echoes.update(merge, events);
    final known = _speakers.length;
    for (final (side, MergeSide(:bots)) in merge.sides.indexed) {
      _speakers.addAll(
        _speakersOf(events[side].where((e) => _spoken.add(e.$1)), bots),
      );
    }
    if (_speakers.length != known) {
      _merged.clear();
    }
    final sides = [
      for (final (side, MergeSide(:graph, :bots)) in merge.sides.indexed)
        _side(
          graph,
          bots,
          events[side],
          (_logs[graph] ??= ChatLog(_formats)).update(events[side]),
          repeats,
        ),
    ];
    // Each chat's entries stay in their order, the chats' between each other
    // by time.
    final next = List.filled(sides.length, 0);
    final merged = <MergedEntry>[];
    while (true) {
      int? first;
      for (final (side, entries) in sides.indexed) {
        if (next[side] < entries.length &&
            (first == null ||
                entries[next[side]].entry.timestamp.isBefore(
                  sides[first][next[first]].entry.timestamp,
                ))) {
          first = side;
        }
      }
      if (first == null) {
        return merged;
      }
      merged.add(sides[first][next[first]++]);
    }
  }

  List<MergedEntry> _side(
    GraphId graph,
    Set<PublicKey> bots,
    List<(EventId, SyncEvent)> events,
    List<ChatEntry> entries,
    Set<EventId> repeats,
  ) {
    late final byId = {for (final (id, event) in events) id: event};
    MergedEntry merged(ChatEntry entry) {
      final event = byId[entry.event];
      return (
        entry: switch ((event?.content, entry.content)) {
          (Received(:final from?), TextContent(:final text))
              when bots.contains(from) =>
            switch (relayed(text, names: _speakers)) {
              (final name, final body) => entry.copyWith(
                sender: name,
                from: null,
                content: contentOfMessage(body),
              ),
              null => entry,
            },
          _ => entry,
        },
        graph: graph,
        rank: event?.rank ?? 0,
      );
    }

    return [
      for (final entry in entries)
        if (!repeats.contains(entry.event))
          switch (_merged[entry.event]) {
            (final from, final done) when identical(from, entry) => done,
            _ => (_merged[entry.event] = (entry, merged(entry))).$2,
          },
    ];
  }
}
