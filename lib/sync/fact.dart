import 'dart:typed_data';

import 'package:btox/models/crypto.dart';
import 'package:btox/sync/codec.dart';
import 'package:btox/sync/event.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'fact.freezed.dart';

const _subjectAccount = 0;
const _subjectFriend = 1;
const _subjectChat = 2;
const _subjectPeer = 3;

const _kindName = 0;
const _kindStatusMessage = 1;
const _kindStatus = 2;
const _kindConnection = 3;
const _kindTyping = 4;
const _kindTopic = 5;
const _kindRole = 6;
const _kindPrivacy = 7;
const _kindPeerLimit = 8;
const _kindPassword = 9;
const _kindTopicLock = 10;
const _kindVoiceState = 11;
const _kindJoined = 12;
const _kindSelfName = 13;
const _kindPresent = 14;
const _kindAddress = 15;
const _kindCall = 16;
const _kindCallRelay = 17;

const _callNone = 0;
const _callRinging = 1;
const _callAnswered = 2;

/// What a fact is about.
@freezed
sealed class Subject with _$Subject {
  const factory Subject.account() = AccountSubject;
  const factory Subject.friend(PublicKey pk) = FriendSubject;
  const factory Subject.chat(ChatId chat) = ChatSubject;
  const factory Subject.peer(ChatId chat, PublicKey pk) = PeerSubject;
}

// Tox's own values, in the order Tox numbers them.
enum UserStatus { online, away, busy }

enum Connection { none, tcp, udp }

enum Role { founder, moderator, user, observer }

enum Privacy { public, private }

enum VoiceState { everyone, moderators, founder }

/// A friend's call, as the home device has it.
@freezed
sealed class CallState with _$CallState {
  const factory CallState.none() = NoCall;

  /// Ringing at the home device, for a device to answer.
  const factory CallState.ringing({required bool video}) = RingingCall;

  /// Going on, through one of the account's devices.
  const factory CallState.answered() = AnsweredCall;
}

/// A subject has at most one value of each kind.
@freezed
sealed class FactValue with _$FactValue {
  const factory FactValue.name(String name) = NameValue;
  const factory FactValue.statusMessage(String message) = StatusMessageValue;
  const factory FactValue.status(UserStatus status) = StatusValue;
  const factory FactValue.connection(Connection connection) = ConnectionValue;
  const factory FactValue.typing(bool typing) = TypingValue;
  const factory FactValue.topic(String topic) = TopicValue;
  const factory FactValue.role(Role role) = RoleValue;
  const factory FactValue.privacy(Privacy privacy) = PrivacyValue;
  const factory FactValue.peerLimit(int limit) = PeerLimitValue;
  // Empty for none.
  const factory FactValue.password(String password) = PasswordValue;
  const factory FactValue.topicLock(bool locked) = TopicLockValue;
  const factory FactValue.voiceState(VoiceState voiceState) = VoiceStateValue;
  const factory FactValue.joined(bool joined) = JoinedValue;
  // Our name in a chat, where it has its own.
  const factory FactValue.selfName(String name) = SelfNameValue;
  const factory FactValue.present(bool present) = PresentValue;
  const factory FactValue.address(Uint8List address) = AddressValue;
  const factory FactValue.call(CallState state) = CallValue;

  /// The home device connects devices to the account's calls.
  const factory FactValue.callRelay(bool relays) = CallRelayValue;

  /// From a newer version, or a value this one doesn't know: shows nothing.
  const factory FactValue.unknown(int kind) = UnknownValue;

  const FactValue._();

  int get kind => switch (this) {
    NameValue() => _kindName,
    StatusMessageValue() => _kindStatusMessage,
    StatusValue() => _kindStatus,
    ConnectionValue() => _kindConnection,
    TypingValue() => _kindTyping,
    TopicValue() => _kindTopic,
    RoleValue() => _kindRole,
    PrivacyValue() => _kindPrivacy,
    PeerLimitValue() => _kindPeerLimit,
    PasswordValue() => _kindPassword,
    TopicLockValue() => _kindTopicLock,
    VoiceStateValue() => _kindVoiceState,
    JoinedValue() => _kindJoined,
    SelfNameValue() => _kindSelfName,
    PresentValue() => _kindPresent,
    AddressValue() => _kindAddress,
    CallValue() => _kindCall,
    CallRelayValue() => _kindCallRelay,
    UnknownValue(:final kind) => kind,
  };
}

typedef Fact = (Subject, FactValue);

final class Facts {
  final Map<Subject, Map<int, FactValue>> _facts;

  Facts([Map<Subject, Map<int, FactValue>>? facts]) : _facts = facts ?? {};

  Facts.of(Iterable<Fact> facts) : _facts = {} {
    update(facts);
  }

  Iterable<FactValue> of(Subject subject) =>
      _facts[subject]?.values ?? const [];

  @override
  bool operator ==(Object other) =>
      other is Facts &&
      const DeepCollectionEquality().equals(_facts, other._facts);

  @override
  int get hashCode => const DeepCollectionEquality().hash(_facts);

  Iterable<Subject> get subjects => _facts.keys;

  /// The value of [subject] [pick] takes, if any.
  T? find<T>(Subject subject, T? Function(FactValue) pick) {
    for (final value in of(subject)) {
      if (pick(value) case final picked?) {
        return picked;
      }
    }
    return null;
  }

  String? nameOf(Subject subject) =>
      find(subject, (v) => v is NameValue ? v.name : null);

  Facts copy() => Facts({
    for (final MapEntry(key: subject, value: values) in _facts.entries)
      subject: {...values},
  });

  void set(Subject subject, FactValue value) =>
      (_facts[subject] ??= {})[value.kind] = value;

