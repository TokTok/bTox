import 'dart:async';
import 'dart:convert';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/messaging.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/services/message_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logger = Logger(['ToxMessageService']);

/// A service that listens to Tox events and persists them to the database.
final toxMessageServiceProvider = Provider<ToxMessageService>((ref) {
  final service = ToxMessageService(ref);
  service._init();
  return service;
});

final class ToxMessageService {
  final Ref _ref;
  ProviderSubscription? _subscription;

  ToxMessageService(this._ref);

  void _init() {
    // Watch for changes in the active profile.
    _ref.listen(activeProfileProvider, (previous, next) {
      _startListening(next);
    }, fireImmediately: true);
  }

  void _startListening(Profile? profile) {
    _subscription?.close();
    if (profile == null) return;

    // Listen to events for this specific profile.
    _subscription = _ref.listen(
      toxEventsProvider(profile.secretKey, profile.nospam),
      (previous, next) {
        final event = next.value;
        if (event != null) {
          _handleEvent(profile, event);
        }
      },
    );
  }

  Future<void> _handleEvent(Profile profile, Event event) async {
    final database = await _ref.read(databaseProvider.future);
    final tox = await _ref.read(
      toxProvider(profile.secretKey, profile.nospam).future,
    );

    switch (event) {
      case ToxEventFriendMessage(
        friendNumber: final friendNum,
        message: final msgBytes,
      ):
        try {
          final senderKey = tox.getFriendPublicKey(friendNum);

          // Find the contact in the database by public key.
          final contacts =
              await (database.select(database.contacts)
                    ..where((c) => c.publicKey.equals(senderKey.toJson()))
                    ..where((c) => c.profileId.equals(profile.id.value)))
                  .get();

          if (contacts.isNotEmpty) {
            final contact = contacts.first;
            final text = utf8.decode(msgBytes, allowMalformed: true);
            await database.addMessage(
              newMessage(
                contactId: contact.id,
                parent: null,
                merged: null,
                author: senderKey,
                timestamp: DateTime.now().toUtc(),
                content: TextContent(text: text),
              ),
            );
            _ref.read(messageNotifierProvider)?.notify(contact, text);
          } else {
            _logger.w(
              'Received message from unknown contact: ${senderKey.toJson()}',
            );
          }
        } catch (e) {
          _logger.e('Error handling friend message: $e');
        }
        break;

      case ToxEventFriendName(:final friendNumber, :final name):
        try {
          await database.updateContactName(
            profile.id,
            tox.getFriendPublicKey(friendNumber),
            utf8.decode(name, allowMalformed: true),
          );
        } catch (e) {
          _logger.e('Error handling friend name: $e');
        }
        break;

      case ToxEventFriendRequest(publicKey: final pubKey, :final message):
        _logger.i('Received friend request from ${pubKey.toJson()}');
        try {
          await database.addFriendRequest(
            FriendRequestsCompanion.insert(
              profileId: profile.id,
              publicKey: pubKey,
              message: utf8.decode(message, allowMalformed: true),
              timestamp: DateTime.now().toUtc(),
            ),
          );
        } catch (e) {
          _logger.e('Error handling friend request: $e');
        }
        break;

      default:
        break;
    }
  }
}
