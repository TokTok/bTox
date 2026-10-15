import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/messages/message_format.dart';
import 'package:btox/models/chat_merge.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:flutter_test/flutter_test.dart';

PublicKey _key(int i) => PublicKey(Uint8List(32)..fillRange(0, 32, i));

final _home = _key(1);
final _groupBot = _key(2);
final _conferenceBot = _key(3);
final _group = GroupChat(GroupChatId(Uint8List(32)..[0] = 1));
final _conference = ConferenceChat(ConferenceId(Uint8List(32)..[0] = 2));
final _merge = ChatMerge([
  MergeSide(graph: _group.graph, bots: {_groupBot}),
  MergeSide(graph: _conference.graph, bots: {_conferenceBot}),
]);

typedef _Events = List<(EventId, SyncEvent)>;

void _add(_Events events, ChatId chat, int time, EventContent content) {
  final event = SyncEvent(
    graph: chat.graph,
    author: _home,
    parents: [?events.lastOrNull?.$1],
    rank: events.length,
    time: time,
    content: content,
  );
  events.add((EventId.of(event.encode()), event));
}

Received _from(PublicKey from, String sender, String text) => Received(
  from: from,
  sender: sender,
  message: utf8.encode(text),
  kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
);

List<(String?, String)> _shown(_Events group, _Events conference) =>
    _said(MergedLog(MessageFormats.none).update(_merge, [group, conference]));

List<(String?, String)> _said(List<MergedEntry> entries) => [
  for (final (:entry, graph: _, rank: _) in entries)
    (entry.sender, (entry.content as TextContent).text),
];

