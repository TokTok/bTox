import 'package:btox/background_service.dart';
import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:flutter/material.dart';

const _logger = Logger(['SettingsPage']);

final class SettingsPage extends StatelessWidget {
  final Database database;
  final Profile profile;

  const SettingsPage({
    super.key,
    required this.database,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.menuSettings)),
      body: ListView(
        children: [
          ListTile(
            title: Text(AppLocalizations.of(context)!.deleteProfile),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(AppLocalizations.of(context)!.deleteProfile),
                  content: Text(
                    AppLocalizations.of(context)!
                        .deleteProfileMessage(profile.settings.nickname),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLocalizations.of(context)!.cancel),
                    ),
                    TextButton(
                      onPressed: () async {
                        _logger.i('Deleting profile ${profile.id}');
                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppLocalizations.of(context)!
                                  .profileDeleted(profile.settings.nickname),
                            ),
                          ),
                        );

                        Navigator.pop(context);

                        await database.deleteProfile(profile.id);
                        _logger.i('Profile ${profile.id} deleted');
                      },
                      child: Text(AppLocalizations.of(context)!.delete),
                    ),
                  ],
                ),
              );
            },
          ),
          ListTile(
            title: Text('Start background service'),
            onTap: () {
              startBackgroundService();
            },
          ),
          ListTile(
            title: Text('Stop background service'),
            onTap: () {
              stopBackgroundService();
            },
          ),
        ],
      ),
    );
  }
}
