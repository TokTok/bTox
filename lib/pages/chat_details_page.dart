import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_details.dart';
import 'package:btox/models/chat_merge.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/widgets/chat_avatar.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:btox/widgets/copy_text.dart';
import 'package:btox/widgets/dates.dart';
import 'package:btox/widgets/load_failed.dart';
import 'package:btox/widgets/mute_chat.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How long ago a relayed name was seen to show without asking.
const _recentlySeen = Duration(days: 30);
// Where a ListTile's title starts, after its leading widget.
const _listTileTitleInset = 72.0;

/// Who a chat is with: a friend, or the people in a group or conference.
final class ChatDetailsPage extends ConsumerWidget {
  final ChatRef chat;

  const ChatDetailsPage({super.key, required this.chat});

  static Route<void> route(ChatRef chat) =>
      MaterialPageRoute(builder: (_) => ChatDetailsPage(chat: chat));

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(),
    body: switch (ref.watch(chatDetailsProvider(chat))) {
      AsyncData(value: final details) => _Details(details: details),
      AsyncError() => const LoadFailed(),
      _ => const Center(child: CircularProgressIndicator()),
    },
  );
}

final class _Details extends StatelessWidget {
  final ChatDetails details;

  const _Details({required this.details});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final summary = details.summary;
    final about = details.topic ?? details.statusMessage;
    final members = details.members;
    final relayed = details.relayed;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const SizedBox(height: 8),
        Center(
          child: ChatAvatar(
            bytes: summary.key,
            online: summary.online,
            size: 80,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            summary.name ?? l10n.defaultContactName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        if (about != null && about.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              about,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_statusText(l10n, details.status) case final status?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              status,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
        if (!summary.closed) _Mute(chat: summary),
        // Tox only sends files to friends.
        if (summary.key is PublicKey && !summary.closed)
          _PicturesAsQoi(chat: summary.ref),
        if (summary.key case final PublicKey pk) _PublicKey(pk: pk),
        if (summary.key is! PublicKey) ...[
          const Divider(),
          if (members == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.membersWhileOnline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                l10n.chatMembers(members.length + 1),
                style: theme.textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: CircleIdenticon(bytes: details.selfKey),
              title: Text(details.selfName ?? l10n.defaultContactName),
              subtitle: _subtitle([
                l10n.you,
                _roleText(l10n, details.selfRole),
              ]),
            ),
            for (final member in members) ...[
              ListTile(
                leading: CircleIdenticon(bytes: member.pk),
                title: Text(member.name ?? l10n.defaultContactName),
                subtitle: _subtitle([
                  _roleText(l10n, member.role),
                  _statusText(l10n, member.status),
                ]),
              ),
              if (relayed != null && member.pk == relayed.bot)
                _SeenNames(relayed: relayed, underBot: true),
            ],
          ],
          if (relayed != null &&
              !(members?.any((m) => m.pk == relayed.bot) ?? false))
            _SeenNames(relayed: relayed, underBot: false),
        ],
      ],
    );
  }
}

/// Who has spoken through a relay bot, not who is there now.
final class _SeenNames extends HookWidget {
  final RelayedNames relayed;
  final bool underBot;

  const _SeenNames({required this.relayed, required this.underBot});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final all = useState(false);
    final since = clock.now().subtract(_recentlySeen);
    final shown = all.value
        ? relayed.seen
        : relayed.seen.where((s) => s.last.isAfter(since)).toList();
    final padding = EdgeInsets.only(
      left: underBot ? _listTileTitleInset : 16,
      right: 16,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: padding,
          child: Text(
            l10n.seenThrough(relayed.name),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final seen in shown)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: padding,
            title: Text(seen.name),
            trailing: Text(
              recentText(context, seen.last),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (shown.length < relayed.seen.length)
          ListTile(
            dense: true,
            contentPadding: padding,
            title: Text(
              l10n.showMoreSeen(relayed.seen.length - shown.length),
              style: TextStyle(color: theme.colorScheme.primary),
            ),
            onTap: () => all.value = true,
          ),
      ],
    );
  }
}

final class _Mute extends ConsumerWidget {
  final ChatSummary chat;

  const _Mute({required this.chat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return switch (chat.mute) {
      null => ListTile(
        leading: const Icon(Icons.notifications_off_outlined),
        title: Text(l10n.muteChat),
        onTap: () => muteChat(context, ref, chat),
      ),
      final mute => ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: Text(l10n.unmuteChat),
        subtitle: Text(mutedText(context, mute)),
        onTap: () => unmuteChat(ref, chat.ref),
      ),
    };
  }
}

final class _PicturesAsQoi extends ConsumerWidget {
  final ChatRef chat;

  const _PicturesAsQoi({required this.chat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return SwitchListTile(
      secondary: const Icon(Icons.image_outlined),
      title: Text(l10n.sendPicturesAsQoi),
      subtitle: Text(l10n.sendPicturesAsQoiHint),
      value: ref.watch(pictureFormatProvider(chat)) == PictureEncoding.qoi,
      onChanged: (qoi) async {
        final db = await ref.read(databaseProvider.future);
        final scope = Scope.conversation(chat.graph);
        await (qoi
            ? db.setSetting(
                chat.profile,
                scope,
                const Kept(Setting.pictureFormat(PictureEncoding.qoi)),
              )
            : db.clearSetting(chat.profile, scope, Setting.pictureFormatKind));
      },
    );
  }
}

final class _PublicKey extends StatelessWidget {
  final PublicKey pk;

  const _PublicKey({required this.pk});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      title: Text(l10n.publicKey),
      subtitle: Text(
        pk.toJson(),
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        tooltip: l10n.copy,
        onPressed: () => copyText(
          ScaffoldMessenger.of(context),
          pk.toJson(),
          l10n.publicKeyCopied,
        ),
      ),
    );
  }
}

// Ordinary users and online friends need no label.
String? _roleText(AppLocalizations l10n, Role? role) => switch (role) {
  Role.founder => l10n.roleFounder,
  Role.moderator => l10n.roleModerator,
  Role.observer => l10n.roleObserver,
  Role.user || null => null,
};

String? _statusText(AppLocalizations l10n, UserStatus? status) =>
    switch (status) {
      UserStatus.away => l10n.statusAway,
      UserStatus.busy => l10n.statusBusy,
      UserStatus.online || null => null,
    };

Widget? _subtitle(List<String?> parts) => switch (parts.nonNulls.join(' · ')) {
  '' => null,
  final text => Text(text),
};
