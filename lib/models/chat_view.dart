import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/setting.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_view.freezed.dart';

enum ChatContentState { none, pending, sent, delivered, seen }

/// A chat of one of the profiles, by its account's graph for it.
@freezed
abstract class ChatRef with _$ChatRef {
  const factory ChatRef(Id<Profiles> profile, GraphId graph) = _ChatRef;

  const ChatRef._();

  /// Names the chat in notifications and between isolates.
  String get key => '${profile.value}:${graph.toJson()}';

  static ChatRef? ofKey(String key) {
    try {
      return switch (key.split(':')) {
        [final profile, final graph] when graph.length == 2 * GraphId.kLength =>
          ChatRef(Id(int.parse(profile)), GraphId.fromJson(graph)),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }
}

@freezed
abstract class ChatSummary with _$ChatSummary {
  const factory ChatSummary({
    required ChatRef ref,
    String? name,
    // Drawn as the identicon.
    required CryptoBytes key,
    // Null where online doesn't apply, as for groups.
    bool? online,
    @Default(0) int unread,
    // Where it's muted now.
    Mute? mute,
    ChatEntry? last,
    // What's being written in it, as the chat list shows it.
    Content? draft,
    // No longer a friend's or a joined chat's: what was said still shows.
    @Default(false) bool closed,
  }) = _ChatSummary;

  const ChatSummary._();

  ChatId? get chatId => switch (key) {
    final GroupChatId id => GroupChat(id),
    final ConferenceId id => ConferenceChat(id),
    _ => null,
  };
}

@freezed
abstract class FileProgress with _$FileProgress {
  const factory FileProgress({
    FileState? state,
    int? transferred,
    // Set where this device runs the transfer, so it can be accepted.
    Id<Transfers>? transfer,
    // A linked account's file its home device holds, to fetch from there.
    BlobId? blob,
  }) = _FileProgress;
}

@freezed
abstract class ChatEntry with _$ChatEntry {
  const factory ChatEntry({
    required EventId event,
    // Shown with others' messages in group chats.
    String? sender,
    // The group sender's key, where Tox gives one: not for messages a bot
    // relayed, whose sender is only a name.
    PublicKey? from,
    required bool mine,
    required Content content,
    required DateTime timestamp,
    @Default(ChatContentState.none) ChatContentState state,
    // When a message or file of ours arrived.
    DateTime? delivered,
    FileProgress? file,
    // Joins, leaves and the like, not anyone's message.
    @Default(false) bool notice,
  }) = _ChatEntry;

  const ChatEntry._();

  bool get forwardable => switch (content) {
    FileContent(:final path) =>
      path.isNotEmpty && (mine || file?.state == FileState.done),
    final content => messageTextOf(content) != null,
  };

  /// How far a message of ours got: a file has arrived when it has all been
  /// sent.
  ChatContentState get delivery => switch ((file, mine)) {
    (null, _) => state,
    (FileProgress(state: FileState.active), true) => ChatContentState.pending,
    (FileProgress(state: FileState.done), true) => ChatContentState.delivered,
    _ => ChatContentState.none,
  };
}
