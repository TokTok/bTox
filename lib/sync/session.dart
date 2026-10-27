import 'dart:typed_data';

import 'package:btox/models/crypto.dart';
import 'package:btox/sync/session_message.dart';
import 'package:btox/sync/store.dart';

// The exchange both ends of a session run: each sends a Summary, answers the
// other's with Heads where they differ, asks with Want for heads it lacks,
// and answers Want from its own store. History is the home's to answer: a
// replica keeps only the latest of each conversation, so its answers would
// have gaps.

const _maxWant = 64;
// Keeps replies small, so live events aren't stuck behind them.
const _maxEventsBytes = 64 * 1024;

Summary summary(EventStore store) => Summary([
  for (final graph in store.graphs)
    (graph, HeadsDigest.of(store.headsOf(graph))),
]);

/// Our heads of each graph the other side holds differently or not at all.
/// Graphs only they have come back in their Heads for our summary.
List<SessionMessage> headsFor(
  EventStore store,
  List<(GraphId, HeadsDigest)> theirs,
) {
  final digests = {for (final (graph, digest) in theirs) graph: digest};
  return [
    for (final graph in store.graphs)
      if (digests[graph] != HeadsDigest.of(store.headsOf(graph)))
        Heads(graph: graph, heads: store.headsOf(graph).toList()),
  ];
}

List<SessionMessage> want(Iterable<EventId> ids) {
  final wanted = ids.toList();
  return [
    for (var i = 0; i < wanted.length; i += _maxWant)
      Want(wanted.skip(i).take(_maxWant).toList()),
  ];
}

/// Encoded events, in as many Events messages as they need.
List<SessionMessage> batches(Iterable<Uint8List> events) {
  final messages = <SessionMessage>[];
  var batch = <Uint8List>[];
  var size = 0;
  for (final bytes in events) {
    if (size + bytes.length > _maxEventsBytes && batch.isNotEmpty) {
      messages.add(Events(batch));
      batch = [];
      size = 0;
    }
    batch.add(bytes);
    size += bytes.length;
  }
  if (batch.isNotEmpty) {
    messages.add(Events(batch));
  }
  return messages;
}

/// The replies to a message, as far as they only need the store. Events and
/// Live are for the caller, which knows what to accept.
List<SessionMessage> answer(EventStore store, SessionMessage message) =>
    switch (message) {
      Summary(:final graphs) => headsFor(store, graphs),
      Heads(:final heads) => want(heads.where((h) => !store.contains(h))),
      Want(:final ids) => batches([
        for (final id in ids.take(_maxWant)) ?store.bytes(id),
      ]),
      _ => const [],
    };
