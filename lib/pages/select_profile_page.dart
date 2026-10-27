import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/pages/create_profile_page.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/widgets/delete_profile.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['SelectProfilePage']);

final class SelectProfilePage extends ConsumerWidget {
  const SelectProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider).asData?.value ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.accounts)),
      body: ListView.builder(
        itemCount: profiles.length,
        itemBuilder: (context, index) {
          final profile = profiles[index];
          return ListTile(
            title: Text(profile.settings.nickname),
            subtitle: Text(profile.settings.statusMessage),
            trailing: profile.signedIn
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
            onTap: () async {
              _logger.d('Signing in profile: ${profile.id}');
              final db = await ref.read(databaseProvider.future);
              await db.signIn(profile.id);
              if (context.mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
            onLongPress: () => deleteProfileIfConfirmed(
              context,
              ref,
              profile,
              profile.settings.nickname,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: AppLocalizations.of(context)!.newProfile,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CreateProfilePage()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}
