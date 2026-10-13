import 'dart:async';
import 'dart:convert';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/api/toxcore/tox_constants.dart';
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_Connection, Tox_Message_Type;
import 'package:btox/logger.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/messaging.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/attachments.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/services/file_transfers.dart';
import 'package:btox/services/message_notifier.dart';
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
  );
  ref.onDispose(sync.dispose);
  ref.listen(toxEventsProvider(secretKey, nospam), (_, next) {
    if (next.value case final event?) {
      sync.handleEvent(event);
    }
  });
  sync.start();
  return sync;
}

final _geo = RegExp(r'^geo:(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$');

// Until clients can agree on richer content, locations travel as text.
String? _toText(Content content) => switch (content) {
  TextContent(:final text) => text,
  LocationContent(:final latitude, :final longitude) =>
    'geo:$latitude,$longitude',
  _ => null,
};

Content _fromText(String text) => switch (_geo.firstMatch(text)) {
  final match? => LocationContent(
    latitude: double.parse(match[1]!),
    longitude: double.parse(match[2]!),
  ),
  null => TextContent(text: text),
};

List<String> splitMessage(String text, int maxBytes) {
  final parts = <String>[];
  var rest = text;
  while (utf8.encode(rest).length > maxBytes) {
    var end = 0;
    var bytes = 0;
    for (final rune in rest.runes) {
      final runeBytes = utf8.encode(String.fromCharCode(rune)).length;
      if (bytes + runeBytes > maxBytes) {
        break;
      }
      bytes += runeBytes;
      end += rune > 0xFFFF ? 2 : 1;
    }
    final space = rest.substring(0, end).lastIndexOf(RegExp(r'\s'));
    if (space >= end ~/ 2) {
      end = space + 1;
    }
    parts.add(rest.substring(0, end));
    rest = rest.substring(end);
  }
  parts.add(rest);
  return parts;
}

/// Keeps a profile's Tox and its database in sync. Tox starts without
/// friends, so every contact is added again on start.
final class ToxSync {
  final Database _db;
  final Tox _tox;
  final Id<Profiles> _profileId;
  final int _maxMessageLength;
  final MessageNotifier? _notifier;

  final _subscriptions = <StreamSubscription<Object?>>[];

  ProfileSettings? _settings;

  var _contacts = <Contact>[];

  var _undelivered = <Message>[];

  final _friendNumbers = <PublicKey, int>{};
  final _onlineFriends = <int>{};

  /// Kept until the database no longer lists them as undelivered, so they
  /// aren't sent twice.
  final _sent = <Id<Messages>, (int, Set<int>)>{};

  final FileTransfers _files;

  ToxSync(
    this._db,
    this._tox,
    this._profileId, {
    required int maxMessageLength,
    MessageNotifier? notifier,
    Future<String> Function()? attachmentsDirectory,
  }) : _maxMessageLength = maxMessageLength,
       _notifier = notifier,
       _files = FileTransfers(
         _db,
         _tox,
         attachmentsDirectory ?? () async => '',
       );

  void start() {
    _run('reset online states', _db.clearContactsOnline(_profileId));
    _run('cancel unfinished files', _db.cancelIncomingFiles(_profileId));
    _subscriptions
      ..add(_db.watchProfile(_profileId).listen(_updateProfile))
      ..add(_db.watchContactsFor(_profileId).listen(_updateContacts))
      ..add(
        _db.watchUndeliveredMessagesFor(_profileId).listen(_updateUndelivered),
      )
      ..add(
        _db.watchIncomingFilesFor(_profileId).listen(_files.incomingChanged),
      )
      ..add(
        _db.watchAppSettings().listen(
          (settings) => _files.autoAcceptSize = settings.autoAcceptFileSize,
        ),
      );
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _files.dispose();
    _run('reset online states', _db.clearContactsOnline(_profileId));
  }

  void handleEvent(Event event) {
    switch (event) {
      case ToxEventFriendConnectionStatus(
        :final friendNumber,
        :final connectionStatus,
      ):
        final online = connectionStatus != Tox_Connection.TOX_CONNECTION_NONE;
        if (_publicKeyOf(friendNumber) case final publicKey?) {
          _run(
            'update online state',
            _db.updateContactOnline(_profileId, publicKey, online),
          );
        }
        if (!online) {
          _onlineFriends.remove(friendNumber);
          _files.friendOffline(friendNumber);
          // Tox forgets the messages it hasn't delivered yet.
          _sent.removeWhere(
            (_, sent) => sent.$1 == friendNumber && sent.$2.isNotEmpty,
          );
        } else {
          _onlineFriends.add(friendNumber);
          _acceptFriendRequests(friendNumber);
          _sendMessages();
        }
      case ToxEventFriendReadReceipt(:final friendNumber, :final messageId):
        for (final MapEntry(key: id, value: (friend, parts)) in _sent.entries) {
          if (friend == friendNumber && parts.remove(messageId)) {
            if (parts.isEmpty) {
              _run('mark message delivered', _db.markMessageDelivered(id));
            }
            break;
          }
        }
      case ToxEventFriendMessage(:final friendNumber, :final message):
        _receive(friendNumber, utf8.decode(message, allowMalformed: true));
      case ToxEventFriendName(:final friendNumber, :final name):
        if (_publicKeyOf(friendNumber) case final publicKey?) {
          _run(
            'save friend name',
            _db.updateContactName(
              _profileId,
              publicKey,
              utf8.decode(name, allowMalformed: true),
            ),
          );
        }
      case ToxEventFriendRequest(:final publicKey, :final message):
        _logger.i('Received friend request from ${publicKey.toJson()}');
        _run(
          'save friend request',
          _db.addFriendRequest(
            FriendRequestsCompanion.insert(
              profileId: _profileId,
              publicKey: publicKey,
              message: utf8.decode(message, allowMalformed: true),
              timestamp: DateTime.now().toUtc(),
            ),
          ),
        );
      case ToxEventFileRecv(
        :final friendNumber,
        :final fileNumber,
        :final kind,
        :final fileSize,
        :final filename,
      ):
        if (_contactOf(friendNumber) case final contact?) {
          _run(
            'receive file',
            _files.offered(
              contact,
              friendNumber,
              fileNumber,
              kind,
              fileSize,
              utf8.decode(filename, allowMalformed: true),
            ),
          );
        }
      case final ToxEventFileRecvChunk e:
        _files.received(e.friendNumber, e.fileNumber, e.position, e.data);
      case final ToxEventFileChunkRequest e:
        _files.requested(e.friendNumber, e.fileNumber, e.position, e.length);
      case final ToxEventFileRecvControl e:
        _files.controlled(e.friendNumber, e.fileNumber, e.control);
      default:
        break;
    }
  }

