import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/attachments/attachments.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_Err_Friend_Custom_Packet;
import 'package:btox/logger.dart';
import 'package:btox/messages/message_format.dart';
import 'package:btox/models/app_defaults.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_merge.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/frames.dart';
import 'package:btox/sync/intents.dart';
import 'package:btox/sync/linked_files.dart';
import 'package:btox/sync/replica.dart';
import 'package:btox/sync/session_message.dart';
import 'package:btox/sync/setting.dart';
import 'package:clock/clock.dart';

const _logger = Logger(['SyncSessions']);

const _retryDelay = Duration(milliseconds: 50);

/// The sync protocol over Tox: Hello with every online friend and, for a
/// linked account, the session with its home device. A [Replica] decides;
/// this stores and sends.
final class SyncSessions {
  final Database _db;
  final Tox _tox;
  final Id<Profiles> _profileId;
  final Future<String> Function() _directory;
  final _incoming = <int, Reassembler>{};
  final _outbox = <int, Queue<Uint8List>>{};
  Timer? _retry;

  /// How friends' messages are read.
  MessageFormats get formats => _formats;
  set formats(MessageFormats formats) {
    if (formats != _formats) {
      _formats = formats;
      _echoes.clear();
    }
  }

  var _formats = MessageFormats.none;
  final _echoes = <GraphId, Echoes>{};

  /// Hears the home device's live facts: with `all`, every one there is, as
  /// none when it goes offline.
  void Function(List<Fact> facts, {required bool all})? onLiveFacts;

  PublicKey? _home;
  Replica? _replica;
  LinkedFiles? _files;
  var _autoAcceptSize = defaultAutoAcceptFileSize;
  var _loaded = false;
  // How far each chat has been notified, once loaded.
  Map<GraphId, int>? _notified;
  int? _homeFriend;

  EventWriter? _writer;
  var _intents = const <StoredIntent>[];
  var _reads = const <ChatRead>[];
  var _transfers = const <Transfer>[];

  // Shows a linked chat's new unread messages.
  final void Function(
    ChatRef chat,
    String? title,
    List<NotifiedMessage> messages,
    String? account,
  )?
  _notify;
  // Takes back a linked chat's notification.
  final void Function(ChatRef chat)? _read;

  // Tells of an invite to a chat by its event, with the names of the friend
  // it's from and of the account.
  final void Function(
    EventId id,
    AccountInvite invite,
    String? from,
    String? account,
  )?
  _invited;
  // Takes back what it told of an invite.
  final void Function(EventId id)? _uninvited;
  // Invites that may have been told of, until they're answered.
  final _invitesTold = <EventId>{};

  SyncSessions(
    this._db,
    this._tox,
    this._profileId, {
    Future<String> Function()? directory,
    void Function(ChatRef, String?, List<NotifiedMessage>, String?)? notify,
    void Function(ChatRef)? read,
    void Function(EventId, AccountInvite, String?, String?)? invited,
    void Function(EventId)? uninvited,
  }) : _directory = directory ?? (() async => ''),
       _notify = notify,
       _read = read,
       _invited = invited,
       _uninvited = uninvited;

  void dispose() {
    _retry?.cancel();
    _files?.dispose();
  }

  LinkedFiles? get files => _files;

  /// The home device's friend number, while it's online.
  int? get homeFriend => _homeFriend;

  String? friendName(PublicKey friend) => _replica?.state.friends[friend]?.name;

  String get accountName => _replica?.state.name ?? '';

  void toHome(SessionMessage message) => _toHome([message]);

  /// Larger files of a linked account are fetched when asked for.
  set autoAcceptSize(int size) {
    _autoAcceptSize = size;
    _files?.autoAcceptSize = size;
  }

  /// Makes this profile a copy of [home]'s account, or a plain one without.
  void link(PublicKey device, PublicKey? home) {
    if (home == _home) {
      return;
    }
    _home = home;
    _loaded = false;
    _notified = null;
    _invitesTold.clear();
    final replica = _replica = home == null
        ? null
        : Replica(device: device, home: home);
    _files?.dispose();
    _files = home == null
        ? null
        : (LinkedFiles(
              _db,
              _tox,
              _profileId,
              device,
              _directory,
              (message) => _toHome([message]),
            )
            ..autoAcceptSize = _autoAcceptSize
            ..transfersChanged(_transfers));
    _writer = replica == null
        ? null
        : EventWriter(_db, _profileId, replica.author, (event) {
            if (identical(replica, _replica)) {
              _toHome(replica.written(event));
              _withdrawInvites(replica);
            }
          });
    if (replica != null) {
      _logger.unawaited('load sync events', _load(replica));
    }
  }

