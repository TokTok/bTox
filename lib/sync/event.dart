import 'dart:typed_data';

import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/models/crypto.dart';
import 'package:btox/sync/codec.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/setting.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'event.freezed.dart';

/// An event with its ID and the bytes that name it.
typedef NewEvent = (EventId, SyncEvent, Uint8List);

const eventVersion = 3;

// Conversation kinds are numbered from 0 and account kinds from 64.
const _tagReceived = 0;
const _tagSend = 1;
const _tagSent = 2;
const _tagDelivered = 3;
const _tagNotice = 4;
const _tagFileStarted = 5;
const _tagFileEnded = 6;
const _tagFileAnswered = 7;
const _tagCall = 8;
const _tagCallEnded = 9;
const _tagWantFriend = 64;
const _tagUnwantFriend = 65;
const _tagReadUpTo = 66;
const _tagFriendRequested = 67;
const _tagMergeChat = 68;
const _tagRelayBot = 69;
const _tagFact = 70;
const _tagWant = 71;
const _tagChatInvite = 72;
const _tagAnswerInvite = 73;
const _tagInviteJoined = 74;
const _tagSetting = 75;
const _tagClearSetting = 76;

const _kindNormal = 0;
const _kindAction = 1;

const _chatGroup = 0;
const _chatConference = 1;

/// What a [ChatId] is of.
enum ChatKind { group, conference }

@freezed
sealed class ChatId with _$ChatId {
  const factory ChatId.group(GroupChatId id) = GroupChat;
  const factory ChatId.conference(ConferenceId id) = ConferenceChat;

  const ChatId._();

  /// The graph of its conversation.
  GraphId get graph => switch (this) {
    GroupChat(:final id) => GraphId.group(id),
    ConferenceChat(:final id) => GraphId.conference(id),
  };
}

@freezed
sealed class EventContent with _$EventContent {
  const factory EventContent.wantFriend({
    required PublicKey pk,
    String? requestMessage,
    // With [pk], the address a friend request goes to.
    ToxAddressNospam? nospam,
  }) = WantFriend;
  const factory EventContent.unwantFriend({required PublicKey pk}) =
      UnwantFriend;
  // Messages in [graph] up to [event], whose rank is [rank], have been read.
  const factory EventContent.readUpTo({
    required GraphId graph,
    required EventId event,
    required int rank,
  }) = ReadUpTo;
  const factory EventContent.friendRequested({
    required PublicKey pk,
    required String message,
  }) = FriendRequested;
  // [chat] shows with [into], as [bot] in [chat] and [intoBot] in [into]
  // relay messages between them, or unmerged where [merged] is false.
  const factory EventContent.mergeChat({
    required ChatId chat,
    required PublicKey bot,
    required ChatId into,
    required PublicKey intoBot,
    required bool merged,
  }) = MergeChat;
  // [bot] in [chat] relays messages from another chat as `<name> text`, or
  // no more where [relays] is false.
  const factory EventContent.relayBot({
    required ChatId chat,
    required PublicKey bot,
    required bool relays,
  }) = RelayBot;
  // What Tox says [subject] has.
  const factory EventContent.fact({
    required Subject subject,
    required FactValue value,
  }) = FactContent;
  // What a device wants Tox to say [subject] has.
  const factory EventContent.want({
    required Subject subject,
    required FactValue value,
  }) = Wish;
  // Friend [from] invites the account to a chat named [name], empty for a
  // conference. [invite] is what Tox joins it with.
  const factory EventContent.chatInvite({
    required PublicKey from,
    required ChatKind kind,
    required String name,
    required Uint8List invite,
  }) = ChatInvite;
  // A device's answer to [invite]: join the chat, with the group's
  // [password] if it has one, or decline.
  const factory EventContent.answerInvite({
    required EventId invite,
    required bool join,
    String? password,
  }) = AnswerInvite;
  // The home carried out a join of [invite]: the chat it joined, or none
  // where Tox refused, [needsPassword] where for a missing or wrong password.
  const factory EventContent.inviteJoined({
    required EventId invite,
    ChatId? chat,
    @Default(false) bool needsPassword,
  }) = InviteJoined;
  // A message's bytes are as Tox carries them. Only showing them decodes them.
  const factory EventContent.received({
    PublicKey? from,
    required String sender,
    required Uint8List message,
    required Tox_Message_Type kind,
  }) = Received;
  const factory EventContent.send({
    required String sender,
    required Uint8List message,
    required Tox_Message_Type kind,
  }) = Send;
  const factory EventContent.sent({required EventId intent}) = Sent;
  const factory EventContent.delivered({required EventId intent}) = Delivered;
  const factory EventContent.notice({required String text}) = Notice;
  const factory EventContent.fileStarted({
    required String sender,
    FileId? fileId,
    required String name,
    required int size,
    required bool incoming,
    // From a device, the file it asks the home to send.
    BlobId? blob,
  }) = FileStarted;
  const factory EventContent.fileEnded({
    required EventId file,
    required bool ok,
    // The file's, which the home holds, when it ended well.
    BlobId? blob,
  }) = FileEnded;
  // A device's answer to a file offered to the home device.
  const factory EventContent.fileAnswered({
    required EventId file,
    required bool accepted,
  }) = FileAnswered;
  // As it rings.
  const factory EventContent.call({
    required String sender,
    required bool incoming,
    required bool video,
  }) = Call;
  // [declined] where it rang here, so it wasn't missed.
  const factory EventContent.callEnded({
    required EventId call,
    Duration? duration,
    @Default(false) bool declined,
  }) = CallEnded;
  // Sets [setting] for [scope]. Per scope and kind, the last writer wins.
  const factory EventContent.setting({
    required Scope scope,
    required Kept<Setting> setting,
  }) = SettingContent;
  // Back to the default: no setting of [kind] for [scope].
  const factory EventContent.clearSetting({
    required Scope scope,
    required int kind,
  }) = ClearSetting;

