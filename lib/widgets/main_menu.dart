import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/connection_status.dart';
import 'package:btox/pages/select_profile_page.dart';
import 'package:btox/pages/settings_page.dart';
import 'package:btox/pages/user_profile_page.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:btox/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['MainMenu']);

final class MainMenu extends ConsumerWidget {
  final Profile profile;

  const MainMenu({super.key, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final others = ref
        .watch(signedInProfilesProvider)
        .where((p) => p.id != profile.id);
    final l10n = AppLocalizations.of(context)!;
    final me = ref.watch(profileIdentityProvider(profile));

    void open(Widget page) {
      Navigator.pop(context); // close drawer before navigating away
      Navigator.push(context, MaterialPageRoute(builder: (context) => page));
    }

    return NavigationDrawer(
      children: [
        DrawerHeader(
          child: ListTile(
            title: Text(
              me.name ?? l10n.linkedAccount,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            subtitle: Text(
              me.statusMessage,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            trailing: CircleIdenticon(bytes: me.address.publicKey),
            onTap: () => open(UserProfilePage(profileId: profile.id)),
          ),
        ),
        for (final other in others)
          ListTile(
            leading: SizedBox.square(
              dimension: 32,
              child: CircleIdenticon(
                bytes: ref
                    .watch(profileIdentityProvider(other))
                    .address
                    .publicKey,
              ),
            ),
            title: Text(
              ref.watch(profileIdentityProvider(other)).name ??
                  l10n.linkedAccount,
            ),
            subtitle: Text(
              connectionStatusText(
                ref.watch(connectionStatusesProvider)?[other.id],
              ),
            ),
            trailing: switch (ref
                .watch(chatsForProfileProvider(other.id))
                .value
                ?.where((chat) => chat.mute == null)
                .fold(0, (sum, chat) => sum + chat.unread)) {
              null || 0 => null,
              final unread => Badge(label: Text('$unread')),
            },
            onTap: () {
              Navigator.pop(context); // close drawer before switching
              _logger.unawaited(
                'switch accounts',
                ref
                    .read(databaseProvider.future)
                    .then(
                      (db) => db.updateAppSettings(
                        AppSettingsCompanion(currentProfile: Value(other.id)),
                      ),
                    ),
              );
            },
          ),
        if (others.isNotEmpty) const Divider(),
        ListTile(
          leading: const Icon(Icons.settings),
          title: Text(l10n.menuSettings),
          onTap: () => open(SettingsPage(profile: profile)),
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
            final db = ref.read(databaseProvider.future);
            if (!await confirm(
              context,
              title: l10n.logout,
              message: l10n.logoutMessage(me.name ?? l10n.linkedAccount),
              action: l10n.logout,
            )) {
              return;
            }
            if (context.mounted) {
              Navigator.pop(context); // close drawer before navigating away
            }
            _logger.d('Signing out profile ${profile.id}');
            await (await db).signOut(profile.id);
          },
        ),
      ],
    );
  }
}
