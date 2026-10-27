import 'package:btox/background_service.dart';
import 'package:btox/btox_app.dart';
import 'package:btox/db/database.dart';
import 'package:btox/pages/chat_page.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/provider_error_logger.dart';
import 'package:btox/services/message_notifier.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  await initializeService();
  final container = ProviderContainer(observers: const [ProviderErrorLogger()]);
  await handleNotificationTaps(
    (chat) => switch (_navigatorKey.currentState) {
      final navigator? => ChatPage.open(navigator, chat),
      null => null,
    },
    // Friend requests and invites show above the profile's chats.
    openRequests: (profile) async {
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      final db = await container.read(databaseProvider.future);
      // A notification from version 1 names a contact instead.
      if ((await db.watchProfiles().first).any((p) => p.id == profile)) {
        await db.updateAppSettings(
          AppSettingsCompanion(currentProfile: Value(profile)),
        );
      }
    },
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: BtoxApp(navigatorKey: _navigatorKey),
    ),
  );
}
