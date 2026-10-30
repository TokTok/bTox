import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/widgets/chat_avatar.dart';
import 'package:btox/widgets/database_write.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['MergeChatPage']);

/// Merges [chat] with another group chat, a bot relaying messages between
/// them, picking the bot in each.
final class MergeChatPage extends HookConsumerWidget {
  final ChatSummary chat;

  const MergeChatPage({super.key, required this.chat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final other = useState<ChatSummary?>(null);
    final picked = useState(<GraphId, PublicKey>{});
    final others = [
      for (final c
          in ref.watch(chatsForProfileProvider(chat.ref.profile)).value ??
              const <ChatSummary>[])
        if (c.ref != chat.ref &&
            c.key is! PublicKey &&
            (ref.watch(chatMergeProvider(c.ref))?.sides.length ?? 1) < 2)
          c,
    ];
    final sides = [chat, ?other.value];
    final senders = {
      for (final side in sides)
        side.ref.graph: ref.watch(chatSendersProvider(side.ref)),
    };
    PublicKey? botIn(ChatSummary side) =>
        picked.value[side.ref.graph] ??
        senders[side.ref.graph]!.where((s) => s.relayed > 0).firstOrNull?.key;
    final bots = [for (final side in sides) botIn(side)];

    Future<void> merge(ChatSummary target) async {
      // Messages written in the merged chat go to the group.
      final (
        into,
        merged,
      ) = chat.key is ConferenceId && target.key is GroupChatId
          ? (target, chat)
          : (chat, target);
      _logger.i('Merging ${merged.ref.graph} into ${into.ref.graph}');
      final saved = await ref.write(
        context,
        (db) => db.addIntent(
          chat.ref.profile,
          MergeChat(
            chat: merged.chatId!,
            bot: botIn(merged)!,
            into: into.chatId!,
            intoBot: botIn(into)!,
            merged: true,
          ),
        ),
      );
      if (saved && context.mounted) {
        Navigator.pop(context);
      }
    }

    String nameOf(ChatSummary c) => c.name ?? l10n.defaultContactName;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mergeChatTitle)),
      body: ListView(
        children: [
          _Heading(l10n.mergeWith),
          if (others.isEmpty)
            ListTile(title: Text(l10n.noChatsToMerge))
          else
            RadioGroup<GraphId>(
              groupValue: other.value?.ref.graph,
              onChanged: (graph) => other.value = others
                  .where((c) => c.ref.graph == graph)
                  .firstOrNull,
              child: Column(
                children: [
                  for (final c in others)
                    RadioListTile(
                      value: c.ref.graph,
                      secondary: ChatAvatar(bytes: c.key),
                      title: Text(nameOf(c)),
                    ),
                ],
              ),
            ),
          if (other.value != null)
            for (final side in sides) ...[
              _Heading(l10n.relayBotIn(nameOf(side))),
              _BotPicker(
                senders: senders[side.ref.graph]!,
                bot: botIn(side),
                onChanged: (bot) =>
                    picked.value = {...picked.value, side.ref.graph: ?bot},
              ),
            ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: switch (other.value) {
              final target? when !bots.contains(null) => () => merge(target),
              _ => null,
            },
            child: Text(l10n.merge),
          ),
        ),
      ),
    );
  }
}

/// Shows the names a bot relays into [chat] from another chat, picking the
/// bot.
final class RelayBotPage extends HookConsumerWidget {
  final ChatSummary chat;

  const RelayBotPage({super.key, required this.chat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final picked = useState<PublicKey?>(null);
    final senders = ref.watch(chatSendersProvider(chat.ref));
    final bot =
        picked.value ?? senders.where((s) => s.relayed > 0).firstOrNull?.key;

    Future<void> use(PublicKey bot) async {
      _logger.i('Showing names from $bot in ${chat.ref.graph}');
      final saved = await ref.write(
        context,
        (db) => db.addIntent(
          chat.ref.profile,
          RelayBot(chat: chat.chatId!, bot: bot, relays: true),
        ),
      );
      if (saved && context.mounted) {
        Navigator.pop(context);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.relayBotNames)),
      body: ListView(
        children: [
          _Heading(l10n.relayBotIn(chat.name ?? l10n.defaultContactName)),
          _BotPicker(
            senders: senders,
            bot: bot,
            onChanged: (bot) => picked.value = bot,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: switch (bot) {
              final bot? => () => use(bot),
              null => null,
            },
            child: Text(l10n.showNames),
          ),
        ),
      ),
    );
  }
}

final class _BotPicker extends StatelessWidget {
  final List<ChatSender> senders;
  final PublicKey? bot;
  final void Function(PublicKey? bot) onChanged;

  const _BotPicker({
    required this.senders,
    required this.bot,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RadioGroup<PublicKey>(
      groupValue: bot,
      onChanged: onChanged,
      child: Column(
        children: [
          for (final sender in senders)
            RadioListTile(
              value: sender.key,
              secondary: ChatAvatar(bytes: sender.key),
              title: Text(sender.name),
              subtitle: Text(
                l10n.relayedMessages(sender.relayed, sender.messages),
              ),
            ),
        ],
      ),
    );
  }
}

final class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