void main() {
  test('names may hold "> "', () {
    final group = <(EventId, SyncEvent)>[];
    final conference = <(EventId, SyncEvent)>[];
    _add(group, _group, 1000, _from(_key(4), '>_> bob', 'hi'));
    _add(
      conference,
      _conference,
      1200,
      _from(_conferenceBot, '!', '<>_> bob> hi'),
    );
    expect(_shown(group, conference), [('>_> bob', 'hi')]);
    expect(relayed('<Bob> a> b'), ('Bob', 'a> b'));
    expect(relayed('<> x'), isNull);
  });

  test('a message and its relayed copy show once, as the message', () {
    final group = <(EventId, SyncEvent)>[];
    final conference = <(EventId, SyncEvent)>[];
    final bob = _key(4);
    final carol = _key(5);
    _add(group, _group, 1000, _from(bob, 'Bob', 'hi'));
    _add(conference, _conference, 1200, _from(_conferenceBot, '!', '<Bob> hi'));
    // Carol's copy from the bot comes before her own.
    _add(group, _group, 2000, _from(_groupBot, '!', '<Carol> yo'));
    _add(conference, _conference, 2100, _from(carol, 'Carol', 'yo'));
    // Ours, relayed back to us.
    _add(
      group,
      _group,
      3000,
      Send(
        sender: 'iphy',
        message: utf8.encode('hey'),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      ),
    );
    _add(
      conference,
      _conference,
      3100,
      _from(_conferenceBot, '!', '<iphy> hey'),
    );
    // Ours again, its copy seeming to come first as clocks differ.
    _add(
      conference,
      _conference,
      3500,
      _from(_conferenceBot, '!', '<iphy> ho'),
    );
    _add(
      group,
      _group,
      3600,
      Send(
        sender: 'iphy',
        message: utf8.encode('ho'),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      ),
    );
    // Bob saying it again is another message, with its own copy.
    _add(group, _group, 4000, _from(bob, 'Bob', 'hi'));
    _add(conference, _conference, 4100, _from(_conferenceBot, '!', '<Bob> hi'));
    // Only in the conference, from someone the group doesn't have.
    _add(
      conference,
      _conference,
      5000,
      _from(_conferenceBot, '!', '<Dan> bye'),
    );
    // What the bot says itself.
    _add(group, _group, 6000, _from(_groupBot, '!', 'Usage: !help'));

    final shown = _shown(group, conference);
    expect(shown, [
      ('Bob', 'hi'),
      ('Carol', 'yo'),
      (null, 'hey'),
      (null, 'ho'),
      ('Bob', 'hi'),
      ('Dan', 'bye'),
      ('!', 'Usage: !help'),
    ]);

    // The same when they come one at a time, as they were said or not.
    final said = [...group, ...conference]
      ..sort((a, b) => a.$2.time.compareTo(b.$2.time));
    for (final order in [said, said.reversed]) {
      final log = MergedLog(MessageFormats.none);
      final (inGroup, inConference) = (
        <(EventId, SyncEvent)>[],
        <(EventId, SyncEvent)>[],
      );
      var merged = const <MergedEntry>[];
      for (final event in order) {
        (event.$2.graph == _group.graph ? inGroup : inConference).add(event);
        merged = log.update(_merge, [
          [...inGroup],
          [...inConference],
        ]);
      }
      expect(_said(merged), shown);
    }
  });

  test('a message written offline matches its copy by when it was sent', () {
    final group = <(EventId, SyncEvent)>[];
    final conference = <(EventId, SyncEvent)>[];
    _add(
      group,
      _group,
      1000,
      Send(
        sender: 'iphy',
        message: utf8.encode('split?'),
        kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      ),
    );
    _add(group, _group, 200000, Sent(intent: group.first.$1));
    _add(
      conference,
      _conference,
      200100,
      _from(_conferenceBot, '!', '<iphy> split?'),
    );

    expect(_shown(group, conference), [(null, 'split?')]);

    final log = MergedLog(MessageFormats.none);
    log.update(_merge, [group.sublist(0, 1), const []]);
    log.update(_merge, [group, const []]);
    expect(_said(log.update(_merge, [group, conference])), [(null, 'split?')]);
  });

  test('chats merge into a joined chat that is not merged itself', () {
    AccountMerge into(ChatId chat) =>
        AccountMerge(bot: _conferenceBot, into: chat, intoBot: _groupBot);
    final account = AccountState(
      chats: {_group: const AccountChat(joined: true)},
      merges: {_conference: into(_group)},
      facts: Facts(),
    );
    expect(mergedChats(account), {_group.graph: _merge});
    expect(mergedChats(account.copyWith(chats: const {})), isEmpty);
    expect(
      mergedChats(
        account.copyWith(
          merges: {...account.merges, _group: into(_conference)},
        ),
      ),
      isEmpty,
    );
  });

  test('a chat with a relay bot shows as one of its own, unless merged', () {
    final account = AccountState(
      chats: {_group: const AccountChat(joined: true)},
      relayBots: {_group: _groupBot},
      facts: Facts(),
    );
    expect(mergedChats(account), {
      _group.graph: ChatMerge([
        MergeSide(graph: _group.graph, bots: {_groupBot}),
      ]),
    });
    expect(
      mergedChats(
        account.copyWith(
          merges: {
            _conference: AccountMerge(
              bot: _conferenceBot,
              into: _group,
              intoBot: _groupBot,
            ),
          },
        ),
      ),
      {_group.graph: _merge},
    );
  });

  test('relayed names show by when they last spoke', () {
    final group = <(EventId, SyncEvent)>[];
    _add(group, _group, 1000, _from(_groupBot, 'EPiG', '<Bob> hi'));
    _add(group, _group, 2000, _from(_groupBot, 'EPiG', '<Carol> yo'));
    _add(group, _group, 3000, _from(_groupBot, 'EPiG-BrDG', '<Bob> again'));
    _add(group, _group, 4000, _from(_groupBot, 'EPiG-BrDG', 'not relayed'));
    _add(group, _group, 5000, _from(_key(4), 'Dave', '<Eve> quoted'));
    final relayed = relayedNames(group, _groupBot)!;
    expect((relayed.bot, relayed.name), (_groupBot, 'EPiG-BrDG'));
    expect(relayed.seen, [
      (name: 'Bob', last: DateTime.fromMillisecondsSinceEpoch(3000)),
      (name: 'Carol', last: DateTime.fromMillisecondsSinceEpoch(2000)),
    ]);
    expect(relayedNames(group, _conferenceBot), isNull);
  });
}
