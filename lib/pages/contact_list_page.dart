import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/pages/add_contact_page.dart';
import 'package:btox/pages/call_page.dart';
import 'package:btox/pages/chat_page.dart';
import 'package:btox/pages/merge_chat_page.dart';
import 'package:btox/providers/calls.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/widgets/call_entry.dart';
import 'package:btox/widgets/chat_avatar.dart';
import 'package:btox/widgets/chat_invite_list_item.dart';
import 'package:btox/widgets/chat_list_item.dart';
import 'package:btox/widgets/confirm_dialog.dart';
import 'package:btox/widgets/connection_status_icon.dart';
import 'package:btox/widgets/database_write.dart';
import 'package:btox/widgets/dates.dart';
import 'package:btox/widgets/friend_request_list_item.dart';
import 'package:btox/widgets/load_failed.dart';
import 'package:btox/widgets/main_menu.dart';
import 'package:btox/widgets/mute_chat.dart';
import 'package:btox/widgets/passphrase_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['ContactListPage']);

enum _Tab { chats, calls }

final class ContactListPage extends HookConsumerWidget {
  const ContactListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final tab = useState(_Tab.chats);
    final profile = ref.watch(currentProfileProvider);

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // A linked account's friend requests go to its home device.
    final local = profile.home == null;
    final requests = local
        ? ref.watch(friendRequestsProvider(profile.id)).entries.toList()
        : const <MapEntry<PublicKey, String>>[];
    final invites = ref.watch(chatInvitesProvider(profile.id));
    final friends = ref.watch(accountProvider(profile.id)).value?.friends;
    Future<void> answer(
      EventId id,
      AccountInvite invite, {
      required bool join,
    }) async {
      String? password;
      // Tox checks a group's password only after it takes the invite, which
      // it takes only once.
      if (join && invite.kind == ChatKind.group) {
        final entered = await showPassphraseDialog(
          context,
          title: invite.name,
          action: l10n.joinInvite,
          run: (password) => password,
          optional: true,
          helper: l10n.groupPasswordHelper,
        );
        if (entered == null) {
          return;
        }
        password = entered.isEmpty ? null : entered;
      }
      if (context.mounted) {
        await ref.write(
          context,
          (db) => db.addIntent(
            profile.id,
            AnswerInvite(invite: id, join: join, password: password),
          ),
        );
      }
    }

    Future<void> want(
      PublicKey pk, {
      required bool wanted,
      bool deleteChat = false,
    }) async {
      await ref.write(
        context,
        (db) => db.addIntent(
          profile.id,
          wanted ? WantFriend(pk: pk) : UnwantFriend(pk: pk),
          deleteChat: deleteChat,
        ),
      );
    }

    final chats = ref.watch(chatsForProfileProvider(profile.id));
    final unread =
        requests.length +
        invites.where((i) => i.$2.status == InviteStatus.pending).length +
        (chats.value ?? const <ChatSummary>[])
            .where((c) => c.mute == null)
            .fold(0, (n, c) => n + c.unread);