  Contact? _contactOf(int friendNumber) {
    final publicKey = _publicKeyOf(friendNumber);
    return _contacts.where((c) => c.publicKey == publicKey).firstOrNull;
  }

  PublicKey? _publicKeyOf(int friendNumber) => _friendNumbers.entries
      .where((entry) => entry.value == friendNumber)
      .firstOrNull
      ?.key;

  void _receive(int friendNumber, String text) {
    final contact = _contactOf(friendNumber);
    if (contact == null) {
      _logger.w('Received a message from unknown friend $friendNumber');
      return;
    }
    _run(
      'save message',
      _db.addMessage(
        newMessage(
          contactId: contact.id,
          parent: null,
          merged: null,
          author: contact.publicKey,
          timestamp: DateTime.now().toUtc(),
          content: _fromText(text),
        ),
      ),
    );
    _notifier?.notify(contact, text, _settings?.nickname);
  }

  void _updateProfile(Profile profile) {
    final settings = profile.settings;
    try {
      if (settings.nickname != _settings?.nickname) {
        _tox.selfSetName(utf8.encode(settings.nickname));
      }
      if (settings.statusMessage != _settings?.statusMessage) {
        _tox.selfSetStatusMessage(utf8.encode(settings.statusMessage));
      }
    } on ApiException catch (e) {
      _logger.e('Failed to set profile info: $e');
    }
    _settings = settings;
  }

  void _updateContacts(List<Contact> contacts) {
    _contacts = contacts;
    // Requests first, so re-adding a friend as a new contact sends one.
    final ordered = [
      ...contacts.where((c) => c.friendRequestAddress != null),
      ...contacts.where((c) => c.friendRequestAddress == null),
    ];
    for (final contact in ordered) {
      if (_friendNumbers.containsKey(contact.publicKey)) {
        continue;
      }
      try {
        _friendNumbers[contact.publicKey] = switch (contact) {
          Contact(:final friendRequestAddress?) => _tox.friendAdd(
            friendRequestAddress,
            utf8.encode(contact.friendRequestMessage ?? ''),
          ),
          _ => _tox.friendAddNorequest(contact.publicKey),
        };
      } on ApiException catch (e) {
        _logger.e('Failed to add contact ${contact.id}: $e');
      }
    }
    final keys = {for (final contact in contacts) contact.publicKey};
    for (final publicKey in [..._friendNumbers.keys]) {
      if (!keys.contains(publicKey)) {
        _deleteFriend(publicKey);
      }
    }
    _sendMessages();
  }

  void _deleteFriend(PublicKey publicKey) {
    final friendNumber = _friendNumbers.remove(publicKey)!;
    _onlineFriends.remove(friendNumber);
    _sent.removeWhere((_, sent) => sent.$1 == friendNumber);
    try {
      _tox.friendDelete(friendNumber);
    } on ApiException catch (e) {
      _logger.e('Failed to delete friend $friendNumber: $e');
    }
  }

  void _updateUndelivered(List<Message> undelivered) {
    _undelivered = undelivered;
    final ids = {for (final message in undelivered) message.id};
    _sent.removeWhere((id, _) => !ids.contains(id));
    _sendMessages();
  }

  /// The friend first coming online means they accepted our request.
  void _acceptFriendRequests(int friendNumber) {
    for (final contact in _contacts) {
      if (contact.friendRequestAddress != null &&
          _friendNumbers[contact.publicKey] == friendNumber) {
        _run('clear friend request', _db.clearFriendRequest(contact.id));
      }
    }
  }

  void _sendMessages() {
    final friendNumbers = {
      for (final contact in _contacts)
        contact.id: _friendNumbers[contact.publicKey],
    };
    for (final message in _undelivered) {
      final friendNumber = friendNumbers[message.contactId];
      if (friendNumber == null ||
          !_onlineFriends.contains(friendNumber) ||
          _sent.containsKey(message.id)) {
        continue;
      }
      switch (message.content) {
        case FileContent():
          _files.send(message, friendNumber);
        case final content:
          // Other content stays undelivered until there's a protocol for it.
          if (_toText(content) case final text?) {
            _send(message.id, friendNumber, text);
          }
      }
    }
  }

  void _send(Id<Messages> id, int friendNumber, String text) {
    final parts = <int>{};
    try {
      for (final part in splitMessage(text, _maxMessageLength)) {
        parts.add(
          _tox.friendSendMessage(
            friendNumber,
            Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
            utf8.encode(part),
          ),
        );
      }
      _sent[id] = (friendNumber, parts);
    } on ApiException catch (e) {
      _logger.w('Failed to send message $id: $e');
    }
  }

  void _run(String what, Future<void> future) {
    future.catchError((Object e) => _logger.e('Failed to $what: $e'));
  }
}
