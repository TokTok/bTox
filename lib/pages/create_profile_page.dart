import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/link_account_page.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/widgets/database_write.dart';
import 'package:btox/widgets/import_profile.dart';
import 'package:btox/widgets/nickname_field.dart';
import 'package:btox/widgets/status_message_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['CreateProfilePage']);

final class CreateProfilePage extends HookConsumerWidget {
  const CreateProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nicknameController = useTextEditingController(text: 'Yanciman');
    final statusMessageController = useTextEditingController(
      text: 'Producing works of art in Kannywood',
    );
    final creating = useState(false);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.newProfile),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.linkAccount,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LinkAccountPage()),
            ),
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context)!.importData,
            onPressed: () => importProfileFile(context, ref),
            icon: const Icon(Icons.file_open),
          ),
        ],
      ),
      // The keyboard, a small screen or large text may not leave it room.
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Image.asset(
                'assets/images/btox-icon.png',
                width: 200,
                height: 200,
              ),
            ),
            NicknameField(controller: nicknameController),
            const Padding(padding: EdgeInsets.all(8)),
            StatusMessageField(controller: statusMessageController),
            const Padding(padding: EdgeInsets.all(8)),
            FilledButton(
              key: const Key('createProfileButton'),
              onPressed: creating.value
                  ? null
                  : () async {
                      // A second tap can come before the button is disabled.
                      if (creating.value) {
                        return;
                      }
                      creating.value = true;
                      _logger.d('Creating new profile');
                      final created = await ref.write(context, (db) async {
                        final (secretKey, publicKey) = await ref.read(
                          newKeyPairProvider.future,
                        );
                        await db.transaction(() async {
                          final id = await db.addProfile(
                            ProfilesCompanion.insert(
                              settings: ProfileSettings(
                                nickname: nicknameController.text,
                                statusMessage: statusMessageController.text,
                              ),
                              secretKey: secretKey,
                              publicKey: publicKey,
                              nospam: ToxAddressNospam(0),
                            ),
                          );
                          await db.signIn(id);
                          _logger.d('Created new profile with ID $id');
                        });
                      });
                      if (!created) {
                        creating.value = false;
                        return;
                      }
                      // On first start, this page is the home page instead.
                      if (context.mounted) {
                        Navigator.popUntil(context, (route) => route.isFirst);
                      }
                    },
              child: Text(AppLocalizations.of(context)!.create),
            ),
          ],
        ),
      ),
    );
  }
}
