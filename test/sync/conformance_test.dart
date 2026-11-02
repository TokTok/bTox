// Runs the cases in test/sync/conformance, rs-toxcore-c's sync/conformance
// as tools/update-sync-conformance copies them, so bTox encodes, decodes and
// syncs as every other implementation does.

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/messages/message_format.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/packets/messagepack.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/codec.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/frames.dart';
import 'package:btox/sync/pairing.dart';
import 'package:btox/sync/replica.dart';
import 'package:btox/sync/session.dart' as session;
import 'package:btox/sync/session_message.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/sync/store.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';

/// More than any session takes.
const _maxRounds = 1000;

void main() {
  _cases('codec', _codec);
  _cases('state', _state);
  _cases('store', _store);
  _cases('session', _session);
}

typedef _Case = void Function(_Check check);

void _cases(String file, Map<String, _Case> Function(Map<String, Object?>) of) {
  final json = jsonDecode(
    File('test/sync/conformance/$file.json').readAsStringSync(),
  ) as Map<String, Object?>;
  group(file, () {
    for (final MapEntry(key: name, value: run) in of(json).entries) {
      test(name, () {
        final check = _Check();
        run(check);
        expect(check.failures, isEmpty, reason: check.failures.join('\n'));
      });
    }
  });
}

final class _Check {
  final failures = <String>[];

  void call(String what, Object? expected, Object? actual) {
    final (e, a) = (_canonical(expected), _canonical(actual));
    if (e != a) {
      failures.add('$what\n  expected $e\n  actual   $a');
    }
  }
}

String _canonical(Object? j) => switch (j) {
  Map() =>
    '{${(j.keys.cast<String>().toList()..sort()).map((k) => '${jsonEncode(k)}:${_canonical(j[k])}').join(',')}}',
  List() => '[${j.map(_canonical).join(',')}]',
  _ => jsonEncode(j),
};

List<Object?> _sorted(Iterable<Object?> items) =>
    items.toList()..sort((a, b) => _canonical(a).compareTo(_canonical(b)));

String _hex(List<int> bytes) => hex.encode(bytes);

Uint8List _bytes(Object? j) => Uint8List.fromList(hex.decode(j! as String));

PublicKey _pk(Object? j) => PublicKey(_bytes(j));

EventId _id(Object? j) => EventId(_bytes(j));

GraphId _graph(Object? j) => GraphId(_bytes(j));

List<EventId> _ids(Object? j) => [for (final id in j! as List) _id(id)];

List<Object?> _idsJson(Iterable<EventId> ids) => [
  for (final id in ids) _hex(id.bytes),
];

R? _opt<T extends Object, R>(T? value, R Function(T) read) =>
    value == null ? null : read(value);

(String, Object?) _variant(Object? j) => switch (j) {
  final String tag => (tag, null),
  Map(length: 1) => (j.keys.single as String, j.values.single),
  _ => throw ArgumentError('Not a variant: $j'),
};

Map<String, Object?> _map(Object? j) => (j! as Map).cast<String, Object?>();

ChatId _chat(Object? j) => switch (_variant(j)) {
  ('group', final id) => ChatId.group(GroupChatId(_bytes(id))),
  ('conference', final id) => ChatId.conference(ConferenceId(_bytes(id))),
  final other => throw ArgumentError('Not a chat: $other'),
};

Object? _chatJson(ChatId chat) => switch (chat) {
  GroupChat(:final id) => {'group': _hex(id.bytes)},
  ConferenceChat(:final id) => {'conference': _hex(id.bytes)},
};

Subject _subject(Object? j) => switch (_variant(j)) {
  ('account', _) => const Subject.account(),
  ('friend', final pk) => Subject.friend(_pk(pk)),
  ('chat', final chat) => Subject.chat(_chat(chat)),
  ('peer', final peer) => Subject.peer(
    _chat(_map(peer)['chat']),
    _pk(_map(peer)['pk']),
  ),
  final other => throw ArgumentError('Not a subject: $other'),
};

Object? _subjectJson(Subject subject) => switch (subject) {
  AccountSubject() => 'account',
  FriendSubject(:final pk) => {'friend': _hex(pk.bytes)},
  ChatSubject(:final chat) => {'chat': _chatJson(chat)},
  PeerSubject(:final chat, :final pk) => {
    'peer': {'chat': _chatJson(chat), 'pk': _hex(pk.bytes)},
  },
};

