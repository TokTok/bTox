import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/api/toxcore/tox_constants.dart';
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/attachments/attachments.dart';
import 'package:btox/calls/call_audio.dart';
import 'package:btox/calls/call_channel.dart';
import 'package:btox/calls/call_video.dart';
import 'package:btox/calls/calls.dart';
import 'package:btox/calls/plugin_call_media.dart';
import 'package:btox/calls/relay_protocol.dart';
import 'package:btox/calls/toxav_protocol.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_Connection, Tox_Message_Type;
import 'package:btox/logger.dart';
import 'package:btox/messages/split_message.dart';
import 'package:btox/messages/formats.dart';
import 'package:btox/messages/message_format.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/attachments.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/message_formats.dart'
    show knownMessageFormatsProvider;
import 'package:btox/providers/profiles.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/services/file_transfers.dart';
import 'package:btox/services/message_notifier.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/frames.dart';
import 'package:btox/sync/home.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/sync/sync_sessions.dart';
import 'package:clock/clock.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tox_sync.g.dart';

const _logger = Logger(['ToxSync']);

/// Only the Tox owner may watch this.
@riverpod
Future<ToxSync> toxSync(
  Ref ref,
  Id<Profiles> profileId,
  SecretKey secretKey,
  ToxAddressNospam nospam,
) async {
  final db = await ref.watch(databaseProvider.future);
  final tox = await ref.watch(toxProvider(secretKey, nospam).future);

  final sync = ToxSync(
    db,
    tox,
    profileId,
    maxMessageLength: toxMaxMessageLength,
    notifier: ref.watch(messageNotifierProvider),
    attachmentsDirectory: () => ref.read(attachmentsDirectoryProvider.future),
    knownFormats: ref.watch(knownMessageFormatsProvider),
    callAudio: AnyPlatform.instance.isWeb ? null : PluginCallAudio(),
    callVideo: AnyPlatform.instance.isWeb ? null : PluginCallVideo(),
  );
  ref.onDispose(sync.dispose);
  sync.start();
  runTox(
    ref,
    tox,
    ref.watch(networkSettingsProvider(secretKey))!,
    sync.handleEvent,
  );
  return sync;
}

/// One of our messages on its way to a friend, in the parts Tox takes.
final class _Outgoing {
  final int friendNumber;
  final Tox_Message_Type kind;
  final List<Uint8List> parts;
  // Tox delivers in order, so the delivered parts are the first ones.
  var delivered = 0;
  // Tox's IDs of the parts after those that it has.
  final pending = <int>[];

  _Outgoing(this.friendNumber, this.kind, this.parts);

  int get next => delivered + pending.length;
}

/// Keeps a profile's Tox and its events in sync. A profile this device runs
/// is its account's home: what Tox does becomes events, and what the pages
/// ask for becomes events and Tox calls. Tox starts without friends, so every
/// friend is added again on start.
final class ToxSync {
  final Database _db;
  final Tox _tox;
  final Id<Profiles> _profileId;
  final int _maxMessageLength;
  final Duration _retryDelay;
  final MessageNotifier? _notifier;
  final List<MessageFormat> _knownFormats;

  final _subscriptions = <StreamSubscription<Object?>>[];
  final _connectionChanges = StreamController<Tox_Connection>.broadcast();
  var _disposed = false;

  Profile? _profile;
  Home? _home;

  final _friendNumbers = <PublicKey, int>{};
  // The request each friend was added to Tox with, if any.
  final _requests = <PublicKey, (ToxAddress, String?)?>{};
  // The friend requests that came since starting.
  final _toldRequests = <PublicKey, String>{};
  final _onlineFriends = <int>{};

  /// Our messages on their way, by their Send event.
  final _outgoing = <EventId, _Outgoing>{};
  // Sends what Tox didn't take again, if nothing else does first.
  Timer? _retry;

  var _transfers = const <Transfer>[];

