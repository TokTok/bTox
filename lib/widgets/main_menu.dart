import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/pages/settings_page.dart';
import 'package:btox/pages/user_profile_page.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logger = Logger(['MainMenu']);

final class MainMenu extends ConsumerWidget {
  final ToxConstants constants;
  final Profile profile;
  final Database database;

  const MainMenu({
    super.key,
    required this.constants,
    required this.profile,
    required this.database,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        ListTile(
          leading: const Icon(Icons.person),
          title: Text(AppLocalizations.of(context)!.menuProfile),
          onTap: () {
            Navigator.pop(context); // close drawer before navigating away
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfilePage(
                  constants: constants,
                  profileId: profile.id,
                ),
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: Text(AppLocalizations.of(context)!.menuSettings),
          onTap: () {
            Navigator.pop(context); // close drawer before navigating away
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    SettingsPage(database: database, profile: profile),
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(AppLocalizations.of(context)!.logout),
          onTap: () async {
            Navigator.pop(context); // close drawer before navigating away
            _logger.d('Logging out');
            await database.deactivateProfiles();
          },
        ),
      ],
    );
  }
}