FactValue _value(Object? j) {
  final (kind, v) = _variant(j);
  return switch (kind) {
    'name' => FactValue.name(v! as String),
    'status_message' => FactValue.statusMessage(v! as String),
    'status' => FactValue.status(UserStatus.values.byName(v! as String)),
    'connection' => FactValue.connection(
      Connection.values.byName(v! as String),
    ),
    'typing' => FactValue.typing(v! as bool),
    'topic' => FactValue.topic(v! as String),
    'role' => FactValue.role(Role.values.byName(v! as String)),
    'privacy' => FactValue.privacy(Privacy.values.byName(v! as String)),
    'peer_limit' => FactValue.peerLimit(v! as int),
    'password' => FactValue.password(v! as String),
    'topic_lock' => FactValue.topicLock(v! as bool),
    'voice_state' => FactValue.voiceState(
      VoiceState.values.byName(v! as String),
    ),
    'joined' => FactValue.joined(v! as bool),
    'self_name' => FactValue.selfName(v! as String),
    'present' => FactValue.present(v! as bool),
    'address' => FactValue.address(_bytes(v)),
    'call' => FactValue.call(switch (_variant(v)) {
      ('none', _) => const CallState.none(),
      ('ringing', final ringing) => CallState.ringing(
        video: _map(ringing)['video']! as bool,
      ),
      ('answered', _) => const CallState.answered(),
      final other => throw ArgumentError('Not a call: $other'),
    }),
    'call_relay' => FactValue.callRelay(v! as bool),
    'self_key' => FactValue.selfKey(_pk(v)),
    'avatar' => FactValue.avatar(_opt(v, (b) => BlobId(_bytes(b)))),
    _ => throw ArgumentError('Not a value: $kind'),
  };
}

Object? _valueJson(FactValue value) => switch (value) {
  NameValue(:final name) => {'name': name},
  StatusMessageValue(:final message) => {'status_message': message},
  StatusValue(:final status) => {'status': status.name},
  ConnectionValue(:final connection) => {'connection': connection.name},
  TypingValue(:final typing) => {'typing': typing},
  TopicValue(:final topic) => {'topic': topic},
  RoleValue(:final role) => {'role': role.name},
  PrivacyValue(:final privacy) => {'privacy': privacy.name},
  PeerLimitValue(:final limit) => {'peer_limit': limit},
  PasswordValue(:final password) => {'password': password},
  TopicLockValue(:final locked) => {'topic_lock': locked},
  VoiceStateValue(:final voiceState) => {'voice_state': voiceState.name},
  JoinedValue(:final joined) => {'joined': joined},
  SelfNameValue(:final name) => {'self_name': name},
  PresentValue(:final present) => {'present': present},
  AddressValue(:final address) => {'address': _hex(address)},
  CallValue(:final state) => {
    'call': switch (state) {
      NoCall() => 'none',
      RingingCall(:final video) => {
        'ringing': {'video': video},
      },
      AnsweredCall() => 'answered',
    },
  },
  CallRelayValue(:final relays) => {'call_relay': relays},
  SelfKeyValue(:final key) => {'self_key': _hex(key.bytes)},
  AvatarValue(:final blob) => {'avatar': _opt(blob, (b) => _hex(b.bytes))},
  UnknownValue(:final kind) => {'unknown': kind},
};

Object? _factJson(Fact fact) => [_subjectJson(fact.$1), _valueJson(fact.$2)];

Scope _scope(Object? j) => switch (_variant(j)) {
  ('account', _) => const Scope.account(),
  ('conversation', final graph) => Scope.conversation(_graph(graph)),
  final other => throw ArgumentError('Not a scope: $other'),
};

Object? _scopeJson(Scope scope) => switch (scope) {
  AccountScope() => 'account',
  ConversationScope(:final graph) => {'conversation': _hex(graph.bytes)},
  UnknownScope(:final tag) => {'unknown': tag},
};

Setting _setting(Object? j) => switch (_variant(j)) {
  ('mute', final mute) => Setting.mute(
    until: _opt(_map(mute)['until'], (ms) {
      return DateTime.fromMillisecondsSinceEpoch(ms as int);
    }),
    mentions: _map(mute)['mentions']! as bool,
  ),
  ('picture_format', final format) => Setting.pictureFormat(
    PictureEncoding.values.byName(format! as String),
  ),
  final other => throw ArgumentError('Not a setting: $other'),
};

Object? _settingJson(Setting setting) => switch (setting) {
  Mute(:final until, :final mentions) => {
    'mute': {'until': until?.millisecondsSinceEpoch, 'mentions': mentions},
  },
  PictureFormat(:final format) => {'picture_format': format.name},
  UnknownSetting(:final kind) => {'unknown': kind},
};

Tox_Message_Type _messageKind(Object? j) => switch (j) {
  'normal' => Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
  'action' => Tox_Message_Type.TOX_MESSAGE_TYPE_ACTION,
  _ => throw ArgumentError('Not a message kind: $j'),
};

String _messageKindJson(Tox_Message_Type kind) =>
    kind == Tox_Message_Type.TOX_MESSAGE_TYPE_ACTION ? 'action' : 'normal';

