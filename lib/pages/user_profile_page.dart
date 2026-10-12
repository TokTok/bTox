import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/widgets/nickname_field.dart';
import 'package:btox/widgets/status_message_field.dart';
import 'package:btox/widgets/tox_id_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final class UserProfilePage extends HookConsumerWidget {
  final ToxConstants constants;
  final Id<Profiles> profileId;

  const UserProfilePage({
    super.key,
    required this.constants,
    required this.profileId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider(profileId));

    return profileAsync.when(
      data: (profile) => _content(context, ref, profile),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('Error: $error'))),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, Profile profile) {
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final nickInputController = useTextEditingController(
      text: profile.settings.nickname,
    );
    final statusMessageInputController = useTextEditingController(
      text: profile.settings.statusMessage,
    );
    final applyButtonPressed = useState(false);

    void onValidate() {
      if (!formKey.currentState!.validate()) {
        return;
      }

      if (profile.settings.nickname != nickInputController.text ||
          profile.settings.statusMessage != statusMessageInputController.text) {
        applyButtonPressed.value = true;
        final database = ref.read(databaseProvider).asData?.value;
        if (database != null) {
          database.updateProfileSettings(
            profile.id,
            profile.settings.copyWith(
              nickname: nickInputController.text,
              statusMessage: statusMessageInputController.text,
            ),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.menuProfile)),
      body: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Padding(padding: EdgeInsets.all(8)),
              NicknameField(
                constants: constants,
                controller: nickInputController,
                onChanged: (value) => applyButtonPressed.value = false,
              ),
              const Padding(padding: EdgeInsets.all(8)),
              StatusMessageField(
                constants: constants,
                controller: statusMessageInputController,
                onChanged: (value) => applyButtonPressed.value = false,
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: applyButtonPressed.value
                      ? Colors.green
                      : Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => onValidate(),
                child: applyButtonPressed.value
                    ? Text(AppLocalizations.of(context)!.applied)
                    : Text(AppLocalizations.of(context)!.applyChanges),
              ),
              const Padding(padding: EdgeInsets.all(8)),
              ToxIdView(
                address: ToxAddress.of(profile.publicKey, profile.nospam),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
