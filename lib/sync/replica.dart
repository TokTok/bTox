import 'dart:math';
import 'dart:typed_data';

import 'package:btox/logger.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/session.dart' as session;
import 'package:btox/sync/session_message.dart';
import 'package:btox/sync/store.dart';

const _logger = Logger(['Replica']);

/// How many of a conversation's latest events a replica first asks for.
const historyPage = 50;

/// The most History answers hold, as the home device caps them.
const _maxHistory = 500;

/// A copy of an account kept from its home device. It only decides, and the
/// caller stores and sends.
final class Replica {
  final PublicKey device;
  final PublicKey home;
  final GraphId account;
  final store = EventStore();
  late final earlier = EarlierRepeats(store);
  var _session = false;
  // Conversations whose latest page has been asked for in this session.
  final _paged = <GraphId>{};
  final _fold = AccountFold();
  AccountState? _state;
  // Each friend by the graph of their conversation.
  Map<GraphId, PublicKey>? _friends;

  Replica({required this.device, required this.home})
    : account = GraphId.account(home);

  static const hello = Hello(features: Features.accountSync);

  bool get inSession => _session;

  AccountState get state => _state ??= _fold.update(store.eventsIn(account));

  Map<GraphId, PublicKey> get _friendIn => _friends ??= {
    for (final pk in state.friends.keys) GraphId.friend(home, pk): pk,
  };

  void _accountChanged() {
    _state = null;
    _friends = null;
  }

  /// Adds an event this device saved before.
  void load(Uint8List bytes) {
    final (_, event) = store.insert(bytes);
    if (event.graph == account) {
      _accountChanged();
    }
  }

  /// When the home device paired this one, by the home's clock.
  int? get pairedAt {
    int? earliest;
    for (final (_, event) in store.eventsIn(account)) {
      if (event.content case WantFriend(:final pk) when pk == device) {
        earliest = min(earliest ?? event.time, event.time);
      }
    }
    return earliest;
  }

  String? nameOf(GraphId graph) => switch (_friendIn[graph]) {
    final pk? => state.friends[pk]!.name,
    null => _chatOf(graph)?.name,
  };

  /// Whether the home device takes what this device writes in [graph]'s
  /// conversation: one with a friend or in a chat joined.
  bool canWrite(GraphId graph) =>
      (state.friends[_friendIn[graph]]?.wanted ?? false) ||
      (_chatOf(graph)?.joined ?? false);

  String? selfNameIn(GraphId graph) => _chatOf(graph)?.selfName ?? state.name;

  /// The chat whose conversation [graph] is.
  ChatId? chatIn(GraphId graph) =>
      state.chats.keys.where((chat) => chat.graph == graph).firstOrNull;

  AccountChat? _chatOf(GraphId graph) => state.chats[chatIn(graph)];

  void offline() {
    _session = false;
    _paged.clear();
  }

  /// The replies to a message from the home device, and the events it added
  /// to [store].
  ({List<SessionMessage> replies, List<NewEvent> added}) received(
    SessionMessage message,
  ) {
    if (message case Hello(:final features)) {
      _session = features.contains(Features.accountSync);
      _paged.clear();
      return (replies: [if (_session) session.summary(store)], added: const []);
    }
    if (!_session) {
      return (replies: const [], added: const []);
    }
    if (message case Events(:final events)) {
      return _add(events);
    }
    return (replies: session.answer(store, message), added: const []);
  }

  /// An event by this device, after the heads it knows. It's added with
  /// [written], once it's stored.
  NewEvent author(GraphId graph, DateTime time, EventContent content) =>
      store.author(graph, device, time, content);

  /// What to send the home device for an event this device wrote: nothing
  /// outside a session, where the next one's summaries catch up.
  List<SessionMessage> written(NewEvent event) {
    store.insert(event.$3);
    if (event.$2.graph == account) {
      _accountChanged();
    }
    return _session ? session.batches([event.$3]) : const [];
  }

  ({List<SessionMessage> replies, List<NewEvent> added}) _add(
    List<Uint8List> events,
  ) {
    final added = <NewEvent>[];
    // The graphs of what came, also of events held already.
    final came = <GraphId>{};
    for (final bytes in events) {
      if (store[EventId.of(bytes)] case final held?) {
        came.add(held.graph);
        continue;
      }
      try {
        final (id, event) = store.insert(bytes);
        added.add((id, event, bytes));
        came.add(event.graph);
      } on FormatException catch (e) {
        _logger.w('Dropped an unreadable event: $e');
      }
    }
    final replies = <SessionMessage>[];
    for (final graph in came) {
      final grew = added.any((e) => e.$2.graph == graph);
      if (grew && graph == account) {
        _accountChanged();
      }
      if (_gap(graph) case final gap?) {
        replies.addAll(
          grew
              ? [History(graph: graph, before: gap, limit: _maxHistory)]
              // History brought nothing new: the missing parents are further
              // back than it goes.
              : session.want({
                  for (final id in gap)
                    for (final parent in store[id]!.parents)
                      if (!store.contains(parent)) parent,
                }),
        );
      } else if (grew && graph != account && _paged.add(graph)) {
        replies.add(
          History(
            graph: graph,
            before: store.headsOf(graph).toList(),
            limit: historyPage,
          ),
        );
      }
    }
    return (replies: replies, added: added);
  }

  /// The events to ask for the ancestors of, while [graph] has a gap: all
  /// the account's, and of a conversation the part between its latest
  /// events and the older ones held here.
  List<EventId>? _gap(GraphId graph) {
    final frontier = store.frontier(graph);
    if (frontier.isEmpty) {
      return null;
    }
    final oldest = graph == account
        ? null
        : store.eventsIn(graph).map((e) => e.$2.rank).reduce(min);
    final gap = [
      for (final (id, event) in frontier)
        if (oldest == null || event.rank > oldest) id,
    ];
    return gap.isEmpty ? null : gap;
  }
}
