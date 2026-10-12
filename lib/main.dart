import 'package:btox/background_service.dart';
import 'package:btox/btox_app.dart';
import 'package:btox/pages/chat_page.dart';
import 'package:btox/services/message_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  await initializeService();
  await handleNotificationTaps(
    (contactId) => _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => ChatPage(contactId: contactId)),
    ),
  );
  runApp(ProviderScope(child: BtoxApp(navigatorKey: _navigatorKey)));
}