  /// From a newer version: stored and passed on, but not understood.
  const factory EventContent.unknown(int tag) = UnknownContent;
}

int _kindValue(Tox_Message_Type kind) => switch (kind) {
  Tox_Message_Type.TOX_MESSAGE_TYPE_ACTION => _kindAction,
  _ => _kindNormal,
};

Tox_Message_Type _kindOf(int value) => switch (value) {
  _kindAction => Tox_Message_Type.TOX_MESSAGE_TYPE_ACTION,
  _ => Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
};

ArrayWriter encodeChat(ChatId chat) => switch (chat) {
  GroupChat(:final id) => ArrayWriter().uint(_chatGroup).bin(id.bytes),
  ConferenceChat(:final id) =>
    ArrayWriter().uint(_chatConference).bin(id.bytes),
};

BlobId? _blob(Fields f) => switch (f.optBin()) {
  final blob? => BlobId(blob),
  null => null,
};

ChatId decodeChat(Fields f) => f.variant<ChatId>(
  (kind, chat) => switch (kind) {
    _chatGroup => GroupChat(GroupChatId(chat.bin())),
    _chatConference => ConferenceChat(ConferenceId(chat.bin())),
    _ => null,
  },
  (_) => throw const FormatException('Unknown chat kind'),
);

// Each content type is a variant: `[tag, [fields]]`, or `[tag, field]` for
// one with a single field.
ArrayWriter _encodeContent(EventContent content) {
  ArrayWriter of(int tag, ArrayWriter fields) =>
      ArrayWriter().uint(tag).array(fields);
  final f = ArrayWriter();
  return switch (content) {
    WantFriend(:final pk, :final requestMessage, :final nospam) => of(
      _tagWantFriend,
      f.bin(pk.bytes).optString(requestMessage).optUint(nospam?.value),
    ),
    UnwantFriend(:final pk) =>
      ArrayWriter().uint(_tagUnwantFriend).bin(pk.bytes),
    ReadUpTo(:final graph, :final event, :final rank) => of(
      _tagReadUpTo,
      f.bin(graph.bytes).bin(event.bytes).uint(rank),
    ),
    FriendRequested(:final pk, :final message) => of(
      _tagFriendRequested,
      f.bin(pk.bytes).string(message),
    ),
    MergeChat(
      :final chat,
      :final bot,
      :final into,
      :final intoBot,
      :final merged,
    ) =>
      of(
        _tagMergeChat,
        f
            .array(encodeChat(chat))
            .bin(bot.bytes)
            .array(encodeChat(into))
            .bin(intoBot.bytes)
            .flag(merged),
      ),
    RelayBot(:final chat, :final bot, :final relays) => of(
      _tagRelayBot,
      f.array(encodeChat(chat)).bin(bot.bytes).flag(relays),
    ),
    FactContent(:final subject, :final value) => of(
      _tagFact,
      encodeFact(subject, value),
    ),
    Wish(:final subject, :final value) => of(
      _tagWant,
      encodeFact(subject, value),
    ),
    ChatInvite(:final from, :final kind, :final name, :final invite) => of(
      _tagChatInvite,
      f
          .bin(from.bytes)
          .uint(switch (kind) {
            ChatKind.group => _chatGroup,
            ChatKind.conference => _chatConference,
          })
          .string(name)
          .bin(invite),
    ),
    AnswerInvite(:final invite, :final join, :final password) => of(
      _tagAnswerInvite,
      f.bin(invite.bytes).flag(join).optString(password),
    ),
    InviteJoined(:final invite, :final chat, :final needsPassword) => of(
      _tagInviteJoined,
      f
          .bin(invite.bytes)
          .optArray(chat == null ? null : encodeChat(chat))
          .flag(needsPassword),
    ),
    Received(:final from, :final sender, :final message, :final kind) => of(
      _tagReceived,
      f.optBin(from?.bytes).string(sender).bin(message).uint(_kindValue(kind)),
    ),
    Send(:final sender, :final message, :final kind) => of(
      _tagSend,
      f.string(sender).bin(message).uint(_kindValue(kind)),
    ),
    Sent(:final intent) => ArrayWriter().uint(_tagSent).bin(intent.bytes),
    Delivered(:final intent) =>
      ArrayWriter().uint(_tagDelivered).bin(intent.bytes),
    Notice(:final text) => ArrayWriter().uint(_tagNotice).string(text),
    FileStarted(
      :final sender,
      :final fileId,
      :final name,
      :final size,
      :final incoming,
      :final blob,
    ) =>
      of(
        _tagFileStarted,
        f
            .string(sender)
            .optBin(fileId?.bytes)
            .string(name)
            .uint(size)
            .flag(incoming)
            .optBin(blob?.bytes),
      ),
    FileEnded(:final file, :final ok, :final blob) => of(
      _tagFileEnded,
      f.bin(file.bytes).flag(ok).optBin(blob?.bytes),
    ),
    FileAnswered(:final file, :final accepted) => of(
      _tagFileAnswered,
      f.bin(file.bytes).flag(accepted),
    ),
    Call(:final sender, :final incoming, :final video) => of(
      _tagCall,
      f.string(sender).flag(incoming).flag(video),
    ),
    CallEnded(:final call, :final duration, :final declined) => of(
      _tagCallEnded,
      f.bin(call.bytes).optUint(duration?.inMilliseconds).flag(declined),
    ),
    SettingContent(:final scope, :final setting) => of(
      _tagSetting,
      addSetting(addScope(f, scope), setting),
    ),
    ClearSetting(:final scope, :final kind) => of(
      _tagClearSetting,
      addScope(f, scope).uint(kind),
    ),
    // Never re-encoded: stores keep the bytes they received.
    UnknownContent(:final tag) => ArrayWriter().uint(tag),
  };
}

