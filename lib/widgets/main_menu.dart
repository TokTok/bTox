import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/connection_status.dart';
import 'package:btox/pages/select_profile_page.dart';
import 'package:btox/pages/settings_page.dart';
import 'package:btox/pages/user_profile_page.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/providers/contacts.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logger = Logger(['MainMenu']);

final class MainMenu extends ConsumerWidget {
  final Profile profile;
  final Database database;

  const MainMenu({super.key, required this.profile, required this.database});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final others = ref
        .watch(signedInProfilesProvider)
        .where((p) => p.id != profile.id);
    final l10n = AppLocalizations.of(context)!;

    void open(Widget page) {
      Navigator.pop(context); // close drawer before navigating away
      Navigator.push(context, MaterialPageRoute(builder: (context) => page));
    }

    return NavigationDrawer(
      children: [
        DrawerHeader(
          decoration: const BoxDecoration(color: Colors.blue),
          child: ListTile(
            title: Text(
              profile.settings.nickname,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            subtitle: Text(
              profile.settings.statusMessage,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            trailing: CircleIdenticon(publicKey: profile.publicKey),
          ),
        ),
        for (final other in others)
          ListTile(
            leading: SizedBox.square(
              dimension: 32,
              child: CircleIdenticon(publicKey: other.publicKey),
            ),
            title: Text(other.settings.nickname),
            subtitle: Text(
              connectionStatusText(
                ref.watch(connectionStatusesProvider)?[other.id],
              ),
            ),
            trailing: switch (ref
                .watch(unreadCountsProvider(other.id))
                .value
                ?.values
                .fold(0, (sum, count) => sum + count)) {
              null || 0 => null,
              final unread => Badge(label: Text('$unread')),
            },
            onTap: () {
              Navigator.pop(context); // close drawer before switching
              database.updateAppSettings(
                AppSettingsCompanion(currentProfile: Value(other.id)),
              );
            },
          ),
        if (others.isNotEmpty) const Divider(),
        ListTile(
          leading: const Icon(Icons.person),
          title: Text(l10n.menuProfile),
          onTap: () => open(UserProfilePage(profileId: profile.id)),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: Text(l10n.menuSettings),
          onTap: () => open(SettingsPage(database: database, profile: profile)),
        ),
        ListTile(
          leading: const Icon(Icons.switch_account),
          title: Text(l10n.accounts),
          onTap: () => open(const SelectProfilePage()),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(l10n.logout),
          onTap: () async {
            Navigator.pop(context); // close drawer before navigating away
            _logger.d('Signing out profile ${profile.id}');
            await database.signOut(profile.id);
          },
        ),
      ],
    );
  }
}