    return Scaffold(
      drawer: MainMenu(profile: profile),
      appBar: AppBar(
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                height: 24,
                width: 24,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: const ConnectionStatusIcon(),
                ),
              ),
            ),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.titleWithAccount(
                  ref.watch(profileIdentityProvider(profile)).name ??
                      AppLocalizations.of(context)!.linkedAccount,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: switch (tab.value) {
        _Tab.calls => _Calls(profile: profile.id),
        _Tab.chats => chats.when(
          data: (chats) {
            if (requests.isEmpty && invites.isEmpty && chats.isEmpty) {
              return _Empty(
                icon: Icons.chat_bubble_outline,
                title: AppLocalizations.of(context)!.noChats,
                hint: local ? AppLocalizations.of(context)!.noChatsHint : null,
              );
            }
            final above = requests.length + invites.length;
            return ListView.builder(
              itemCount: above + chats.length,
              itemBuilder: (context, index) {
                if (index < requests.length) {
                  final MapEntry(key: pk, value: message) = requests[index];
                  return FriendRequestListItem(
                    publicKey: pk,
                    message: message,
                    onAccept: () => want(pk, wanted: true),
                    onReject: () => want(pk, wanted: false),
                  );
                }
                if (index < above) {
                  final (event, invite) = invites[index - requests.length];
                  return ChatInviteListItem(
                    invite: invite,
                    text: inviteText(l10n, invite, friends?[invite.from]?.name),
                    onAnswer: ({required join}) =>
                        answer(event, invite, join: join),
                  );
                }
                return ChatListItem(
                  chat: chats[index - above],
                  onTap: (chat) {
                    _logger.d('Opening chat ${chat.ref}');
                    Navigator.push(context, ChatPage.route(chat.ref));
                  },
                  onLongPress: (chat) => _chatActions(
                    context,
                    ref,
                    chat,
                    delete: switch (chat.key) {
                      final PublicKey pk when local => (deleteChat) => want(
                        pk,
                        wanted: false,
                        deleteChat: deleteChat,
                      ),
                      _ => null,
                    },
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const LoadFailed(),
        ),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.value.index,
        onDestinationSelected: (index) => tab.value = _Tab.values[index],
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.chat_bubble),
            ),
            label: l10n.chats,
          ),
          NavigationDestination(
            icon: const Icon(Icons.call_outlined),
            selectedIcon: const Icon(Icons.call),
            label: l10n.calls,
          ),
        ],
      ),
      floatingActionButton: !local || tab.value != _Tab.chats
          ? null
          : FloatingActionButton(
              key: const Key('addContactButton'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddContactPage(
                    own: {profile.publicKey},
                    onAddContact: (address, message) async {
                      final db = await ref.read(databaseProvider.future);
                      await db.addIntent(
                        profile.id,
                        WantFriend(
                          pk: address.publicKey,
                          requestMessage: message,
                          nospam: address.nospam,
                        ),
                      );
                      _logger.d('Added contact: ${address.publicKey}');
                    },
                    selfName: profile.settings.nickname,
                  ),
                ),
              ),
              tooltip: AppLocalizations.of(context)!.addContact,
              child: const Icon(Icons.add),
            ),
    );
  }

  Future<void> _chatActions(
    BuildContext context,
    WidgetRef ref,
    ChatSummary chat, {
    Future<void> Function(bool deleteChat)? delete,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final account = ref.read(accountProvider(chat.ref.profile)).value;
    final merged =
        (ref.read(chatMergeProvider(chat.ref))?.sides.length ?? 0) > 1;
    final relayBot = account?.relayBots.entries
        .where((r) => r.key.graph == chat.ref.graph)
        .firstOrNull
        ?.value;
    final picked = await showModalBottomSheet<_ChatAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                chat.mute == null
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_outlined,
              ),
              title: Text(chat.mute == null ? l10n.muteChat : l10n.unmuteChat),
              onTap: () => Navigator.pop(
                context,
                chat.mute == null ? _ChatAction.mute : _ChatAction.unmute,
              ),
            ),
            if (delete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.deleteContact),
                onTap: () => Navigator.pop(context, _ChatAction.delete),
              ),
            if (chat.key is! PublicKey)
              ListTile(
                leading: Icon(merged ? Icons.call_split : Icons.merge),
                title: Text(merged ? l10n.unmergeChat : l10n.mergeChat),
                onTap: () => Navigator.pop(
                  context,
                  merged ? _ChatAction.unmerge : _ChatAction.merge,
                ),
              ),
            if (chat.key is! PublicKey && !merged)
              ListTile(
                leading: Icon(
                  relayBot == null
                      ? Icons.smart_toy_outlined
                      : Icons.person_off_outlined,
                ),
                title: Text(
                  relayBot == null
                      ? l10n.relayBotNames
                      : l10n.stopRelayBotNames,
                ),
                onTap: () => Navigator.pop(
                  context,
                  relayBot == null
                      ? _ChatAction.relayBot
                      : _ChatAction.noRelayBot,
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) {
      return;
    }
    switch (picked) {
      case _ChatAction.mute:
        await muteChat(context, ref, chat);
        return;
      case _ChatAction.unmute:
        await unmuteChat(context, ref, chat.ref);
        return;
      case _ChatAction.delete:
        await _confirmDelete(context, delete!, chat.name);
        return;
      case _ChatAction.merge:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => MergeChatPage(chat: chat)),
        );
        return;
      case _ChatAction.relayBot:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => RelayBotPage(chat: chat)),
        );
        return;
      case _ChatAction.noRelayBot:
        _logger.i('No more names from the relay bot in ${chat.ref.graph}');
        await ref.write(
          context,
          (db) => db.addIntent(
            chat.ref.profile,
            RelayBot(chat: chat.chatId!, bot: relayBot!, relays: false),
          ),
        );
        return;
      case _ChatAction.unmerge:
        await ref.write(
          context,
          (db) => db.showApart(
            chat.ref.profile,
            chat.ref.graph,
            account?.merges ?? const {},
          ),
        );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Future<void> Function(bool deleteChat) delete,
    String? contactName,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final name = contactName ?? l10n.defaultContactName;
    final deleteChat = await confirmWithOption(
      context,
      title: l10n.deleteContact,
      message: l10n.deleteContactMessage(name),
      action: l10n.delete,
      option: l10n.deleteChatToo,
    );
    if (deleteChat == null) {
      return;
    }
    _logger.i('Deleting contact $name');
    await delete(deleteChat);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.contactDeleted(name))));
    }
  }
}

