import 'dart:typed_data';

import 'package:btox/attachments/avatar_picture.dart';
import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/widgets/avatar.dart';
import 'package:btox/widgets/database_write.dart';
import 'package:btox/widgets/load_failed.dart';
import 'package:btox/widgets/nickname_field.dart';
import 'package:btox/widgets/status_message_field.dart';
import 'package:btox/widgets/tox_id_view.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:file_picker/file_picker.dart';
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
      data: (profile) => profile.home == null
          ? _ProfileForm(profile)
          : _LinkedProfile(profile),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Scaffold(body: LoadFailed()),
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
        final nickname = nickInputController.text;
        final statusMessage = statusMessageInputController.text;
        ref.write(
          context,
          (db) => db.updateProfileSettings(
            profile.id,
            (s) => s.copyWith(nickname: nickname, statusMessage: statusMessage),
          ),
        );
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
              _AvatarPicker(profile),
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
              if (applyButtonPressed.value)
                FilledButton.tonal(
                  onPressed: onValidate,
                  child: Text(AppLocalizations.of(context)!.applied),
                )
              else
                FilledButton(
                  onPressed: onValidate,
                  child: Text(AppLocalizations.of(context)!.applyChanges),
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

final class _AvatarPicker extends ConsumerWidget {
  final Profile profile;

  const _AvatarPicker(this.profile);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    Future<void> choose() async {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final bytes = picked?.files.singleOrNull?.bytes;
      if (bytes == null) {
        return;
      }
      final avatar = await avatarPicture(bytes);
      if (!context.mounted) {
        return;
      }
      if (avatar == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.avatarUnusable)));
        return;
      }
      final blob = BlobId(Uint8List.fromList(sha256.convert(avatar).bytes));
      await ref.write(context, (db) async {
        await db.setAvatar(profile.id, blob, avatar);
        await db.updateProfileSettings(
          profile.id,
          (s) => s.copyWith(avatar: blob),
        );
      });
    }

    return Column(
      children: [
        Avatar(
          profile: profile.id,
          blob: profile.settings.avatar,
          bytes: profile.publicKey,
          radius: 48,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.photo_outlined),
              label: Text(l10n.avatarChoose),
              onPressed: choose,
            ),
            if (profile.settings.avatar != null)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.avatarRemove),
                onPressed: () => ref.write(
                  context,
                  (db) => db.updateProfileSettings(
                    profile.id,
                    (s) => s.copyWith(avatar: null),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Edited on the device that runs the account, for now.
final class _LinkedProfile extends ConsumerWidget {
  final Profile profile;

  const _LinkedProfile(this.profile);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final identity = ref.watch(profileIdentityProvider(profile));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.menuProfile)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: Text(identity.name ?? l10n.linkedAccount),
            subtitle: Text(identity.statusMessage),
          ),
          ToxIdView(address: identity.address),
        ],
      ),
    );
  }
}