EventContent _content(Object? j) {
  final (tag, payload) = _variant(j);
  final c = _map(payload);
  BlobId? blob(Object? j) => _opt(j, (b) => BlobId(_bytes(b)));
  return switch (tag) {
    'received' => Received(
      from: _opt(c['from'], _pk),
      sender: c['sender']! as String,
      message: _bytes(c['message']),
      kind: _messageKind(c['kind']),
    ),
    'send' => Send(
      sender: c['sender']! as String,
      message: _bytes(c['message']),
      kind: _messageKind(c['kind']),
    ),
    'sent' => Sent(intent: _id(c['intent'])),
    'delivered' => Delivered(intent: _id(c['intent'])),
    'notice' => Notice(text: c['text']! as String),
    'file' => FileStarted(
      sender: c['sender']! as String,
      fileId: _opt(c['file_id'], (f) => FileId(_bytes(f))),
      name: c['name']! as String,
      size: c['size']! as int,
      incoming: c['incoming']! as bool,
      blob: blob(c['blob']),
    ),
    'file_ended' => FileEnded(
      file: _id(c['file']),
      ok: c['ok']! as bool,
      blob: blob(c['blob']),
    ),
    'file_answered' => FileAnswered(
      file: _id(c['file']),
      accepted: c['accepted']! as bool,
    ),
    'call' => Call(
      sender: c['sender']! as String,
      incoming: c['incoming']! as bool,
      video: c['video']! as bool,
    ),
    'call_ended' => CallEnded(
      call: _id(c['call']),
      duration: _opt(c['duration'], (ms) => Duration(milliseconds: ms as int)),
      declined: c['declined']! as bool,
    ),
    'want_friend' => WantFriend(
      pk: _pk(c['pk']),
      requestMessage: c['request_message'] as String?,
      nospam: _opt(c['nospam'], (n) => ToxAddressNospam(n as int)),
    ),
    'unwant_friend' => UnwantFriend(pk: _pk(c['pk'])),
    'read_up_to' => ReadUpTo(
      graph: _graph(c['graph']),
      event: _id(c['event']),
      rank: c['rank']! as int,
    ),
    'friend_request' => FriendRequested(
      pk: _pk(c['pk']),
      message: c['message']! as String,
    ),
    'merge_chat' => MergeChat(
      chat: _chat(c['chat']),
      bot: _pk(c['bot']),
      into: _chat(c['into']),
      intoBot: _pk(c['into_bot']),
      merged: c['merged']! as bool,
    ),
    'relay_bot' => RelayBot(
      chat: _chat(c['chat']),
      bot: _pk(c['bot']),
      relays: c['relays']! as bool,
    ),
    'fact' => FactContent(
      subject: _subject(c['subject']),
      value: _value(c['value']),
    ),
    'want' => Wish(subject: _subject(c['subject']), value: _value(c['value'])),
    'chat_invite' => ChatInvite(
      from: _pk(c['from']),
      kind: ChatKind.values.byName(c['kind']! as String),
      name: c['name']! as String,
      invite: _bytes(c['invite']),
    ),
    'answer_invite' => AnswerInvite(
      invite: _id(c['invite']),
      join: c['join']! as bool,
      password: c['password'] as String?,
    ),
    'invite_joined' => InviteJoined(
      invite: _id(c['invite']),
      chat: _opt(c['chat'], _chat),
      needsPassword: c['needs_password']! as bool,
    ),
    'setting' => SettingContent(
      scope: _scope(c['scope']),
      setting: Kept(_setting(c['setting'])),
    ),
    'clear_setting' => ClearSetting(
      scope: _scope(c['scope']),
      kind: c['kind']! as int,
    ),
    _ => throw ArgumentError('Not content: $tag'),
  };
}