  late final FileTransfers _files;
  final SyncSessions _syncSessions;

  // Where calls can be made, and once the account runs.
  final CallAudio? _callAudio;
  final CallVideo? _callVideo;
  Calls? _calls;

  ToxSync(
    this._db,
    this._tox,
    this._profileId, {
    required int maxMessageLength,
    Duration retryDelay = const Duration(seconds: 1),
    MessageNotifier? notifier,
    Future<String> Function()? attachmentsDirectory,
    List<MessageFormat> knownFormats = messageFormats,
    CallAudio? callAudio,
    CallVideo? callVideo,
  }) : _maxMessageLength = maxMessageLength,
       _callAudio = callAudio,
       _callVideo = callVideo,
       _retryDelay = retryDelay,
       _notifier = notifier,
       _knownFormats = knownFormats,
       _syncSessions = SyncSessions(
         _db,
         _tox,
         _profileId,
         directory: attachmentsDirectory,
         notify: notifier?.notify,
         read: notifier?.read,
         invited: notifier == null
             ? null
             : (id, invite, from, account) =>
                   notifier.invited(_profileId, id, invite, from, account),
         uninvited: notifier?.uninvited,
       ) {
    _files = FileTransfers(
      _db,
      _tox,
      _profileId,
      attachmentsDirectory ?? () async => '',
      (graph, content) => isIncoming(content)
          ? _recordIncoming(graph, content)
          : _home!.record(graph, content),
    );
  }

  Tox_Connection get connection => _tox.selfGetConnectionStatus();

  Stream<Tox_Connection> get connectionChanges => _connectionChanges.stream;

  void start() {
    _logger.unawaited('forget live facts', _db.clearLiveFacts(_profileId));
    _subscriptions
      ..add(_db.watchProfile(_profileId).listen(_updateProfile))
      ..add(
        _db.watchAppSettings().listen((settings) {
          _files.autoAcceptSize = settings.autoAcceptFileSize;
          _syncSessions.autoAcceptSize = settings.autoAcceptFileSize;
        }),
      );
  }

  void dispose() {
    _disposed = true;
    _calls?.dispose();
    if (_calls != null) {
      CallHost.instance.remove(_profileId);
    }
    _retry?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _files.dispose();
    _syncSessions.dispose();
    _connectionChanges.close();
    _logger.unawaited('forget live facts', _db.clearLiveFacts(_profileId));
  }

