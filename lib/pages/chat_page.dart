import 'package:btox/background_service.dart';
import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/messaging.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/contacts.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/keyboard_height.dart';
import 'package:btox/providers/messages.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/widgets/chat_item.dart';
import 'package:btox/widgets/contact_avatar.dart';
import 'package:btox/widgets/message_input.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final class ChatPage extends HookConsumerWidget {
  final Id<Contacts> contactId;
  final bool recentEmojis;

  const ChatPage({
    super.key,
    required this.contactId,
    this.recentEmojis = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replyingTo = useState<Message?>(null);
    useEffect(() {
      reportOpenChat(contactId);
      return () => reportOpenChat(null);
    }, [contactId]);
    useOnAppLifecycleStateChange(
      (_, state) =>
          reportOpenChat(state == AppLifecycleState.resumed ? contactId : null),
    );
    final contactAsync = ref.watch(contactProvider(contactId));
    final messagesAsync = ref.watch(messagesForContactProvider(contactId));
    final profile = ref.watch(activeProfileProvider);

    return contactAsync.when(
      data: (contact) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                if (MediaQuery.of(context).size.width > 150)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: ContactAvatar(contact: contact),
                  ),
                Expanded(
                  child: Text(
                    contact.name ??
                        AppLocalizations.of(context)!.defaultContactName,
                  ),
                ),
              ],
            ),
          ),
          body: messagesAsync.when(
            data: (messages) {
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
                          isSender: message.author == profile?.publicKey,
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
                      bottom: ref
                          .watch(keyboardHeightProvider)
                          .when(
                            data: (height) => height == 0 ? 24 : 4,
                            error: (_, _) => 12,
                            loading: () => 12,
                          ),
                    ),
                    child: MessageInput(
                      hintText: AppLocalizations.of(context)!.messageInput,
                      replyingTo: replyingTo.value?.content,
                      recentEmojis: recentEmojis,
                      onSend: (content) {
                        final database = ref
                            .read(databaseProvider)
                            .asData
                            ?.value;
                        if (database != null && profile != null) {
                          database.addMessage(
                            newMessage(
                              contactId: contactId,
                              parent: messages.lastOrNull,
                              merged: null,
                              author: profile.publicKey,
                              timestamp: clock.now().toUtc(),
                              content: content,
                            ).copyWith(delivered: const Value(false)),
                          );
                        }
                        replyingTo.value = null;
                      },
                      onTapCloseReply: () {
                        replyingTo.value = null;
                      },
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('Error: $error'))),
    );
  }
}