Object? _contentJson(EventContent content) => switch (content) {
  Received(:final from, :final sender, :final message, :final kind) => {
    'received': {
      'from': _opt(from, (k) => _hex(k.bytes)),
      'sender': sender,
      'message': _hex(message),
      'kind': _messageKindJson(kind),
    },
  },
  Send(:final sender, :final message, :final kind) => {
    'send': {
      'sender': sender,
      'message': _hex(message),
      'kind': _messageKindJson(kind),
    },
  },
  Sent(:final intent) => {
    'sent': {'intent': _hex(intent.bytes)},
  },
  Delivered(:final intent) => {
    'delivered': {'intent': _hex(intent.bytes)},
  },
  Notice(:final text) => {
    'notice': {'text': text},
  },
  FileStarted(
    :final sender,
    :final fileId,
    :final name,
    :final size,
    :final incoming,
    :final blob,
  ) =>
    {
      'file': {
        'sender': sender,
        'file_id': _opt(fileId, (f) => _hex(f.bytes)),
        'name': name,
        'size': size,
        'incoming': incoming,
        'blob': _opt(blob, (b) => _hex(b.bytes)),
      },
    },
  FileEnded(:final file, :final ok, :final blob) => {
    'file_ended': {
      'file': _hex(file.bytes),
      'ok': ok,
      'blob': _opt(blob, (b) => _hex(b.bytes)),
    },
  },
  FileAnswered(:final file, :final accepted) => {
    'file_answered': {'file': _hex(file.bytes), 'accepted': accepted},
  },
  Call(:final sender, :final incoming, :final video) => {
    'call': {'sender': sender, 'incoming': incoming, 'video': video},
  },
  CallEnded(:final call, :final duration, :final declined) => {
    'call_ended': {
      'call': _hex(call.bytes),
      'duration': duration?.inMilliseconds,
      'declined': declined,
    },
  },
  WantFriend(:final pk, :final requestMessage, :final nospam) => {
    'want_friend': {
      'pk': _hex(pk.bytes),
      'request_message': requestMessage,
      'nospam': nospam?.value,
    },
  },
  UnwantFriend(:final pk) => {
    'unwant_friend': {'pk': _hex(pk.bytes)},
  },
  ReadUpTo(:final graph, :final event, :final rank) => {
    'read_up_to': {
      'graph': _hex(graph.bytes),
      'event': _hex(event.bytes),
      'rank': rank,
    },
  },
  FriendRequested(:final pk, :final message) => {
    'friend_request': {'pk': _hex(pk.bytes), 'message': message},
  },
  MergeChat(
    :final chat,
    :final bot,
    :final into,
    :final intoBot,
    :final merged,
  ) =>
    {
      'merge_chat': {
        'chat': _chatJson(chat),
        'bot': _hex(bot.bytes),
        'into': _chatJson(into),
        'into_bot': _hex(intoBot.bytes),
        'merged': merged,
      },
    },
  RelayBot(:final chat, :final bot, :final relays) => {
    'relay_bot': {
      'chat': _chatJson(chat),
      'bot': _hex(bot.bytes),
      'relays': relays,
    },
  },
  FactContent(:final subject, :final value) => {
    'fact': {'subject': _subjectJson(subject), 'value': _valueJson(value)},
  },
  Wish(:final subject, :final value) => {
    'want': {'subject': _subjectJson(subject), 'value': _valueJson(value)},
  },
  ChatInvite(:final from, :final kind, :final name, :final invite) => {
    'chat_invite': {
      'from': _hex(from.bytes),
      'kind': kind.name,
      'name': name,
      'invite': _hex(invite),
    },
  },
  AnswerInvite(:final invite, :final join, :final password) => {
    'answer_invite': {
      'invite': _hex(invite.bytes),
      'join': join,
      'password': password,
    },
  },
  InviteJoined(:final invite, :final chat, :final needsPassword) => {
    'invite_joined': {
      'invite': _hex(invite.bytes),
      'chat': _opt(chat, _chatJson),
      'needs_password': needsPassword,
    },
  },
  SettingContent(:final scope, :final setting) => {
    'setting': {
      'scope': _scopeJson(scope),
      'setting': _settingJson(setting.value),
    },
  },
  ClearSetting(:final scope, :final kind) => {
    'clear_setting': {'scope': _scopeJson(scope), 'kind': kind},
  },
  UnknownContent(:final tag) => {'unknown': tag},
};

SyncEvent _event(Object? j) {
  final e = _map(j);
  return SyncEvent(
    graph: _graph(e['graph']),
    author: _pk(e['author']),
    parents: _ids(e['parents']),
    rank: e['rank']! as int,
    time: e['time']! as int,
    content: _content(e['content']),
  );
}

Object? _eventJson(SyncEvent event) => {
  'graph': _hex(event.graph.bytes),
  'author': _hex(event.author.bytes),
  'parents': _idsJson(event.parents),
  'rank': event.rank,
  'time': event.time,
  'content': _contentJson(event.content),
};

SessionMessage _message(Object? j) {
  final (tag, m) = _variant(j);
  return switch (tag) {
    'hello' => Hello(
      version: _map(m)['version']! as int,
      features: Features(_map(m)['features']! as int),
    ),
    'summary' => Summary([
      for (final entry in m! as List)
        (_graph((entry as List)[0]), HeadsDigest(_bytes(entry[1]))),
    ]),
    'heads' => Heads(
      graph: _graph(_map(m)['graph']),
      heads: _ids(_map(m)['heads']),
    ),
    'want' => Want(_ids(m)),
    'events' => Events([for (final e in m! as List) _bytes(e)]),
    'history' => History(
      graph: _graph(_map(m)['graph']),
      before: _ids(_map(m)['before']),
      limit: _map(m)['limit']! as int,
    ),
    'want_blob' => WantBlob(BlobId(_bytes(m))),
    'no_blob' => NoBlob(BlobId(_bytes(m))),
    'facts' => FactsUpdate([
      for (final fact in _map(m)['facts']! as List)
        (_subject((fact as List)[0]), _value(fact[1])),
    ], all: _map(m)['all']! as bool),
    'call' => CallControl(_pk(_map(m)['friend']), switch (_variant(
      _map(m)['action'],
    )) {
      ('connect', final c) => CallAction.connect(
        video: _map(c)['video']! as bool,
      ),
      ('hang_up', _) => const CallAction.hangUp(),
      final other => throw ArgumentError('Not a call action: $other'),
    }),
    _ => throw ArgumentError('Not a message: $tag'),
  };
}