  /// Takes in live facts: `Present(false)` drops a subject.
  void update(Iterable<Fact> facts) {
    for (final (subject, value) in facts) {
      if (value == const FactValue.present(false)) {
        _facts.remove(subject);
      } else {
        set(subject, value);
      }
    }
  }
}

// The account is a bare tag, other subjects are `[tag, payload]`.
ArrayWriter _addSubject(ArrayWriter into, Subject subject) => switch (subject) {
  AccountSubject() => into.uint(_subjectAccount),
  FriendSubject(:final pk) => into.array(
    ArrayWriter().uint(_subjectFriend).bin(pk.bytes),
  ),
  ChatSubject(:final chat) => into.array(
    ArrayWriter().uint(_subjectChat).array(encodeChat(chat)),
  ),
  PeerSubject(:final chat, :final pk) => into.array(
    ArrayWriter()
        .uint(_subjectPeer)
        .array(ArrayWriter().array(encodeChat(chat)).bin(pk.bytes)),
  ),
};

ArrayWriter _encodeValue(FactValue value) {
  final f = ArrayWriter().uint(value.kind);
  return switch (value) {
    NameValue(:final name) => f.string(name),
    StatusMessageValue(:final message) => f.string(message),
    StatusValue(:final status) => f.uint(status.index),
    ConnectionValue(:final connection) => f.uint(connection.index),
    TypingValue(:final typing) => f.flag(typing),
    TopicValue(:final topic) => f.string(topic),
    RoleValue(:final role) => f.uint(role.index),
    PrivacyValue(:final privacy) => f.uint(privacy.index),
    PeerLimitValue(:final limit) => f.uint(limit),
    PasswordValue(:final password) => f.string(password),
    TopicLockValue(:final locked) => f.flag(locked),
    VoiceStateValue(:final voiceState) => f.uint(voiceState.index),
    JoinedValue(:final joined) => f.flag(joined),
    SelfNameValue(:final name) => f.string(name),
    PresentValue(:final present) => f.flag(present),
    AddressValue(:final address) => f.bin(address),
    CallValue(:final state) => switch (state) {
      NoCall() => f.uint(_callNone),
      RingingCall(:final video) => f.array(
        ArrayWriter().uint(_callRinging).flag(video),
      ),
      AnsweredCall() => f.uint(_callAnswered),
    },
    CallRelayValue(:final relays) => f.flag(relays),
    // Never re-encoded: stores keep the bytes they received.
    UnknownValue() => throw StateError('Unknown values are not written'),
  };
}

/// The key a subject is stored under.
Uint8List encodeSubject(Subject subject) =>
    _addSubject(ArrayWriter(), subject).encode();

/// Decodes what [encodeFact] wrote.
Fact decodeFact(Uint8List bytes) => decodeExact(bytes, (unpacker) {
  final fields = Fields(unpacker);
  final fact = readFact(fields);
  fields.exact();
  return fact;
});

/// `[subject, value]`, as a fact or wish's fields.
ArrayWriter encodeFact(Subject subject, FactValue value) =>
    _addSubject(ArrayWriter(), subject).array(_encodeValue(value));

Subject readSubject(Fields f) => f.variant<Subject>(
  (tag, s) => switch (tag) {
    _subjectFriend => Subject.friend(PublicKey(s.bin())),
    _subjectChat => Subject.chat(decodeChat(s)),
    _subjectPeer => s.fields(
      (p) => Subject.peer(decodeChat(p), PublicKey(p.bin())),
    ),
    _ => null,
  },
  (tag) => tag == _subjectAccount
      ? const Subject.account()
      : throw const FormatException('Unknown subject'),
);

/// Tox's value of [values] that [v] holds, or null for one this version
/// doesn't know, as one a newer version gave a payload.
FactValue? _known<T>(List<T> values, Fields v, FactValue Function(T) make) {
  final index = v.variant<int>((_, payload) {
    payload.end();
    return -1;
  }, (tag) => tag);
  return index >= 0 && index < values.length ? make(values[index]) : null;
}

FactValue readValue(Fields f) => f.variant<FactValue>(
  (kind, v) => switch (kind) {
    _kindName => FactValue.name(v.string()),
    _kindStatusMessage => FactValue.statusMessage(v.string()),
    _kindStatus => _known(UserStatus.values, v, FactValue.status),
    _kindConnection => _known(Connection.values, v, FactValue.connection),
    _kindTyping => FactValue.typing(v.flag()),
    _kindTopic => FactValue.topic(v.string()),
    _kindRole => _known(Role.values, v, FactValue.role),
    _kindPrivacy => _known(Privacy.values, v, FactValue.privacy),
    _kindPeerLimit => FactValue.peerLimit(v.uint()),
    _kindPassword => FactValue.password(v.string()),
    _kindTopicLock => FactValue.topicLock(v.flag()),
    _kindVoiceState => _known(VoiceState.values, v, FactValue.voiceState),
    _kindJoined => FactValue.joined(v.flag()),
    _kindSelfName => FactValue.selfName(v.string()),
    _kindPresent => FactValue.present(v.flag()),
    _kindAddress => FactValue.address(v.bin()),
    _kindCall => switch (_readCall(v)) {
      final state? => FactValue.call(state),
      null => null,
    },
    _kindCallRelay => FactValue.callRelay(v.flag()),
    _ => null,
  },
  FactValue.unknown,
);

/// Null for a state this version doesn't know.
CallState? _readCall(Fields f) => f.variant<CallState?>(
  (tag, c) => tag == _callRinging ? CallState.ringing(video: c.flag()) : null,
  (tag) => switch (tag) {
    _callNone => const CallState.none(),
    _callAnswered => const CallState.answered(),
    _ => null,
  },
);

Fact readFact(Fields f) => (readSubject(f), readValue(f));