  Future<void> _load(Replica replica) async {
    final unreadable = <EventId>[];
    for (final bytes in await _db.getSyncEvents(_profileId)) {
      try {
        replica.load(bytes);
      } on FormatException {
        unreadable.add(EventId.of(bytes));
      }
    }
    if (unreadable.isNotEmpty) {
      _logger.w(
        'Dropping ${unreadable.length} unreadable events to sync again',
      );
      await _db.dropSyncEvents(_profileId, unreadable);
    }
    final notified = await _db.getLinkedNotified(_profileId);
    if (identical(replica, _replica)) {
      _notified = notified;
      _loaded = true;
      // An earlier run may have told of these.
      _invitesTold.addAll([
        for (final MapEntry(key: id, value: invite)
            in replica.state.invites.entries)
          if (invite.status == InviteStatus.pending) id,
      ]);
      _logger.unawaited('write events', _writeEvents());
      _logger.unawaited(
        'fetch files',
        _files!.fetchEnded(replica.store, [
          for (final graph in replica.store.graphs)
            ...replica.store.eventsIn(graph),
        ]),
      );
    }
  }

  void intentsChanged(List<StoredIntent> intents) {
    _intents = intents;
    _logger.unawaited('write events', _writeEvents());
  }

  void transfersChanged(List<Transfer> transfers) {
    _transfers = transfers;
    _files?.transfersChanged(transfers);
    _logger.unawaited('write events', _writeEvents());
  }

  void readsChanged(List<ChatRead> reads) {
    _reads = reads;
    _logger.unawaited('write events', _writeEvents());
  }

  Future<void> _writeEvents() async {
    final (replica, writer) = (_replica, _writer);
    if (replica == null || writer == null || !_loaded) {
      return;
    }
    String senderIn(GraphId chat) => replica.selfNameIn(chat) ?? '';
    // What the home device wouldn't take waits for the chat to come back.
    await writer.intents(
      _intents,
      replica.account,
      senderIn,
      canWrite: replica.canWrite,
    );
    await writer.files(
      [
        for (final transfer in _transfers)
          if (replica.canWrite(transfer.graph)) transfer,
      ],
      senderIn,
      blobOf,
    );
    await writer.reads(replica.account, [
      for (final read in _reads)
        if (replica.canWrite(read.graph)) read,
    ], () => replica.state);
  }

  void online(int friendNumber, PublicKey publicKey) {
    if (publicKey == _home) {
      _homeFriend = friendNumber;
    }
    // Our Hello is the first message of each connection, ahead of replies
    // to the friend's Hello that came before Tox reported it online. None of
    // those went out, so it doesn't split one.
    _send(
      friendNumber,
      publicKey == _home ? Replica.hello : const Hello(features: Features.none),
      first: true,
    );
  }

  void offline(int friendNumber) {
    _incoming.remove(friendNumber);
    _outbox.remove(friendNumber);
    if (friendNumber == _homeFriend) {
      _homeFriend = null;
      _replica?.offline();
      _files?.session(null);
      _forgetLiveFacts();
    }
  }

  // Only the home device knows what Tox says now.
  void _forgetLiveFacts() {
    _logger.unawaited('forget live facts', _db.clearLiveFacts(_profileId));
    onLiveFacts?.call(const [], all: true);
  }

