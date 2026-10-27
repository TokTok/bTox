import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/pages/contact_list_page.dart';
import 'package:btox/pages/create_profile_page.dart';
import 'package:btox/pages/select_profile_page.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/widgets/load_failed.dart';
import 'package:btox/widgets/system_gestures.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      builder: leaveSystemSwipes,
      home: _appContent(ref),
    );
  }

  Widget _appContent(WidgetRef ref) {
    // Subscribing tells the background service that the UI is open.
    ref.watch(connectionStatusesProvider);

    return ref
        .watch(profilesProvider)
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, _) => const Scaffold(body: LoadFailed()),
          data: (profiles) {
            final currentProfile = ref.watch(currentProfileProvider);

            if (profiles.isEmpty) {
              return const CreateProfilePage();
            }

            if (currentProfile == null) {
              return const SelectProfilePage();
            }

            return const ContactListPage();
          },
        );
  }
}