enum _ChatAction { mute, unmute, delete, merge, unmerge, relayBot, noRelayBot }

/// What a tab shows with nothing in it.
final class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;

  const _Empty({required this.icon, required this.title, this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            if (hint case final hint?) ...[
              const SizedBox(height: 4),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _Calls extends ConsumerWidget {
  final Id<Profiles> profile;

  const _Calls({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final calls = ref.watch(callHistoryProvider(profile));
    final canCall = ref.watch(canCallProvider(profile));
    final Widget list;
    if (calls.isEmpty) {
      list = _Empty(
        icon: Icons.call,
        title: l10n.noCalls,
        hint: canCall ? null : l10n.callsNotAvailable,
      );
    } else {
      list = ListView.builder(
        itemCount: calls.length,
        itemBuilder: (context, index) {
          final (:chat, :entry) = calls[index];
          final call = entry.content as CallContent;
          final color = call.missed ? theme.colorScheme.error : null;
          return ListTile(
            leading: ChatAvatar(bytes: chat.key),
            title: Text(
              chat.name ?? l10n.defaultContactName,
              style: TextStyle(color: color),
            ),
            subtitle: Row(
              children: [
                Icon(callIcon(call), size: 16, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(switch (call.duration) {
                    final duration? => l10n.callWithDuration(
                      recentText(context, entry.timestamp),
                      durationText(duration),
                    ),
                    null => recentText(context, entry.timestamp),
                  }),
                ),
              ],
            ),
            trailing: switch (chat.key) {
              final PublicKey friend when canCall => IconButton(
                icon: const Icon(Icons.call),
                tooltip: l10n.voiceCall,
                onPressed: chat.online == true
                    ? () => startCall(context, chat.ref, friend)
                    : null,
              ),
              _ => null,
            },
            onTap: () => Navigator.push(context, ChatPage.route(chat.ref)),
          );
        },
      );
    }
    return Column(
      children: [
        if (canCall) const RingOverLockScreenBanner(),
        Expanded(child: list),
      ],
    );
  }
}