  void received(int friendNumber, PublicKey publicKey, Uint8List packet) {
    final SessionMessage? message;
    try {
      final bytes = (_incoming[friendNumber] ??= Reassembler()).push(packet);
      if (bytes == null) {
        return;
      }
      message = SessionMessage.decode(bytes);
    } on FormatException catch (e) {
      _logger.w('Dropped sync message from friend $friendNumber: $e');
      return;
    }
    if (message == null) {
      return;
    }
    if (message case Hello(:final version, :final features)) {
      _logger.i(
        'Friend $friendNumber speaks sync v$version, features ${features.bits}',
      );
    }

    final replica = _replica;
    if (replica == null || publicKey != _home) {
      return;
    }
    // Its messages can come before Tox reports it online.
    _homeFriend = friendNumber;
    if (message case FactsUpdate(:final facts, :final all)
        when replica.inSession) {
      _logger.unawaited(
        'save live facts',
        _db.updateLiveFacts(_profileId, facts, all: all),
      );
      onLiveFacts?.call(facts, all: all);
      return;
    }
    if (message case WantBlob() || NoBlob() when replica.inSession) {
      _files?.received(message);
      return;
    }
    final (:replies, :added) = replica.received(message);
    if (message is Hello) {
      _files?.session(replica.inSession ? friendNumber : null);
      if (!replica.inSession) {
        _forgetLiveFacts();
      }
    }
    if (added.isNotEmpty) {
      _logger.unawaited('save events', _db.addSyncEvents(_profileId, added));
      _notifyUnread(replica, added);
      _unnotifyRead(replica, added);
      _notifyInvites(replica, added);
      _withdrawInvites(replica);
      _logger.unawaited(
        'fetch files',
        _files!.fetchEnded(replica.store, [
          for (final (id, e, _) in added) (id, e),
        ]),
      );
    }
    _toHome(replies);
  }

  /// Shows each chat's newest message past both how far it was read and how
  /// far it was notified, so history that syncs again stays quiet. In a chat
  /// never notified, only messages from after the pairing count. Merged chats
  /// notify as one, without [Echoes].
  void _notifyUnread(Replica replica, List<NewEvent> added) {
    final notified = _notified;
    final pairedAt = replica.pairedAt;
    if (notified == null || pairedAt == null) {
      return;
    }
    final merges = mergedChats(replica.state);
    final sides = _sidesOf(merges);
    final repeats = {
      for (final chat in {
        for (final (_, event, _) in added) ?sides[event.graph]?.chat,
      })
        ...(_echoes[chat] ??= Echoes(formats)).update(merges[chat]!, [
          for (final side in merges[chat]!.sides)
            replica.store.eventsIn(side.graph),
        ]),
    };
    final unread = <GraphId, List<SyncEvent>>{};
    for (final (id, event, _) in added) {
      final graph = event.graph;
      final since = notified[graph];
      if (isIncoming(event.content) &&
          event.rank > (replica.state.read[graph]?.$1 ?? -1) &&
          (since == null ? event.time >= pairedAt : event.rank > since) &&
          !repeats.contains(id) &&
          !replica.earlier.repeats(id, event, formats)) {
        (unread[graph] ??= []).add(event);
      }
    }
    final shown = <GraphId, List<SyncEvent>>{};
    for (final MapEntry(key: graph, value: events) in unread.entries) {
      final rank = events.map((event) => event.rank).reduce(max);
      notified[graph] = rank;
      _logger.unawaited(
        'save notified',
        _db.setLinkedNotified(_profileId, graph, rank),
      );
      (shown[sides[graph]?.chat ?? graph] ??= []).addAll(events);
    }
    for (final MapEntry(key: chat, value: events) in shown.entries) {
      events.sort((a, b) => a.time.compareTo(b.time));
      final listed = notifying(
        [
          for (final event in events)
            _listed(event, sides[event.graph]?.side.bots ?? const {}),
        ],
        replica.state.setting<Mute>(Scope.conversation(chat)),
        clock.now(),
        [
          for (final graph
              in merges[chat]?.sides.map((side) => side.graph) ?? [chat])
            ?replica.selfNameIn(graph),
        ],
      );
      if (listed.isNotEmpty) {
        _notify?.call(
          ChatRef(_profileId, chat),
          replica.nameOf(chat),
          listed,
          replica.state.name,
        );
      }
    }
  }

  /// Takes back the notifications of chats [added] reads past them, as
  /// another device read them.
  void _unnotifyRead(Replica replica, List<NewEvent> added) {
    final notified = _notified;
    if (notified == null) {
      return;
    }
    final sides = _sidesOf(mergedChats(replica.state));
    for (final (_, event, _) in added) {
      if (event.content case ReadUpTo(:final graph, :final rank)
          when event.graph == replica.account) {
        if (notified[graph] case final shown? when rank >= shown) {
          _read?.call(ChatRef(_profileId, sides[graph]?.chat ?? graph));
        }
      }
    }
  }

