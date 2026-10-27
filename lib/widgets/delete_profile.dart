import 'package:btox/attachments/attachments.dart';
import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/drafts.dart';
import 'package:btox/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['DeleteProfile']);

/// Asks whether to delete [profile], shown as [name], and deletes it if so.
/// [confirmed] runs before it's deleted, e.g. to leave a page showing it.
Future<void> deleteProfileIfConfirmed(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
  String name, {
  void Function()? confirmed,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final database = ref.read(databaseProvider.future);
  if (!await confirm(
    context,
    title: l10n.deleteProfile,
    message: l10n.deleteProfileMessage(name),
    action: l10n.delete,
  )) {
    return;
  }
  confirmed?.call();
  _logger.i('Deleting profile ${profile.id}');
  var result = l10n.profileDeleted(name);
  try {
    for (final file in await (await database).deleteProfile(profile.id)) {
      _logger.unawaited('delete $file', deleteAttachment(file));
    }
  } on Exception catch (e) {
    _logger.e('Failed to delete profile ${profile.id}: $e');
    result = l10n.profileDeleteFailed(name);
  }
  // So no draft of its is saved again. Those of others come back saved.
  container.invalidate(chatDraftProvider);
  messenger.showSnackBar(SnackBar(content: Text(result)));
}