  void handleEvent(Event event) {
    switch (event) {
      case ToxEventSelfConnectionStatus(:final connectionStatus):
        _connectionChanges.add(connectionStatus);
      case ToxEventFriendConnectionStatus(
        :final friendNumber,
        :final connectionStatus,
      ):
        final online = connectionStatus != Tox_Connection.TOX_CONNECTION_NONE;
        final publicKey = _publicKeyOf(friendNumber);
        // A linked account's friends' states come from its home device.
        if (publicKey != null && _home != null) {
          _logger.unawaited(
            'update online state',
            _db.updateLiveFacts(_profileId, [
              (
                Subject.friend(publicKey),
                FactValue.connection(Connection.values[connectionStatus.value]),
              ),
            ]),
          );
        }
        // Toxcore also says when only the connection changes, as between
        // UDP and TCP: the friend was online all along.
        if (online == _onlineFriends.contains(friendNumber)) {
          break;
        }
        if (!online) {
          _onlineFriends.remove(friendNumber);
          _files.friendOffline(friendNumber);
          if (publicKey != null) {
            _calls?.friendOffline(publicKey);
          }
          _syncSessions.offline(friendNumber);
          // Tox forgets the messages it hasn't delivered yet.
          for (final message in _outgoing.values) {
            if (message.friendNumber == friendNumber) {
              message.pending.clear();
            }
          }
        } else {
          _onlineFriends.add(friendNumber);
          if (publicKey != null) {
            _syncSessions.online(friendNumber, publicKey);
            _accepted(publicKey);
          }
          _sendMessages();
        }
      case ToxEventFriendLosslessPacket(:final friendNumber, :final data)
          when data.isNotEmpty && data[0] == syncPacketId:
        if (_publicKeyOf(friendNumber) case final publicKey?) {
          _syncSessions.received(friendNumber, publicKey, data);
        }
      case ToxEventFriendReadReceipt(:final friendNumber, :final messageId):
        for (final MapEntry(key: id, value: message) in _outgoing.entries) {
          if (message.friendNumber == friendNumber &&
              message.pending.remove(messageId)) {
            if (++message.delivered == message.parts.length) {
              _delivered(id);
            }
            break;
          }
        }
      case ToxEventFriendMessage(
        :final friendNumber,
        :final type,
        :final message,
      ):
        _receive(friendNumber, type, message);
      case ToxEventFriendName(:final friendNumber, :final name):
        if (_publicKeyOf(friendNumber) case final pk?) {
          _home?.named(pk, utf8.decode(name, allowMalformed: true));
        }
      case ToxEventFriendRequest(:final publicKey, :final message):
        _logger.i('Received friend request from ${publicKey.toJson()}');
        if (_home case final home?) {
          final text = utf8.decode(message, allowMalformed: true);
          if (home.declined(publicKey, text)) {
            break;
          }
          final known = home.state.friends[publicKey];
          // Sent again, as clients do, it's the same request.
          if (known?.request == text || _toldRequests[publicKey] == text) {
            break;
          }
          _toldRequests[publicKey] = text;
          home.record(
            home.account,
            FriendRequested(pk: publicKey, message: text),
          );
          if (known?.wanted != true) {
            _notifier?.request?.call(
              _profileId,
              publicKey,
              text,
              _profile?.settings.nickname,
            );
          }
        }
      case ToxEventFileRecv(
        :final friendNumber,
        :final fileNumber,
        :final kind,
        :final fileSize,
        :final filename,
      ):
        final home = _home;
        if (home == null) {
          // A linked account's files come from its home device.
          if (_syncSessions.files case final files?) {
            files.offered(friendNumber, fileNumber, kind, fileSize);
          } else {
            _files.decline(friendNumber, fileNumber);
          }
        } else if (_publicKeyOf(friendNumber) case final pk?) {
          _logger.unawaited(
            'receive file',
            _files.offered(
              home.chatWith(pk),
              home.state.friends[pk]?.name ?? '',
              friendNumber,
              fileNumber,
              kind,
              fileSize,
              utf8.decode(filename, allowMalformed: true),
            ),
          );
        }
      case final ToxEventFileRecvChunk e:
        if (_syncSessions.files case final files?) {
          files.chunk(e.friendNumber, e.fileNumber, e.position, e.data);
        } else {
          _files.received(e.friendNumber, e.fileNumber, e.position, e.data);
        }
      case final ToxEventFileChunkRequest e:
        if (_syncSessions.files case final files?) {
          files.requested(e.friendNumber, e.fileNumber, e.position, e.length);
        } else {
          _files.requested(e.friendNumber, e.fileNumber, e.position, e.length);
        }
      case final ToxEventFileRecvControl e:
        if (_syncSessions.files case final files?) {
          files.controlled(e.friendNumber, e.fileNumber, e.control);
        } else {
          _files.controlled(e.friendNumber, e.fileNumber, e.control);
        }
      default:
        break;
    }
  }

  PublicKey? _publicKeyOf(int friendNumber) => _friendNumbers.entries
      .where((entry) => entry.value == friendNumber)
      .firstOrNull
      ?.key;

  void _receive(int friendNumber, Tox_Message_Type type, Uint8List message) {
    final home = _home;
    final pk = _publicKeyOf(friendNumber);
    final friend = home?.state.friends[pk];
    if (home == null || pk == null || friend == null || !friend.wanted) {
      _logger.w('Received a message from unknown friend $friendNumber');
      return;
    }
    _logger.unawaited(
      'save a message',
      _recordIncoming(
        home.chatWith(pk),
        Received(sender: friend.name ?? '', message: message, kind: type),
      ),
    );
  }

