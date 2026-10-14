import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/widgets/import_profile.dart';
import 'package:btox/widgets/nickname_field.dart';
import 'package:btox/widgets/status_message_field.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['CreateProfilePage']);

final class CreateProfilePage extends HookConsumerWidget {
  const CreateProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(databaseProvider).asData?.value;
    final nicknameController = useTextEditingController(text: 'Yanciman');
    final statusMessageController = useTextEditingController(
      text: 'Producing works of art in Kannywood',
    );
    final creating = useState(false);

    if (database == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.newProfile),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.importProfile,
            onPressed: () => importProfileFile(context, ref, database),
            icon: const Icon(Icons.file_open),
          ),
        ],
      ),
      body: Column(
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
          ElevatedButton(
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
                    final Id<Profiles> id;
                    try {
                      final (secretKey, publicKey) = await ref.read(
                        newKeyPairProvider.future,
                      );
                      id = await database.transaction(() async {
                        final id = await database.addProfile(
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
                        await database.signIn(id);
                        return id;
                      });
                    } catch (e) {
                      _logger.e('Failed to create profile: $e');
                      creating.value = false;
                      return;
                    }
                    _logger.d('Created new profile with ID $id');
                    // On first start, this page is the home page instead.
                    if (context.mounted) {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    }
                  },
            child: Text(AppLocalizations.of(context)!.create),
          ),
        ],
      ),
    );
  }
}
