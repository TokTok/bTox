import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/widgets/chat_item.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:btox/widgets/dates.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final class MessageInfoPage extends ConsumerWidget {
  final ChatRef chat;
  final ChatEntry entry;

  const MessageInfoPage({super.key, required this.chat, required this.entry});

  static Route<void> route(ChatRef chat, ChatEntry entry) => MaterialPageRoute(
    builder: (_) => MessageInfoPage(chat: chat, entry: entry),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final entry =
        ref
            .watch(chatEntriesProvider(chat))
            .value
            ?.where((e) => e.event == this.entry.event)
            .firstOrNull ??
        this.entry;
    final summary = ref.watch(chatProvider(chat)).value;
    final key = switch ((entry.from, entry.sender, summary?.key)) {
      (final PublicKey from, _, _) => from,
      (null, null, final PublicKey friend) => friend,
      _ => null,
    };
    final delivered = entry.delivered;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.messageInfo)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: IgnorePointer(
              child: ChatItem(chat: chat, entry: entry),
            ),
          ),
          if (entry.mine) ...[
            ListTile(
              title: Text(
                entry.delivery == ChatContentState.pending
                    ? l10n.messageSending
                    : l10n.messageSent,
              ),
              subtitle: Text(dayAndTimeText(context, entry.timestamp)),
            ),
            if (delivered != null)
              ListTile(
                title: Text(l10n.messageDelivered),
                subtitle: Text(dayAndTimeText(context, delivered)),
              ),
          ] else ...[
            ListTile(
              title: Text(l10n.messageReceived),
              subtitle: Text(dayAndTimeText(context, entry.timestamp)),
            ),
            ListTile(
              leading: key == null ? null : CircleIdenticon(bytes: key),
              title: Text(l10n.messageFrom),
              subtitle: Text(
                [
                  entry.sender ?? summary?.name ?? l10n.defaultContactName,
                  ?key?.toJson(),
                ].join('\n'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