EventContent _decodeContent(Fields event) => event.variant<EventContent>(
  (tag, c) => switch (tag) {
    _tagWantFriend => c.fields(
      (f) => WantFriend(
        pk: PublicKey(f.bin()),
        requestMessage: f.optString(),
        nospam: switch (f.optUint()) {
          final nospam? => ToxAddressNospam(nospam),
          null => null,
        },
      ),
    ),
    _tagUnwantFriend => UnwantFriend(pk: PublicKey(c.bin())),
    _tagReadUpTo => c.fields(
      (f) => ReadUpTo(
        graph: GraphId(f.bin()),
        event: EventId(f.bin()),
        rank: f.uint(),
      ),
    ),
    _tagFriendRequested => c.fields(
      (f) => FriendRequested(pk: PublicKey(f.bin()), message: f.string()),
    ),
    _tagMergeChat => c.fields(
      (f) => MergeChat(
        chat: decodeChat(f),
        bot: PublicKey(f.bin()),
        into: decodeChat(f),
        intoBot: PublicKey(f.bin()),
        merged: f.flag(),
      ),
    ),
    _tagRelayBot => c.fields(
      (f) => RelayBot(
        chat: decodeChat(f),
        bot: PublicKey(f.bin()),
        relays: f.flag(),
      ),
    ),
    _tagFact => c.fields((f) {
      final (subject, value) = readFact(f);
      return FactContent(subject: subject, value: value);
    }),
    _tagWant => c.fields((f) {
      final (subject, value) = readFact(f);
      return Wish(subject: subject, value: value);
    }),
    _tagChatInvite => c.fields((f) {
      final from = PublicKey(f.bin());
      final kind = switch (f.uint()) {
        _chatGroup => ChatKind.group,
        _chatConference => ChatKind.conference,
        // A kind of chat this version doesn't know shows nothing.
        _ => null,
      };
      final name = f.string();
      final invite = f.bin();
      return kind == null
          ? null
          : ChatInvite(from: from, kind: kind, name: name, invite: invite);
    }),
    _tagAnswerInvite => c.fields(
      (f) => AnswerInvite(
        invite: EventId(f.bin()),
        join: f.flag(),
        password: f.optString(),
      ),
    ),
    _tagInviteJoined => c.fields(
      (f) => InviteJoined(
        invite: EventId(f.bin()),
        chat: f.opt(decodeChat),
        needsPassword: f.laterFlag(),
      ),
    ),
    _tagReceived => c.fields((f) {
      final from = f.optBin();
      return Received(
        from: from == null ? null : PublicKey(from),
        sender: f.string(),
        message: f.bin(),
        kind: _kindOf(f.uint()),
      );
    }),
    _tagSend => c.fields(
      (f) =>
          Send(sender: f.string(), message: f.bin(), kind: _kindOf(f.uint())),
    ),
    _tagSent => Sent(intent: EventId(c.bin())),
    _tagDelivered => Delivered(intent: EventId(c.bin())),
    _tagNotice => Notice(text: c.string()),
    _tagFileStarted => c.fields((f) {
      final sender = f.string();
      final fileId = f.optBin();
      return FileStarted(
        sender: sender,
        fileId: fileId == null ? null : FileId(fileId),
        name: f.string(),
        size: f.uint(),
        incoming: f.flag(),
        blob: _blob(f),
      );
    }),
    _tagFileEnded => c.fields(
      (f) => FileEnded(file: EventId(f.bin()), ok: f.flag(), blob: _blob(f)),
    ),
    _tagFileAnswered => c.fields(
      (f) => FileAnswered(file: EventId(f.bin()), accepted: f.flag()),
    ),
    _tagCall => c.fields(
      (f) => Call(sender: f.string(), incoming: f.flag(), video: f.flag()),
    ),
    _tagCallEnded => c.fields(
      (f) => CallEnded(
        call: EventId(f.bin()),
        duration: switch (f.optUint()) {
          final ms? => Duration(milliseconds: ms),
          null => null,
        },
        declined: f.laterFlag(),
      ),
    ),
    _tagSetting => c.fields(
      (f) => SettingContent(scope: readScope(f), setting: readSetting(f)),
    ),
    _tagClearSetting => c.fields(
      (f) => ClearSetting(scope: readScope(f), kind: f.uint()),
    ),
    _ => null,
  },
  UnknownContent.new,
);

