import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/db/database.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/widgets/nickname_field.dart';
import 'package:btox/widgets/status_message_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:sodium/sodium.dart';

const _logger = Logger(['CreateProfilePage']);

final class CreateProfilePage extends HookWidget {
  final ToxConstants constants;
  final Sodium sodium;
  final Database database;
  final Function(Id<Profiles>)? onProfileCreated;

  const CreateProfilePage({
    super.key,
    required this.constants,
    required this.sodium,
    required this.database,
    this.onProfileCreated,
  });

  @override
  Widget build(BuildContext context) {
    final nicknameController = useTextEditingController(
      text: 'Yanciman',
    );
    final statusMessageController = useTextEditingController(
      text: 'Producing works of art in Kannywood',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.newProfile),
      ),
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
          NicknameField(
            constants: constants,
            controller: nicknameController,
          ),
          const Padding(
            padding: EdgeInsets.all(8),
          ),
          StatusMessageField(
            constants: constants,
            controller: statusMessageController,
          ),
          const Padding(
            padding: EdgeInsets.all(8),
          ),
          ElevatedButton(
            onPressed: () async {
              _logger.d('Creating new profile');
              final keyPair = sodium.crypto.box.keyPair();

              final id = await database.addProfile(ProfilesCompanion.insert(
                active: const Value(true),
                settings: ProfileSettings(
                  nickname: nicknameController.text,
                  statusMessage: statusMessageController.text,
                ),
                secretKey: SecretKey.fromSodium(keyPair.secretKey),
                publicKey: PublicKey(keyPair.publicKey),
                nospam: ToxAddressNospam(0),
              ));
              _logger.d('Created new profile with ID $id');
              onProfileCreated?.call(id);
            },
            child: Text(AppLocalizations.of(context)!.create),
          ),
        ],
      ),
    );
  }
}
