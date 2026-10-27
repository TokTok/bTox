import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/ffi/tox_library.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/services/backup.dart';
import 'package:btox/services/profile_import.dart';
import 'package:btox/widgets/account_picker.dart';
import 'package:btox/widgets/passphrase_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['ImportProfile']);

/// Imports a Tox save or restores a bTox backup.
Future<void> importProfileFile(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final database = ref.read(databaseProvider.future);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
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
    final decrypted = await showPassphraseDialog(
      context,
      title: l10n.importData,
      action: l10n.import,
      run: (passphrase) => decryptToxSave(lib, bytes, passphrase),
    );
    if (decrypted == null) {
      return;
    }
    save = decrypted;
  }

  String message;
  try {
    if (readBackup(save) case final backup?) {
      if (!context.mounted) {
        return;
      }
      final accounts = await showAccountPicker(
        context,
        title: l10n.importData,
        action: l10n.import,
        accounts: backupAccounts(backup.tables),
      );
      if (accounts == null) {
        return;
      }
      message = l10n.accountsRestored(
        await restoreBackup(await database, backup, accounts),
      );
    } else {
      final profile = readToxSave(lib, save);
      await importProfile(await database, profile);
      message = l10n.profileImported(profile.name);
      // It's signed in and shown.
      navigator.popUntil((route) => route.isFirst);
    }
  } on ProfileExistsException {
    message = l10n.profileAlreadyImported;
  } on ApiException catch (e) {
    _logger.w('Not a Tox profile: $e');
    message = l10n.notAToxProfile;
  } on Object catch (e) {
    // A damaged backup can fail anywhere while it's restored.
    _logger.e('Failed to import a file: $e');
    message = l10n.importFailed;
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
