import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/pages/create_profile_page.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/widgets/confirm_dialog.dart';
import 'package:btox/widgets/import_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logger = Logger(['SelectProfilePage']);

final class SelectProfilePage extends ConsumerWidget {
  const SelectProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider).asData?.value ?? const [];
    final database = ref.watch(databaseProvider).asData?.value;

    if (database == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Select Profile')),
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
              await database.signIn(profile.id);
              if (context.mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
            onLongPress: () => _confirmDelete(context, database, profile),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'importProfile',
            tooltip: AppLocalizations.of(context)!.importProfile,
            onPressed: () => importProfileFile(context, ref, database),
            child: const Icon(Icons.file_open),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            tooltip: AppLocalizations.of(context)!.newProfile,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CreateProfilePage(),
              ),
            ),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Database database,
    Profile profile,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final nickname = profile.settings.nickname;
    if (!await confirm(
      context,
      title: l10n.deleteProfile,
      message: l10n.deleteProfileMessage(nickname),
      action: l10n.delete,
    )) {
      return;
    }
    _logger.i('Deleting profile ${profile.id}');
    await database.deleteProfile(profile.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.profileDeleted(nickname))));
    }
  }
}
