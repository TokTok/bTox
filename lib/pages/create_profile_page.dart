import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/widgets/nickname_field.dart';
import 'package:btox/widgets/status_message_field.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/sodium.dart';
import 'package:btox/providers/tox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['CreateProfilePage']);

final class CreateProfilePage extends HookConsumerWidget {
  const CreateProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final constants = ref.watch(toxConstantsProvider).asData?.value;
    final sodium = ref.watch(sodiumProvider).asData?.value;
    final database = ref.watch(databaseProvider).asData?.value;

    if (constants == null || sodium == null || database == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final nicknameController = useTextEditingController(text: 'Yanciman');
    final statusMessageController = useTextEditingController(
      text: 'Producing works of art in Kannywood',
    );
    final creating = useState(false);

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.newProfile)),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Image.asset(
              'assets/images/btox-icon.png',
              width: 200,
              height: 200,
            ),
          ),
          NicknameField(constants: constants, controller: nicknameController),
          const Padding(padding: EdgeInsets.all(8)),
          StatusMessageField(
            constants: constants,
            controller: statusMessageController,
          ),
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
                    final keyPair = sodium.crypto.box.keyPair();

                    final Id<Profiles> id;
                    try {
                      id = await database.transaction(() async {
                        final id = await database.addProfile(
                          ProfilesCompanion.insert(
                            settings: ProfileSettings(
                              nickname: nicknameController.text,
                              statusMessage: statusMessageController.text,
                            ),
                            secretKey: SecretKey.fromSodium(keyPair.secretKey),
                            publicKey: PublicKey(keyPair.publicKey),
                            nospam: ToxAddressNospam(0),
                          ),
                        );
                        await database.activateProfile(id);
                        return id;
                      });
                    } catch (e) {
                      _logger.e('Failed to create profile: $e');
                      creating.value = false;
                      return;
                    }
                    _logger.d('Created new profile with ID $id');
                    // On first start, this page is the home page instead.
                    if (context.mounted && Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
            child: Text(AppLocalizations.of(context)!.create),
          ),
        ],
      ),
    );
  }
}
