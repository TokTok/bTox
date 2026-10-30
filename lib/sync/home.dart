import 'dart:async';

import 'package:btox/db/database.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/intents.dart';
import 'package:btox/sync/store.dart';
import 'package:clock/clock.dart';

/// The account of a profile this device is the home device of, as events of
/// what Tox does and what the pages ask for. Events join [store] once saved.
final class Home {
  final Database _db;
  final Id<Profiles> _profileId;
  final PublicKey me;
  final store = EventStore();
  var state = AccountState.of(const []);
  final _fold = AccountFold();
  late final earlier = EarlierRepeats(store);
  var _friends = const <GraphId, PublicKey>{};
  late final _writer = EventWriter(
    _db,
    _profileId,
    (graph, time, content) =>
        store.author(graph, me, time, content, minRank: _deleted[graph] ?? 0),
    _saved,
  );
  // Chats deleted here, by the rank their next event takes.
  final _deleted = <GraphId, int>{};

  /// Our messages not delivered yet, by their Send event, with the friend.
  final undelivered = <EventId, PublicKey>{};
  final _sent = <EventId>{};

  Home._(this._db, this._profileId, this.me);

  GraphId get account => GraphId.account(me);

  GraphId chatWith(PublicKey friend) => GraphId.friend(me, friend);

  PublicKey? friendOf(GraphId chat) => _friends[chat];

  static Future<Home> load(Database db, Profile profile) async {
    final home = Home._(db, profile.id, profile.publicKey);
    home._deleted.addAll(await db.getDeletedChats(profile.id));
    for (final bytes in await db.getSyncEvents(profile.id)) {
      home.store.insert(bytes);
    }
    home._accountChanged();
    final events = [
      for (final graph in home.store.graphs) ...home.store.eventsIn(graph),
    ];
    // Deliveries after what they deliver.
    for (final delivered in [false, true]) {
      for (final (id, event) in events) {
        if ((event.content is Delivered) == delivered) {
          home._added(id, event);
        }
      }
    }
    return home;
  }

  /// Records [content] in [graph], saved by [save] if given, or null if it
  /// couldn't be saved.
  Future<NewEvent?> record(
    GraphId graph,
    EventContent content, {
    Future<void> Function(NewEvent)? save,
  }) => _writer.write(
    graph,
    () => switch (content) {
      // A file whose chat was deleted has nothing left to end.
      FileEnded(:final file) when !store.contains(file) => null,
      _ => content,
    },
    save: save,
  );

  /// Ends what stopped with Tox, until [stopped]: friends' unfinished
  /// files, which it forgets, and calls, which ended unrecorded.
  Future<void> endInterrupted({required bool Function() stopped}) async {
    for (final transfer in await _db.watchTransfers(_profileId).first) {
      if (stopped()) {
        return;
      }
      if (transfer case Transfer(
        incoming: true,
        :final event?,
        state: FileState.offered || FileState.active,
      )) {
        await _db.setTransferState(transfer.id, FileState.paused);
        await record(transfer.graph, FileEnded(file: event, ok: false));
      }
    }
    for (final graph in store.graphs) {
      final events = store.eventsIn(graph);
      final ended = {
        for (final (_, event) in events)
          if (event.content case CallEnded(:final call)) call,
      };
      for (final (id, event) in events) {
        if (stopped()) {
          return;
        }
        if (event.content is Call && !ended.contains(id)) {
          await record(graph, CallEnded(call: id));
        }
      }
    }
  }

  void _saved(NewEvent event) {
    final (id, saved, bytes) = event;
    store.insert(bytes);
    if (saved.graph == account) {
      _accountChanged();
    }
    _added(id, saved);
  }

  Future<void> profileChanged(ProfileSettings settings) async {
    await _fact(const Subject.account(), FactValue.name(settings.nickname));
    await _fact(
      const Subject.account(),
      FactValue.statusMessage(settings.statusMessage),
    );
  }

  /// Records what Tox says, unless the account knows it already.
  Future<void> _fact(Subject subject, FactValue value) => _writer.write(
    account,
    () => state.facts.of(subject).contains(value)
        ? null
        : FactContent(subject: subject, value: value),
  );