Object? _messageJson(SessionMessage message) => switch (message) {
  Hello(:final version, :final features) => {
    'hello': {'version': version, 'features': features.bits},
  },
  Summary(:final graphs) => {
    'summary': [
      for (final (graph, digest) in graphs)
        [_hex(graph.bytes), _hex(digest.bytes)],
    ],
  },
  Heads(:final graph, :final heads) => {
    'heads': {'graph': _hex(graph.bytes), 'heads': _idsJson(heads)},
  },
  Want(:final ids) => {'want': _idsJson(ids)},
  Events(:final events) => {'events': events.map(_hex).toList()},
  History(:final graph, :final before, :final limit) => {
    'history': {
      'graph': _hex(graph.bytes),
      'before': _idsJson(before),
      'limit': limit,
    },
  },
  WantBlob(:final blob) => {'want_blob': _hex(blob.bytes)},
  NoBlob(:final blob) => {'no_blob': _hex(blob.bytes)},
  FactsUpdate(:final facts, :final all) => {
    'facts': {'facts': facts.map(_factJson).toList(), 'all': all},
  },
  CallControl(:final friend, :final action) => {
    'call': {
      'friend': _hex(friend.bytes),
      'action': switch (action) {
        ConnectCall(:final video) => {
          'connect': {'video': video},
        },
        HangUpCall() => 'hang_up',
      },
    },
  },
};

/// Replies, whose order says nothing, as the lists in them whose order says
/// nothing: all but events, which come in the order asked for.
List<Object?> _repliesJson(Iterable<SessionMessage> messages) => _sorted([
  for (final message in messages)
    switch (message) {
      Summary(:final graphs) => {
        'summary': _sorted([
          for (final (graph, digest) in graphs)
            [_hex(graph.bytes), _hex(digest.bytes)],
        ]),
      },
      Heads(:final graph, :final heads) => {
        'heads': {
          'graph': _hex(graph.bytes),
          'heads': _sorted(_idsJson(heads)),
        },
      },
      Want(:final ids) => {'want': _sorted(_idsJson(ids))},
      History(:final graph, :final before, :final limit) => {
        'history': {
          'graph': _hex(graph.bytes),
          'before': _sorted(_idsJson(before)),
          'limit': limit,
        },
      },
      _ => _messageJson(message),
    },
]);

Object? _factsJson(Facts facts) => _sorted([
  for (final subject in facts.subjects)
    for (final value in facts.of(subject)) _factJson((subject, value)),
]);

Object? _stateJson(AccountState state) => {
  'facts': _factsJson(state.facts),
  'friends': _sorted([
    for (final MapEntry(key: pk, value: friend) in state.friends.entries)
      if (friend.wanted || friend.request != null)
        {
          'pk': _hex(pk.bytes),
          'wanted': friend.wanted,
          'request': friend.request,
        },
  ]),
  'merges': _sorted([
    for (final MapEntry(key: chat, value: merge) in state.merges.entries)
      {
        'chat': _chatJson(chat),
        'bot': _hex(merge.bot.bytes),
        'into': _chatJson(merge.into),
        'into_bot': _hex(merge.intoBot.bytes),
      },
  ]),
  'relay_bots': _sorted([
    for (final MapEntry(key: chat, value: bot) in state.relayBots.entries)
      {'chat': _chatJson(chat), 'bot': _hex(bot.bytes)},
  ]),
  'read': _sorted([
    for (final MapEntry(key: graph, value: (rank, event)) in state.read.entries)
      {'graph': _hex(graph.bytes), 'rank': rank, 'event': _hex(event.bytes)},
  ]),
  'settings': _sorted([
    for (final MapEntry(key: scope, value: kinds) in state.settings.entries)
      for (final MapEntry(key: kind, value: kept) in kinds.entries)
        {
          'scope': _scopeJson(scope),
          'kind': kind,
          'setting': _settingJson(kept.value),
          'bytes': _hex(kept.bytes!),
        },
  ]),
  'invites': _sorted([
    for (final MapEntry(key: id, value: invite) in state.invites.entries)
      {
        'invite': _hex(id.bytes),
        'from': _hex(invite.from.bytes),
        'kind': invite.kind.name,
        'name': invite.name,
        'status': invite.status.name,
        'chat': _opt(invite.chat, _chatJson),
        'needs_password':
            invite.status == InviteStatus.failed && invite.needsPassword,
      },
  ]),
};

Object? _countsJson(EventStore store) => _sorted([
  for (final graph in store.graphs)
    {'graph': _hex(graph.bytes), 'count': store.countIn(graph)},
]);

final class _Labels {
  final Map<String, Object?> _values;

  _Labels._(this._values);

  factory _Labels.of(Map<String, Object?> file) {
    final labels = _Labels._({});
    for (final (sigil, table) in [('%', 'keys'), ('&', 'chats')]) {
      for (final MapEntry(:key, :value)
          in (file[table] as Map? ?? const {}).entries) {
        labels._values['$sigil$key'] = labels.resolve(value);
      }
    }
    for (final MapEntry(:key, :value)
        in (file['graphs'] as Map? ?? const {}).entries) {
      final graph = switch (_variant(labels.resolve(value))) {
        ('account', final pk) => GraphId.account(_pk(pk)),
        ('friend', final List pks) => GraphId.friend(_pk(pks[0]), _pk(pks[1])),
        ('group', final id) => GraphId.group(GroupChatId(_bytes(id))),
        ('conference', final id) => GraphId.conference(
          ConferenceId(_bytes(id)),
        ),
        final other => throw ArgumentError('Not a graph: $other'),
      };
      labels._values['\$$key'] = _hex(graph.bytes);
    }
    return labels;
  }

