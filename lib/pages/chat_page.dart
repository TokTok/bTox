import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/content.dart';
import 'package:btox/providers/keyboard_height.dart';
import 'package:btox/widgets/chat_item.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:btox/widgets/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final class ChatPage extends HookConsumerWidget {
  final Profile profile;
  final Stream<Contact> contact;
  final Stream<List<Message>> messages;
  final void Function(Message? parent, Content content)? onSendMessage;
  final bool recentEmojis;

  const ChatPage({
    super.key,
    required this.profile,
    required this.contact,
    required this.messages,
    this.onSendMessage,
    this.recentEmojis = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replyingTo = useState<Message?>(null);

    return StreamBuilder<Contact>(
      stream: contact,
      builder: (context, snapshot) {
        final contact = snapshot.data;
        if (contact == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                if (MediaQuery.of(context).size.width > 150)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: CircleIdenticon(publicKey: contact.publicKey),
                  ),
                Expanded(
                  child: Text(contact.name ??
                      AppLocalizations.of(context)!.defaultContactName),
                ),
              ],
            ),
          ),
          body: StreamBuilder<List<Message>>(
            stream: messages,
            builder: ((context, snapshot) {
              final messages = snapshot.data ?? const [];
              return Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final reversedIndex = messages.length - index - 1;
                        final message = messages[reversedIndex];
                        return ChatItem(
                          message: message,
                          isSender: message.author == profile.publicKey,
                          onReply: () => replyingTo.value = message,
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      top: 4,
                      right: 8,
                      bottom: ref.watch(keyboardHeightProvider).when(
                          data: (height) => height == 0 ? 24 : 4,
                          error: (_, __) => 12,
                          loading: () => 12),
                    ),
                    child: MessageInput(
                      hintText: AppLocalizations.of(context)!.messageInput,
                      replyingTo: replyingTo.value?.content,
                      recentEmojis: recentEmojis,
                      onSend: (message) {
                        onSendMessage?.call(messages.lastOrNull, message);
                        replyingTo.value = null;
                      },
                      onTapCloseReply: () {
                        replyingTo.value = null;
                      },
                    ),
                  ),
                ],
              );
            }),
          ),
        );
      },
    );
  }
}