  /// Records a friend's message or file, and shows it unless it repeats one.
  Future<NewEvent?> _recordIncoming(GraphId chat, EventContent content) async {
    final home = _home!;
    final recorded = await home.record(chat, content);
    if (recorded case (final id, final event, _)
        when !home.earlier.repeats(id, event, _formats)) {
      final listed = notifying(
        [
          (
            sender: null,
            text: notificationText(content, _formats),
            time: DateTime.fromMillisecondsSinceEpoch(event.time),
          ),
        ],
        home.state.setting<Mute>(Scope.conversation(chat)),
        clock.now(),
        [_nickname],
      );
      if (listed.isNotEmpty) {
        _notifier?.notify(
          ChatRef(_profileId, chat),
          home.state.friends[home.friendOf(chat)]?.name,
          listed,
          _profile?.settings.nickname,
        );
      }
    }
    return recorded;
  }

  void _updateProfile(Profile profile) {
    final first = _profile == null;
    final settings = profile.settings;
    try {
      if (settings.nickname != _profile?.settings.nickname) {
        _tox.selfSetName(utf8.encode(settings.nickname));
      }
      if (settings.statusMessage != _profile?.settings.statusMessage) {
        _tox.selfSetStatusMessage(utf8.encode(settings.statusMessage));
      }
    } on ApiException catch (e) {
      _logger.e('Failed to set profile info: $e');
    }
    _profile = profile;
    _syncSessions
      ..formats = _formats
      ..link(profile.publicKey, profile.home?.publicKey);
    if (!first) {
      _home?.profileChanged(settings);
      return;
    }
    if (profile.home case final home?) {
      _subscriptions
        ..add(_db.watchSends(_profileId).listen(_syncSessions.sendsChanged))
        ..add(_db.watchReads(_profileId).listen(_syncSessions.readsChanged))
        ..add(
          _db.watchFileAnswers(_profileId).listen(_syncSessions.answersChanged),
        )
        ..add(
          _db
              .watchInviteAnswers(_profileId)
              .listen(_syncSessions.inviteAnswersChanged),
        )
        ..add(
          _db.watchChatMerges(_profileId).listen(_syncSessions.mergesChanged),
        )
        ..add(
          _db.watchRelayBots(_profileId).listen(_syncSessions.relayBotsChanged),
        )
        ..add(
          _db
              .watchSettingChanges(_profileId)
              .listen(_syncSessions.settingsChanged),
        )
        ..add(
          _db.watchTransfers(_profileId).listen(_syncSessions.transfersChanged),
        );
      _addFriend(
        home.publicKey,
        profile.pairingMessage == null ? null : home,
        profile.pairingMessage,
      );
      _startRelayedCalls(home.publicKey);
    } else {
      _logger.unawaited('load the account', _startHome(profile));
    }
  }

  /// A linked account's calls, which its home device connects this device
  /// to, and records.
  void _startRelayedCalls(PublicKey account) {
    final audio = _callAudio;
    if (audio == null) {
      return;
    }
    final relay = RelayProtocol(
      _tox.startAv(),
      homeNumber: () => _syncSessions.homeFriend,
      toHome: _syncSessions.toHome,
    );
    _syncSessions.onLiveFacts = relay.facts;
    final calls = _calls = Calls(
      _profileId,
      account,
      relay,
      audio,
      video: _callVideo,
      notifier: _notifier?.calls,
      chatOf: (friend) => GraphId.friend(account, friend),
      nameOf: _syncSessions.friendName,
      selfName: () => _syncSessions.accountName,
      record: (_, _) async => null,
      changed: (call) => CallHost.instance.changed(_profileId, call),
      busyElsewhere: () => CallHost.instance.busyElsewhere(_profileId),
      showVideo: CallHost.instance.showVideo,
    );
    CallHost.instance.add(_profileId, calls);
  }

