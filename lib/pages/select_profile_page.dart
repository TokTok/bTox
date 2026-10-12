import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/tox_library.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/pages/create_profile_page.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/services/profile_import.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
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
            onTap: () async {
              _logger.d('Selecting profile: ${profile.id}');
              await database.activateProfile(profile.id);
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
            onPressed: () => _import(context, ref, database),
            child: const Icon(Icons.file_open),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            tooltip: AppLocalizations.of(context)!.newProfile,
            onPressed: () async {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateProfilePage(),
                ),
              );
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    Database database,
    Profile profile,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final nickname = profile.settings.nickname;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteProfile),
        content: Text(l10n.deleteProfileMessage(nickname)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              _logger.i('Deleting profile ${profile.id}');
              await database.deleteProfile(profile.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.profileDeleted(nickname))),
                );
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _import(
    BuildContext context,
    WidgetRef ref,
    Database database,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    // Importing opens the new profile, which replaces this page.
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final bytes = picked?.files.singleOrNull?.bytes;
    if (bytes == null || !context.mounted) {
      return;
    }
    final lib = await ref.read(toxFfiProvider.future);
    var save = bytes;
    if (isToxSaveEncrypted(lib, bytes)) {
      if (!context.mounted) {
        return;
      }
      final decrypted = await _askPassphrase(
        context,
        (passphrase) => decryptToxSave(lib, bytes, passphrase),
      );
      if (decrypted == null) {
        return;
      }
      save = decrypted;
    }

    String message;
    try {
      final profile = readToxSave(lib, save);
      await importProfile(database, profile);
      message = l10n.profileImported(profile.name);
    } on ProfileExistsException {
      message = l10n.profileAlreadyImported;
    } on ApiException catch (e) {
      _logger.w('Not a Tox profile: $e');
      message = l10n.notAToxProfile;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Uint8List?> _askPassphrase(
    BuildContext context,
    Uint8List Function(String passphrase) decrypt,
  ) => showDialog<Uint8List>(
    context: context,
    builder: (_) => _PassphraseDialog(decrypt: decrypt),
  );
}

final class _PassphraseDialog extends HookWidget {
  final Uint8List Function(String passphrase) decrypt;

  const _PassphraseDialog({required this.decrypt});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = useTextEditingController();
    final error = useState<String?>(null);

    void submit() {
      try {
        Navigator.pop(context, decrypt(controller.text));
      } on ApiException {
        error.value = l10n.wrongPassword;
      }
    }

    return AlertDialog(
      title: Text(l10n.importProfile),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.password,
          errorText: error.value,
        ),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: submit, child: Text(l10n.import)),
      ],
    );
  }
}
