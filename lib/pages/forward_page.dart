import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart' show Profiles;
import 'package:btox/providers/chats.dart';
import 'package:btox/widgets/chat_avatar.dart';
import 'package:btox/widgets/load_failed.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final class ForwardPage extends ConsumerWidget {
  final Id<Profiles> profile;
  // Lists only friends, as Tox sends files only to friends.
  final bool files;

  const ForwardPage({super.key, required this.profile, required this.files});

  static Route<ChatRef> route(Id<Profiles> profile, {required bool files}) =>
      MaterialPageRoute(
        builder: (_) => ForwardPage(profile: profile, files: files),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.forwardTo)),
      body: switch (ref.watch(chatsForProfileProvider(profile))) {
        AsyncData(value: final chats) => ListView(
          children: [
            for (final chat in chats)
              if (!chat.closed && (!files || chat.key is PublicKey))
                ListTile(
                  leading: ChatAvatar(bytes: chat.key, online: chat.online),
                  title: Text(chat.name ?? l10n.defaultContactName),
                  onTap: () => Navigator.pop(context, chat.ref),
                ),
          ],
        ),
        AsyncError() => const LoadFailed(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