  Future<void> _startHome(Profile profile) async {
    final home = await Home.load(_db, profile);
    if (_disposed) {
      return;
    }
    _home = home;
    // Toxcore forgets unfinished incoming files when it stops.
    for (final transfer in await _db.watchTransfers(_profileId).first) {
      if (_disposed) {
        return;
      }
      if (transfer case Transfer(
        incoming: true,
        :final event?,
        state: FileState.offered || FileState.active,
      )) {
        await _db.setTransferState(transfer.id, FileState.paused);
        await home.record(transfer.graph, FileEnded(file: event, ok: false));
      }
    }
    // And calls, which ended unrecorded.
    for (final graph in home.store.graphs) {
      final events = home.store.eventsIn(graph);
      final ended = {
        for (final (_, event) in events)
          if (event.content case CallEnded(:final call)) call,
      };
      for (final (id, event) in events) {
        if (_disposed) {
          return;
        }
        if (event.content is Call && !ended.contains(id)) {
          await home.record(graph, CallEnded(call: id));
        }
      }
    }
    _notifier?.calls?.stopRinging(_profileId);
    await home.profileChanged(profile.settings);
    if (_disposed) {
      return;
    }
    _updateFriends();
    if (_callAudio case final audio?) {
      final calls = _calls = Calls(
        _profileId,
        home.me,
        ToxavProtocol(_tox.startAv(), (pk) => _friendNumbers[pk], _publicKeyOf),
        audio,
        video: _callVideo,
        notifier: _notifier?.calls,
        chatOf: home.chatWith,
        nameOf: (pk) => home.state.friends[pk]?.name,
        selfName: () => _nickname,
        record: home.record,
        changed: (call) => CallHost.instance.changed(_profileId, call),
        busyElsewhere: () => CallHost.instance.busyElsewhere(_profileId),
        showVideo: CallHost.instance.showVideo,
      );
      CallHost.instance.add(_profileId, calls);
    }
    _subscriptions
      ..add(_db.watchFriendChanges(_profileId).listen(_friendChanges))
      ..add(_db.watchSends(_profileId).listen(_sends))
      ..add(_db.watchReads(_profileId).listen(_reads))
      ..add(_db.watchSettingChanges(_profileId).listen(_settings))
      ..add(_db.watchTransfers(_profileId).listen(_transfersChanged));
  }

  void _friendChanges(List<FriendChange> changes) => _logger.unawaited(
    'write friend changes',
    _home!.friendChanges(changes).then((files) {
      for (final file in files) {
        _logger.unawaited('delete $file', deleteAttachment(file));
      }
      _updateFriends();
    }),
  );

  void _sends(List<ChatSend> sends) => _logger.unawaited(
    'write sends',
    _home!.sends(sends, _nickname).then((_) => _sendMessages()),
  );

  void _reads(List<ChatRead> reads) =>
      _logger.unawaited('write read marks', _home!.reads(reads));

  void _settings(List<SettingChange> changes) =>
      _logger.unawaited('write settings', _home!.settings(changes));

  void _transfersChanged(List<Transfer> transfers) {
    _transfers = transfers;
    _files.incomingChanged(transfers);
    _logger.unawaited(
      'start files',
      _home!.startFiles(transfers, _nickname).then((_) => _sendMessages()),
    );
  }

  String get _nickname => _profile?.settings.nickname ?? '';

  MessageFormats get _formats => formatsOn(
    _knownFormats,
    _profile?.settings.messageFormatsOff ?? const [],
  );

