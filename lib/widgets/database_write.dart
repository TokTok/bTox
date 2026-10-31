import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/providers/database.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['DatabaseWrite']);

extension DatabaseWrite on WidgetRef {
  /// Does what the user asked, and whether it did. Where it fails, [context]
  /// shows [failed], or a general message.
  Future<bool> write(
    BuildContext context,
    Future<void> Function(Database db) change, {
    String? failed,
  }) async {
    // Taken now, as the page may close meanwhile.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = failed ?? AppLocalizations.of(context)!.saveFailed;
    final database = read(databaseProvider.future);
    try {
      await change(await database);
      return true;
    } on Object catch (e, stackTrace) {
      _logger.e('Failed to save: $e', stackTrace);
      messenger?.showSnackBar(SnackBar(content: Text(message)));
      return false;
    }
  }
}