  /// Returns the files of the chats deleted with friends.
  Future<List<String>> intents(
    List<StoredIntent> intents,
    String sender,
  ) async {
    final files = <String>[];
    await _writer.intents(
      intents,
      account,
      (_) => sender,
      save: (intent, event) async => files.addAll(switch (intent) {
        StoredIntent(deleteChat: true, content: UnwantFriend(:final pk)) =>
          await _deleteChat(intent, pk, event),
        _ => await _db.writeIntent(intent, event),
      }),
    );
    return files;
  }

  /// The chat's next event ranks after everything deleted from it. Returns
  /// its files.
  Future<List<String>> _deleteChat(
    StoredIntent intent,
    PublicKey friend,
    NewEvent event,
  ) async {
    final chat = chatWith(friend);
    final next = store.nextRank(chat, minRank: _deleted[chat] ?? 0);
    final files = await _db.writeIntent(intent, event, deleted: (chat, next));
    store.forget(chat);
    earlier.forget(chat);
    undelivered.removeWhere((id, _) => !store.contains(id));
    _deleted[chat] = next;
    return files;
  }

  Future<void> reads(List<ChatRead> reads) =>
      _writer.reads(account, reads, () => state);

  Future<void> startFiles(List<Transfer> transfers, String sender) async {
    for (final transfer in transfers) {
      if (transfer.event == null) {
        await _writer.once(
          transfer.id,
          () => record(
            transfer.graph,
            FileStarted(
              sender: sender,
              name: transfer.name,
              size: transfer.size,
              incoming: false,
            ),
            save: (event) => _db.writeTransferEvent(transfer.id, event),
          ),
        );
      }
    }
  }

  Future<void> named(PublicKey pk, String name) =>
      _fact(Subject.friend(pk), FactValue.name(name));

  /// A friend first coming online means they accepted our request.
  Future<void> accepted(PublicKey pk) => _writer.write(
    account,
    () => state.friends[pk]?.nospam == null ? null : WantFriend(pk: pk),
  );

  /// Tox took our message [id].
  Future<void> sent(EventId id) => _writer.write(
    store[id]!.graph,
    () => _sent.contains(id) ? null : Sent(intent: id),
  );

  Future<void> delivered(EventId id) => _writer.write(
    store[id]!.graph,
    () => undelivered.containsKey(id) ? Delivered(intent: id) : null,
  );

  /// Whether [pk]'s request saying [message] was declined: their client
  /// sends a request again until it's accepted.
  bool declined(PublicKey pk, String message) {
    String? asked;
    var refused = false;
    for (final (_, event) in rankOrder(store.eventsIn(account))) {
      switch (event.content) {
        case FriendRequested(pk: final from, message: final text)
            when from == pk:
          (asked, refused) = (text, false);
        case UnwantFriend(pk: final friend) when friend == pk:
          refused = asked != null;
        case WantFriend(pk: final friend) when friend == pk:
          (asked, refused) = (null, false);
        default:
          break;
      }
    }
    return refused && asked == message;
  }

  void _accountChanged() {
    state = _fold.update(store.eventsIn(account));
    _friends = {for (final pk in state.friends.keys) chatWith(pk): pk};
  }

  void _added(EventId id, SyncEvent event) {
    switch (event.content) {
      case Send() when friendOf(event.graph) != null:
        undelivered[id] = friendOf(event.graph)!;
      case Sent(:final intent):
        _sent.add(intent);
      case Delivered(:final intent):
        undelivered.remove(intent);
      default:
        break;
    }
  }
}

/// Events of [me]'s account written one after another, before it runs.
final class AccountWriter {
  final PublicKey me;
  final store = EventStore();
  final events = <NewEvent>[];

  AccountWriter(this.me, ProfileSettings settings) {
    for (final value in [
      FactValue.name(settings.nickname),
      FactValue.statusMessage(settings.statusMessage),
    ]) {
      add(
        account,
        clock.now(),
        FactContent(subject: const Subject.account(), value: value),
      );
    }
  }

  GraphId get account => GraphId.account(me);

  EventId add(GraphId graph, DateTime time, EventContent content) {
    final added = store.author(graph, me, time, content);
    store.insert(added.$3);
    events.add(added);
    return added.$1;
  }

  void addFriend(DateTime time, WantFriend want, String? name) {
    add(account, time, want);
    if (name != null && name.isNotEmpty) {
      add(
        account,
        time,
        FactContent(
          subject: Subject.friend(want.pk),
          value: FactValue.name(name),
        ),
      );
    }
  }
}