  /// Makes Tox's friends the account's.
  void _updateFriends() {
    final friends = _home!.state.friends;
    // Requests first, so re-adding a friend as a new contact sends one.
    for (final requested in [true, false]) {
      for (final MapEntry(key: pk, value: friend) in friends.entries) {
        if (friend.wanted && (friend.nospam != null) == requested) {
          _addFriend(pk, switch (friend.nospam) {
            final nospam? => ToxAddress.of(pk, nospam),
            null => null,
          }, friend.requestMessage);
        }
      }
    }
    for (final pk in [..._friendNumbers.keys]) {
      if (friends[pk]?.wanted != true) {
        _deleteFriend(pk);
      }
    }
    _sendMessages();
  }

  /// Adds [pk] to Tox, with a friend request to [address] if there is one.
  /// A new request to a friend already added, such as one who deleted us,
  /// adds them again to send it.
  void _addFriend(PublicKey pk, ToxAddress? address, [String? message]) {
    final request = address == null ? null : (address, message);
    if (_friendNumbers.containsKey(pk)) {
      if (request == null || request == _requests[pk]) {
        return;
      }
      _deleteFriend(pk);
    }
    try {
      _friendNumbers[pk] = address == null
          ? _tox.friendAddNorequest(pk)
          : _tox.friendAdd(address, utf8.encode(message ?? ''));
      _requests[pk] = request;
    } on ApiException catch (e) {
      _logger.e('Failed to add friend ${pk.toJson()}: $e');
    }
  }

  void _deleteFriend(PublicKey publicKey) {
    final friendNumber = _friendNumbers.remove(publicKey)!;
    _requests.remove(publicKey);
    _onlineFriends.remove(friendNumber);
    _calls?.friendOffline(publicKey);
    _syncSessions.offline(friendNumber);
    _outgoing.removeWhere((_, message) => message.friendNumber == friendNumber);
    _files.friendOffline(friendNumber);
    try {
      _tox.friendDelete(friendNumber);
    } on ApiException catch (e) {
      _logger.e('Failed to delete friend $friendNumber: $e');
    }
  }

  /// A friend first coming online means they accepted our request.
  void _accepted(PublicKey pk) {
    if (_profile?.home?.publicKey == pk) {
      if (_profile?.pairingMessage != null) {
        _logger.unawaited(
          'clear the pairing request',
          _db.clearPairingMessage(_profileId),
        );
      }
      return;
    }
    if (_requests.containsKey(pk)) {
      _requests[pk] = null;
    }
    _home?.accepted(pk);
  }

  void _delivered(EventId id) {
    _outgoing.remove(id);
    _home?.delivered(id);
  }

  void _sendMessages() {
    _retry?.cancel();
    _retry = null;
    final home = _home;
    if (home == null) {
      return;
    }
    for (final MapEntry(key: id, value: pk) in home.undelivered.entries) {
      final friendNumber = _friendNumbers[pk];
      if (friendNumber == null || !_onlineFriends.contains(friendNumber)) {
        continue;
      }
      if (home.store[id]?.content case Send(:final message, :final kind)) {
        _send(
          id,
          _outgoing[id] ??= _Outgoing(
            friendNumber,
            kind,
            splitMessage(message, _maxMessageLength),
          ),
        );
      }
    }
    for (final transfer in _transfers) {
      if (home.friendOf(transfer.graph) case final pk?) {
        if (_friendNumbers[pk] case final friendNumber?
            when _onlineFriends.contains(friendNumber)) {
          _files.send(transfer, friendNumber);
        }
      }
    }
  }

  /// Gives Tox the parts of [message] it doesn't have, from where it
  /// stopped taking them.
  void _send(EventId id, _Outgoing message) {
    if (message.next == message.parts.length) {
      return;
    }
    try {
      while (message.next < message.parts.length) {
        message.pending.add(
          _tox.friendSendMessage(
            message.friendNumber,
            message.kind,
            message.parts[message.next],
          ),
        );
      }
    } on ApiException catch (e) {
      _logger.w('Failed to send message $id: $e');
      _retry ??= Timer(_retryDelay, _sendMessages);
      return;
    }
    _home!.sent(id);
  }
}