  _Labels copy() => _Labels._({..._values});

  void addEvent(String label, Uint8List bytes) {
    _values['@$label'] = _hex(EventId.of(bytes).bytes);
    _values['#$label'] = _hex(bytes);
  }

  Object? resolve(Object? j) => switch (j) {
    final String s when _values.containsKey(s) => _values[s],
    final String s when RegExp(r'^[%&$@#]').hasMatch(s) => throw ArgumentError(
      'No label $s',
    ),
    List() => [for (final item in j) resolve(item)],
    Map() => <String, Object?>{
      for (final MapEntry(:key, :value) in j.entries)
        key as String: resolve(value),
    },
    _ => j,
  };
}

final class _Pool {
  final events = <(String, Uint8List)>[];
  final chains = <String, List<String>>{};

  List<Uint8List> bytes(String label) => switch (chains[label]) {
    final members? => [for (final member in members) ...bytes(member)],
    null => [events.firstWhere((e) => e.$1 == label).$2],
  };

  EventStore store(Object? labels) {
    final store = EventStore();
    for (final label in (labels as List? ?? const [])) {
      bytes(label as String).forEach(store.insert);
    }
    return store;
  }
}

_Pool _pool(
  _Check check,
  _Labels labels,
  Map<String, Object?> defaults,
  Map<String, Object?> testCase,
) {
  final pool = _Pool();
  final ranks = <EventId, int>{};
  for (final entry
      in (testCase['events']! as List).cast<Map<String, Object?>>()) {
    final spec = {...defaults, ...entry};
    final label = entry['label'] as String?;
    if (entry['raw'] case final raw?) {
      final bytes = _bytes(raw);
      labels.addEvent(label!, bytes);
      pool.events.add((label, bytes));
      continue;
    }
    if (entry['chain'] case final String name) {
      final resolved = _map(labels.resolve(spec));
      var parent = switch (entry['after']) {
        final String after => EventId.of(pool.bytes(after).first),
        _ => null,
      };
      final members = <String>[];
      for (var i = 0; i < (entry['count']! as int); i++) {
        final event = SyncEvent(
          graph: _graph(resolved['graph']),
          author: _pk(resolved['author']),
          parents: [?parent],
          rank: parent == null ? 0 : ranks[parent]! + 1,
          time: i,
          content: Notice(text: '$i'),
        );
        final bytes = event.encode();
        final id = EventId.of(bytes);
        ranks[id] = event.rank;
        labels.addEvent('$name$i', bytes);
        pool.events.add(('$name$i', bytes));
        members.add('$name$i');
        parent = id;
      }
      pool.chains[name] = members;
      continue;
    }
    final resolved = _map(labels.resolve(spec));
    final parents = _ids(resolved['parents'] ?? const []);
    final rank = switch (resolved['rank']) {
      final int rank => rank,
      _ => parents.map((p) => ranks[p]).nonNulls.fold(-1, max) + 1,
    };
    final event = SyncEvent(
      graph: _graph(resolved['graph']),
      author: _pk(resolved['author']),
      parents: parents,
      rank: rank,
      time: resolved['time']! as int,
      content: _content(resolved['content']),
    );
    final bytes = event.encode();
    ranks[EventId.of(bytes)] = rank;
    check('$label: bytes', entry['bytes'], _hex(bytes));
    labels.addEvent(label!, bytes);
    pool.events.add((label, bytes));
  }
  return pool;
}

Iterable<Map<String, Object?>> _list(Map<String, Object?> file, String key) =>
    (file[key]! as List).cast<Map<String, Object?>>();

Object? _decoded(Object? Function() decode) {
  try {
    return decode();
  } on FormatException {
    return 'error';
  }
}

Object? _decodedMessage(Object? bytes) =>
    switch (SessionMessage.decode(_bytes(bytes))) {
      final message? => _messageJson(message),
      null => null,
    };