  /// The chat in which each side of [merges] shows, and as which side.
  static Map<GraphId, ({GraphId chat, MergeSide side})> _sidesOf(
    Map<GraphId, ChatMerge> merges,
  ) => {
    for (final MapEntry(key: chat, value: merge) in merges.entries)
      for (final side in merge.sides) side.graph: (chat: chat, side: side),
  };

  /// [event] as its notification lists it: a group member's or relay bot's
  /// under who said it.
  NotifiedMessage _listed(SyncEvent event, Set<PublicKey> bots) {
    final text = notificationText(event.content, formats);
    final time = DateTime.fromMillisecondsSinceEpoch(event.time);
    return switch ((event.content, relayed(text))) {
      (Received(:final from?), (final name, final body))
          when bots.contains(from) =>
        (sender: name, text: body, time: time),
      (Received(from: _?, :final sender), _) => (
        sender: sender,
        text: text,
        time: time,
      ),
      _ => (sender: null, text: text, time: time),
    };
  }

  /// Tells of the invites in [added] waiting for an answer, past how far the
  /// account was notified. In one never notified, it tells of those from
  /// after the pairing.
  void _notifyInvites(Replica replica, List<NewEvent> added) {
    final notified = _notified;
    final pairedAt = replica.pairedAt;
    if (notified == null || pairedAt == null) {
      return;
    }
    final state = replica.state;
    final since = notified[replica.account];
    var rank = since;
    for (final (id, event, _) in added) {
      if (state.invites[id] case final invite?
          when invite.status == InviteStatus.pending &&
              (since == null ? event.time >= pairedAt : event.rank > since)) {
        _invitesTold.add(id);
        _invited?.call(
          id,
          invite,
          state.friends[invite.from]?.name,
          state.name,
        );
        rank = max(rank ?? event.rank, event.rank);
      }
    }
    if (rank case final rank? when rank != since) {
      notified[replica.account] = rank;
      _logger.unawaited(
        'save notified',
        _db.setLinkedNotified(_profileId, replica.account, rank),
      );
    }
  }

  /// Takes back what was told of invites answered since, here or elsewhere.
  void _withdrawInvites(Replica replica) {
    _invitesTold.removeWhere((id) {
      final answered =
          replica.state.invites[id]?.status != InviteStatus.pending;
      if (answered) {
        _uninvited?.call(id);
      }
      return answered;
    });
  }

  void _toHome(List<SessionMessage> messages) {
    if (_homeFriend case final friendNumber?) {
      for (final message in messages) {
        _send(friendNumber, message);
      }
    }
  }

  void _send(int friendNumber, SessionMessage message, {bool first = false}) {
    final queue = _outbox.putIfAbsent(friendNumber, Queue.new);
    final packets = frames(message.encode());
    if (first) {
      packets.reversed.forEach(queue.addFirst);
    } else {
      queue.addAll(packets);
    }
    _flush();
  }

  void _flush() {
    _retry?.cancel();
    _retry = null;
    for (final MapEntry(key: friendNumber, value: queue) in _outbox.entries) {
      while (queue.isNotEmpty) {
        try {
          _tox.friendSendLosslessPacket(friendNumber, queue.first);
          queue.removeFirst();
        } on ApiException catch (e) {
          if (e.error ==
              Tox_Err_Friend_Custom_Packet.TOX_ERR_FRIEND_CUSTOM_PACKET_SENDQ) {
            _retry ??= Timer(_retryDelay, _flush);
          } else if (e.error ==
              Tox_Err_Friend_Custom_Packet
                  .TOX_ERR_FRIEND_CUSTOM_PACKET_FRIEND_NOT_CONNECTED) {
            // Replies to messages that came before Tox reported it online,
            // sent once it does.
          } else {
            _logger.w('Dropped sync messages to friend $friendNumber: $e');
            queue.clear();
          }
          break;
        }
      }
    }
    _outbox.removeWhere((_, queue) => queue.isEmpty);
  }
}