@freezed
abstract class SyncEvent with _$SyncEvent {
  const factory SyncEvent({
    required GraphId graph,
    required PublicKey author,
    required List<EventId> parents,
    required int rank,
    // Milliseconds since the Unix epoch, by the author's clock.
    required int time,
    required EventContent content,
  }) = _SyncEvent;

  /// `[version, event]`, decoded exactly: its bytes name it.
  factory SyncEvent.decode(Uint8List bytes) => decodeExact(bytes, (unpacker) {
    final versioned = Fields(unpacker);
    if (versioned.uint() != eventVersion) {
      throw const FormatException('Unknown event version');
    }
    final event = versioned.fields(
      (e) => SyncEvent(
        graph: GraphId(e.bin()),
        author: PublicKey(e.bin()),
        parents: e.list((list) => EventId(list.bin())),
        rank: e.uint(),
        time: checkTime(e.sint()),
        content: _decodeContent(e),
      ),
    );
    versioned.exact();
    return event;
  });

  const SyncEvent._();

  Uint8List encode() {
    final parentList = ArrayWriter();
    for (final parent in parents) {
      parentList.bin(parent.bytes);
    }
    return (ArrayWriter()
          ..uint(eventVersion)
          ..array(
            ArrayWriter()
              ..bin(graph.bytes)
              ..bin(author.bytes)
              ..array(parentList)
              ..uint(rank)
              ..sint(time)
              ..array(_encodeContent(content)),
          ))
        .encode();
  }
}
