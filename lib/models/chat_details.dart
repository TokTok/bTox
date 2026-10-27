import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_details.freezed.dart';

@freezed
abstract class ChatMember with _$ChatMember {
  const factory ChatMember({
    required PublicKey pk,
    String? name,
    Role? role,
    UserStatus? status,
  }) = _ChatMember;
}

/// What a chat's details page shows, beyond its summary.
@freezed
abstract class ChatDetails with _$ChatDetails {
  const factory ChatDetails({
    required ChatSummary summary,
    // A friend's.
    String? statusMessage,
    UserStatus? status,
    // A group's or conference's.
    String? topic,
    // What the others in it see us as.
    required PublicKey selfKey,
    String? selfName,
    Role? selfRole,
    // Who else is in it, while Tox says. Null for friend chats, and where the
    // account's Tox isn't running.
    List<ChatMember>? members,
  }) = _ChatDetails;

  /// From what the [account] keeps and what its Tox says now, in [live], if
  /// it's running.
  factory ChatDetails.of(
    ChatSummary summary,
    PublicKey selfKey,
    AccountState account,
    Facts? live,
  ) {
    T? fact<T>(Facts? facts, Subject subject, T? Function(FactValue) pick) =>
        facts?.find(subject, pick);
    String? topicOf(FactValue v) => v is TopicValue ? v.topic : null;
    Role? roleOf(FactValue v) => v is RoleValue ? v.role : null;
    UserStatus? statusOf(FactValue v) => v is StatusValue ? v.status : null;

    final ChatId chat;
    switch (summary.key) {
      case final PublicKey pk:
        final friend = Subject.friend(pk);
        return ChatDetails(
          summary: summary,
          selfKey: selfKey,
          statusMessage: fact(
            account.facts,
            friend,
            (v) => v is StatusMessageValue ? v.message : null,
          ),
          status: fact(live, friend, statusOf),
        );
      case final GroupChatId id:
        chat = ChatId.group(id);
      case final ConferenceId id:
        chat = ChatId.conference(id);
      default:
        return ChatDetails(summary: summary, selfKey: selfKey);
    }
    final subject = Subject.chat(chat);
    return ChatDetails(
      summary: summary,
      // Conferences have only a title, their name.
      topic: chat is GroupChat ? fact(account.facts, subject, topicOf) : null,
      selfKey: selfKey,
      selfName:
          fact(
            account.facts,
            subject,
            (v) => v is SelfNameValue ? v.name : null,
          ) ??
          account.name,
      selfRole: fact(account.facts, subject, roleOf),
      // The home device says what Tox says only while it's in session.
      members: live != null && live.of(const Subject.account()).isNotEmpty
          ? ([
              for (final peer in live.subjects)
                if (peer case PeerSubject(chat: final c, :final pk)
                    when c == chat)
                  ChatMember(
                    pk: pk,
                    name: live.nameOf(peer),
                    role: live.find(peer, roleOf),
                    status: live.find(peer, statusOf),
                  ),
            ]..sort(_byRoleThenName))
          : null,
    );
  }
}

int _byRoleThenName(ChatMember a, ChatMember b) {
  final role = (a.role?.index ?? Role.values.length).compareTo(
    b.role?.index ?? Role.values.length,
  );
  return role != 0
      ? role
      : (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
}