Map<String, _Case> _codec(Map<String, Object?> file) => {
  for (final c in _list(file, 'ids'))
    c['name']! as String: (check) {
      final digest = switch (_variant(c['of'])) {
        ('account', final pk) => GraphId.account(_pk(pk)).bytes,
        ('friend', final List pks) => GraphId.friend(
          _pk(pks[0]),
          _pk(pks[1]),
        ).bytes,
        ('group', final id) => GraphId.group(GroupChatId(_bytes(id))).bytes,
        ('conference', final id) => GraphId.conference(
          ConferenceId(_bytes(id)),
        ).bytes,
        ('blob', final data) => sha256.convert(_bytes(data)).bytes,
        ('heads', final heads) => HeadsDigest.of(_ids(heads)).bytes,
        final other => throw ArgumentError('Not an ID: $other'),
      };
      check('id', c['id'], _hex(digest));
    },
  for (final c in _list(file, 'events'))
    c['name']! as String: (check) {
      final encoded = _event(c['event']).encode();
      check('bytes', c['bytes'], _hex(encoded));
      check('id', c['id'], _hex(EventId.of(encoded).bytes));
      check(
        'decoded',
        c['event'],
        _decoded(() => _eventJson(SyncEvent.decode(_bytes(c['bytes'])))),
      );
    },
  for (final c in _list(file, 'event_decodings'))
    c['name']! as String: (check) => check(
      'event',
      c['event'],
      _decoded(() => _eventJson(SyncEvent.decode(_bytes(c['bytes'])))),
    ),
  for (final c in _list(file, 'messages'))
    c['name']! as String: (check) {
      check('bytes', c['bytes'], _hex(_message(c['message']).encode()));
      check(
        'decoded',
        c['message'],
        _decoded(() => _decodedMessage(c['bytes'])),
      );
    },
  for (final c in _list(file, 'message_decodings'))
    c['name']! as String: (check) => check(
      'message',
      c['message'],
      _decoded(() => _decodedMessage(c['bytes'])),
    ),
  for (final c in _list(file, 'packets'))
    c['name']! as String: (check) => check('packets', c['packets'], [
      for (final packet in frames(_bytes(c['message']))) _hex(packet),
    ]),
  for (final c in _list(file, 'reassembly'))
    c['name']! as String: (check) {
      final reassembler = Reassembler();
      check('results', c['results'], [
        for (final packet in c['packets']! as List)
          _decoded(() => _opt(reassembler.push(_bytes(packet)), _hex)),
      ]);
    },
  for (final c in _list(file, 'setting_edits'))
    c['name']! as String: (check) {
      final kept = readSetting(
        Fields(Unpacker((ArrayWriter()..raw(_bytes(c['setting']))).encode())),
      );
      final edited = kept.withSetting(_setting(c['value']));
      check('bytes', c['bytes'], _hex(edited.bytes!));
    },
  for (final c in _list(file, 'pairing'))
    c['name']! as String: (check) {
      final link = PairingLink.parse(c['link']! as String);
      check('address', c['address'], _opt(link, (l) => _hex(l.home.bytes)));
      check('code', c['code'], link?.code);
      check('request', c['request'], link?.requestMessage);
    },
};

Map<String, _Case> _state(Map<String, Object?> file) {
  final base = _Labels.of(file);
  final defaults = _map(file['defaults']);
  final account = _graph(base.resolve(defaults['graph']));
  return {
    for (final c in _list(file, 'account_states'))
      c['name']! as String: (check) {
        final labels = base.copy();
        final pool = _pool(check, labels, defaults, c);
        Object? fold(Iterable<Uint8List> events) {
          final store = EventStore();
          events.forEach(store.insert);
          return _stateJson(
            AccountState.of(rankOrder(store.eventsIn(account))),
          );
        }

        final state = fold(pool.events.map((e) => e.$2));
        check(
          'state, from the events reversed',
          state,
          fold(pool.events.reversed.map((e) => e.$2)),
        );
        check('state', labels.resolve(c['state']), state);
      },
    for (final c in _list(file, 'live_facts'))
      c['name']! as String: (check) {
        Fact fact(Object? f) {
          final [subject, value] = f! as List;
          return (_subject(subject), _value(value));
        }

        final facts = Facts();
        for (final f in base.resolve(c['before'])! as List) {
          final (subject, value) = fact(f);
          facts.set(subject, value);
        }
        facts.update([
          for (final f in base.resolve(c['update'])! as List) fact(f),
        ]);
        check('after', base.resolve(c['after']), _factsJson(facts));
      },
  };
}

Map<String, _Case> _store(Map<String, Object?> file) {
  final base = _Labels.of(file);
  final defaults = _map(file['defaults']);
  return {
    for (final c in _list(file, 'stores'))
      c['name']! as String: (check) {
        final labels = base.copy();
        final pool = _pool(check, labels, defaults, c);
        final store = EventStore();
        final results = [
          for (final label in c['inserts']! as List)
            for (final bytes in pool.bytes(label as String))
              _decoded(() {
                    store.insert(bytes);
                    return true;
                  }) ==
                  true,
        ];
        check('results', c['results'], results);
        check(
          'graphs',
          labels.resolve(c['graphs']),
          _sorted([
            for (final graph in store.graphs)
              {
                'graph': _hex(graph.bytes),
                'heads': _sorted(_idsJson(store.headsOf(graph))),
                'frontier': _sorted(
                  _idsJson(store.frontier(graph).map((e) => e.$1)),
                ),
                'count': store.countIn(graph),
              },
          ]),
        );
        if (c['display'] case final List graphs) {
          check('display_order', labels.resolve(c['display_order']), [
            for (final graph in labels.resolve(graphs)! as List)
              _idsJson(
                ChatLog(MessageFormats.none)
                    .update(store.eventsIn(_graph(graph)))
                    .map((e) => e.event),
              ),
          ]);
        }
      },
  };
}

