import 'dart:async';
import 'dart:convert';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_Connection;
import 'package:btox/logger.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/providers/tox.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tox_outbox.g.dart';

const _logger = Logger(['ToxOutbox']);

/// Only the Tox owner may watch this.
@riverpod
Future<ToxOutbox> toxOutbox(
  Ref ref,
  Id<Profiles> profileId,
  SecretKey secretKey,
  ToxAddressNospam nospam,
) async {
  final db = await ref.watch(databaseProvider.future);
  final tox = await ref.watch(toxProvider(secretKey, nospam).future);
  final constants = await ref.watch(toxConstantsProvider.future);

  final outbox = ToxOutbox(
    db,
    tox,
    profileId,
    maxMessageLength: constants.maxMessageLength,
  );
  ref.onDispose(outbox.dispose);
  ref.listen(toxEventsProvider(secretKey, nospam), (_, next) {
    if (next.value case final event?) {
      outbox.handleEvent(event);
    }
  });
  outbox.start();
  return outbox;
}

final activeToxOutboxProvider = Provider<void>((ref) {
  final profile = ref.watch(activeProfileProvider);
  if (profile != null) {
    ref.watch(toxOutboxProvider(profile.id, profile.secretKey, profile.nospam));
  }
});

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

/// Tox starts without friends, so every contact is added again on start.
final class ToxOutbox {
  final Database _db;
  final Tox _tox;
  final Id<Profiles> _profileId;
  final int _maxMessageLength;

  final _subscriptions = <StreamSubscription<Object?>>[];

  ProfileSettings? _settings;

  var _contacts = <Contact>[];

  var _undelivered = <Message>[];

  final _friendNumbers = <PublicKey, int>{};
  final _onlineFriends = <int>{};

  /// Kept until the database no longer lists them as undelivered, so they
  /// aren't sent twice.
  final _sent = <Id<Messages>, (int, Set<int>)>{};

  ToxOutbox(
    this._db,
    this._tox,
    this._profileId, {
    required int maxMessageLength,
  }) : _maxMessageLength = maxMessageLength;

  void start() {
    _run('reset online states', _db.clearContactsOnline(_profileId));
    _subscriptions
      ..add(_db.watchProfile(_profileId).listen(_updateProfile))
      ..add(_db.watchContactsFor(_profileId).listen(_updateContacts))
      ..add(
        _db.watchUndeliveredMessagesFor(_profileId).listen(_updateUndelivered),
      );
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _run('reset online states', _db.clearContactsOnline(_profileId));
  }

  void handleEvent(Event event) {
    switch (event) {
      case ToxEventFriendConnectionStatus(
        :final friendNumber,
        :final connectionStatus,
      ):
        final online = connectionStatus != Tox_Connection.TOX_CONNECTION_NONE;
        for (final MapEntry(key: publicKey, value: number)
            in _friendNumbers.entries) {
          if (number == friendNumber) {
            _run(
              'update online state',
              _db.updateContactOnline(_profileId, publicKey, online),
            );
          }
        }
        if (!online) {
          _onlineFriends.remove(friendNumber);
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
      default:
        break;
    }
  }

  void _updateProfile(Profile profile) {
    final settings = profile.settings;
    try {
      if (settings.nickname != _settings?.nickname) {
        _tox.name = settings.nickname;
      }
      if (settings.statusMessage != _settings?.statusMessage) {
        _tox.statusMessage = settings.statusMessage;
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
          Contact(:final friendRequestAddress?) => _tox.addFriend(
            friendRequestAddress,
            contact.friendRequestMessage ?? '',
          ),
          _ => _tox.addFriendNorequest(contact.publicKey),
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
      _tox.deleteFriend(friendNumber);
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
      // Other content stays undelivered until there's a protocol for it.
      if (message.content case TextContent(:final text)) {
        _send(message.id, friendNumber, text);
      }
    }
  }

  void _send(Id<Messages> id, int friendNumber, String text) {
    final parts = <int>{};
    try {
      for (final part in splitMessage(text, _maxMessageLength)) {
        parts.add(_tox.sendFriendMessage(friendNumber, part));
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
