import 'dart:math';
import 'dart:typed_data';

import 'package:btox/models/crypto.dart';
import 'package:btox/sync/event.dart';

/// The most an event takes, in bytes.
const maxEventBytes = 64 * 1024;

/// Ranks stay below this, so one more always fits, also as a double.
const maxRank = 1 << 53;

final class EventStore {
  final _events = <EventId, SyncEvent>{};
  // Forwarded as received, so every device computes the same IDs.
  final _bytes = <EventId, Uint8List>{};
  final _graphs = <GraphId, List<EventId>>{};
  final _heads = <GraphId, Set<EventId>>{};
  final _referenced = <GraphId, Set<EventId>>{};

  bool contains(EventId id) => _events.containsKey(id);

  SyncEvent? operator [](EventId id) => _events[id];

  Set<EventId> headsOf(GraphId graph) => _heads[graph] ?? const {};

  Iterable<GraphId> get graphs => _heads.keys;

  Uint8List? bytes(EventId id) => _bytes[id];

  /// Throws [FormatException] for bytes that aren't an event, or are more
  /// than one may be.
  (EventId, SyncEvent) insert(Uint8List bytes) {
    if (bytes.length > maxEventBytes) {
      throw const FormatException('Too big for an event');
    }
    final id = EventId.of(bytes);
    final known = _events[id];
    if (known != null) {
      return (id, known);
    }
    final event = SyncEvent.decode(bytes);
    _checkRank(event);
    final heads = _heads.putIfAbsent(event.graph, () => {})
      ..removeAll(event.parents);
    final referenced = _referenced.putIfAbsent(event.graph, () => {});
    if (!referenced.contains(id)) {
      heads.add(id);
    }
    referenced.addAll(event.parents);
    _graphs.putIfAbsent(event.graph, () => []).add(id);
    _events[id] = event;
    _bytes[id] = bytes;
    return (id, event);
  }

  /// An event's rank is one more than its highest parent's. Only the parents
  /// here can be checked: the others may come later, as history is paged in
  /// newest first.
  void _checkRank(SyncEvent event) {
    final known = [for (final parent in event.parents) ?_events[parent]?.rank];
    final fits =
        event.rank < maxRank &&
        switch (known.isEmpty ? null : known.reduce(max)) {
          null => true,
          final highest when known.length == event.parents.length =>
            event.rank == highest + 1,
          final highest => event.rank > highest,
        };
    if (!fits) {
      throw const FormatException("Rank doesn't follow its parents'");
    }
  }

  List<(EventId, SyncEvent)> eventsIn(GraphId graph) => eventsFrom(graph, 0);

  /// [graph]'s events after the first [start], in the order they came.
  List<(EventId, SyncEvent)> eventsFrom(GraphId graph, int start) => [
    for (final id in (_graphs[graph] ?? const <EventId>[]).skip(start))
      (id, _events[id]!),
  ];

  int countIn(GraphId graph) => _graphs[graph]?.length ?? 0;

  void forget(GraphId graph) {
    for (final id in _graphs.remove(graph) ?? const <EventId>[]) {
      _events.remove(id);
      _bytes.remove(id);
    }
    _heads.remove(graph);
    _referenced.remove(graph);
  }

  /// The rank of a new event in [graph] after its heads, [minRank] at least.
  int nextRank(GraphId graph, {int minRank = 0}) =>
      headsOf(graph)
          .fold(minRank, (rank, id) => max(rank, _events[id]!.rank + 1));

  /// A new event by [author] in [graph] after its heads, not yet inserted,
  /// of rank [minRank] at least.
  NewEvent author(
    GraphId graph,
    PublicKey author,
    DateTime time,
    EventContent content, {
    int minRank = 0,
  }) {
    final event = SyncEvent(
      graph: graph,
      author: author,
      parents: headsOf(graph).toList()..sort(),
      rank: nextRank(graph, minRank: minRank),
      time: time.millisecondsSinceEpoch,
      content: content,
    );
    final bytes = event.encode();
    return (EventId.of(bytes), event, bytes);
  }

  /// [graph]'s events whose parents this device doesn't all have: where its
  /// history stops here, or has a gap.
  List<(EventId, SyncEvent)> frontier(GraphId graph) => [
    for (final (id, event) in eventsIn(graph))
      if (!event.parents.every(_events.containsKey)) (id, event),
  ];
}

/// In the order last-writer-wins rules apply them: by rank, then ID.
List<(EventId, SyncEvent)> rankOrder(Iterable<(EventId, SyncEvent)> events) =>
    events.toList()
      ..sort((a, b) => compareRanks((a.$2.rank, a.$1), (b.$2.rank, b.$1)));

int compareRanks((int, EventId) a, (int, EventId) b) {
  final rank = a.$1.compareTo(b.$1);
  return rank != 0 ? rank : a.$2.compareTo(b.$2);
}
