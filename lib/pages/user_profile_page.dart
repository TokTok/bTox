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

final class UserProfilePage extends ConsumerWidget {
  final Id<Profiles> profileId;

  const UserProfilePage({super.key, required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider(profileId));

    return profileAsync.when(
      data: (profile) => _ProfileForm(profile),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('Error: $error'))),
    );
  }
}

final class _ProfileForm extends HookConsumerWidget {
  final Profile profile;

  const _ProfileForm(this.profile);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                controller: nickInputController,
                onChanged: (value) => applyButtonPressed.value = false,
              ),
              const Padding(padding: EdgeInsets.all(8)),
              StatusMessageField(
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
                onPressed: onValidate,
                child: Text(
                  applyButtonPressed.value
                      ? AppLocalizations.of(context)!.applied
                      : AppLocalizations.of(context)!.applyChanges,
                ),
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
