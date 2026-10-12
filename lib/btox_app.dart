import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/pages/contact_list_page.dart';
import 'package:btox/pages/create_profile_page.dart';
import 'package:btox/pages/select_profile_page.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/services/tox_message_service.dart';
import 'package:btox/services/tox_outbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class BtoxApp extends ConsumerWidget {
  final GlobalKey<NavigatorState>? navigatorKey;

  const BtoxApp({super.key, this.navigatorKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'bTox',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.blue),
      home: _appContent(ref),
    );
  }

  Widget _appContent(WidgetRef ref) {
    if (!AnyPlatform.instance.isMobile) {
      // Initialize the background message handler.
      ref.watch(toxMessageServiceProvider);
      ref.watch(activeToxOutboxProvider);
    } else {
      // Subscribing tells the background service that the UI is open.
      ref.watch(connectionStatusProvider);
    }

    return ref
        .watch(profilesProvider)
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) =>
              Scaffold(body: Center(child: Text('Error: $error'))),
          data: (profiles) {
            final activeProfile = ref.watch(activeProfileProvider);

            if (profiles.isEmpty) {
              return const CreateProfilePage();
            }

            if (activeProfile == null) {
              return const SelectProfilePage();
            }

            return const ContactListPage();
          },
        );
  }
}