/// Up to [limit] ancestors of [before], newest first, of those in [graph],
/// as the home device answers History.
List<Uint8List> _history(
  EventStore home,
  GraphId graph,
  List<EventId> before,
  int limit,
) {
  final queue = SplayTreeSet<(int, EventId)>(
    (a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : b.$2.compareTo(a.$2),
  );
  final seen = <EventId>{};
  void push(EventId id) {
    if (home[id] case final event? when seen.add(id)) {
      queue.add((event.rank, id));
    }
  }

  for (final id in before) {
    home[id]?.parents.forEach(push);
  }
  final found = <EventId>[];
  while (found.length < limit && queue.isNotEmpty) {
    final (_, id) = queue.first;
    queue.remove(queue.first);
    home[id]!.parents.forEach(push);
    found.add(id);
  }
  return [
    for (final id in found)
      if (home[id]!.graph == graph) home.bytes(id)!,
  ];
}

List<SessionMessage> _homeAnswer(EventStore home, SessionMessage message) =>
    switch (message) {
      History(:final graph, :final before, :final limit) => session.batches(
        _history(home, graph, before, min(limit, maxHistory)),
      ),
      _ => session.answer(home, message),
    };

/// Runs a session between a home's store and a replica until neither has
/// anything left to say. False if it doesn't end.
bool _converse(EventStore home, Replica replica, List<SessionMessage> start) {
  var toReplica = start;
  for (var round = 0; round < _maxRounds; round++) {
    if (toReplica.isEmpty) {
      return true;
    }
    final next = <SessionMessage>[];
    for (final message in toReplica) {
      for (final reply in replica.received(message).replies) {
        if (reply case Events(:final events)) {
          for (final bytes in events) {
            _decoded(() => home.insert(bytes));
          }
        } else {
          next.addAll(_homeAnswer(home, reply));
        }
      }
    }
    toReplica = next;
  }
  return false;
}

Map<String, _Case> _session(Map<String, Object?> file) {
  final base = _Labels.of(file);
  final defaults = _map(file['defaults']);
  return {
    for (final c in _list(file, 'answers'))
      // History is for the home to answer, which bTox isn't for other devices.
      if (c['role'] != 'home')
        c['name']! as String: (check) {
          final labels = base.copy();
          final pool = _pool(check, labels, defaults, c);
          final store = pool.store(c['store']);
          final message = c['message'] == 'summary'
              ? session.summary(store)
              : _message(labels.resolve(c['message']));
          check(
            'replies',
            labels.resolve(c['replies']),
            _repliesJson(session.answer(store, message)),
          );
        },
    for (final c in _list(file, 'replicas'))
      c['name']! as String: (check) {
        final labels = base.copy();
        final pool = _pool(check, labels, defaults, c);
        final home = pool.store(c['home_store']);
        final replica = Replica(
          device: _pk(labels.resolve(c['device'])),
          home: _pk(labels.resolve(c['home'])),
        );
        for (final (i, step) in (c['steps']! as List).indexed) {
          final s = _map(step);
          final (action, spec) = s.entries
              .where((e) => !_results.contains(e.key))
              .map((e) => (e.key, e.value))
              .single;
          final what = 'step ${i + 1}, $action';
          switch (action) {
            case 'receive':
              final replies = replica
                  .received(_message(labels.resolve(spec)))
                  .replies;
              check(
                '$what: replies',
                labels.resolve(s['replies']),
                _repliesJson(replies),
              );
            case 'offline':
              replica.offline();
            case 'home_add':
              for (final label in spec! as List) {
                pool.bytes(label as String).forEach(home.insert);
              }
            case 'author':
              final a = _map(labels.resolve(spec));
              final event = replica.author(
                _graph(a['graph']),
                DateTime.fromMillisecondsSinceEpoch(a['time']! as int),
                _content(a['content']),
              );
              final push = replica.written(event);
              labels.addEvent(a['label']! as String, event.$3);
              for (final message in push) {
                if (message case Events(:final events)) {
                  events.forEach(home.insert);
                }
              }
              check(
                '$what: event',
                labels.resolve(s['event']),
                _eventJson(event.$2),
              );
              check(
                '$what: push',
                labels.resolve(s['push']),
                _repliesJson(push),
              );
            case 'converse':
              final start = spec == 'session'
                  ? [Replica.hello, session.summary(home)]
                  : [
                      for (final m in labels.resolve(spec)! as List)
                        _message(m),
                    ];
              if (!_converse(home, replica, start)) {
                check.failures.add('$what: the session never ends');
              }
              check(
                '$what: replica',
                labels.resolve(s['replica']),
                _countsJson(replica.store),
              );
              check(
                '$what: home',
                labels.resolve(s['home']),
                _countsJson(home),
              );
            default:
              throw ArgumentError('Not a step: $action');
          }
        }
      },
  };
}

const _results = {'replies', 'event', 'push', 'replica', 'home'};
