import 'dart:async';

import 'package:btox/db/database.dart';
import 'package:btox/models/chat_details.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/drafts.dart';
import 'package:btox/providers/message_formats.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/setting.dart';
import 'package:clock/clock.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chats.g.dart';

@riverpod
Stream<List<(EventId, SyncEvent)>> _syncEvents(
  Ref ref,
  Id<Profiles> id,
  GraphId graph,
) => watchDb(ref, (db) => db.watchSyncEvents(id, graph));

@riverpod
Stream<Map<GraphId, ChatEntry>> _latestEntries(Ref ref, Id<Profiles> id) {
  final formats = ref.watch(messageFormatsProvider(id));
  return watchDb(ref, (db) => db.watchLatestEntries(id, formats));
}

@riverpod
Stream<Map<GraphId, List<int>>> _receivedRanks(Ref ref, Id<Profiles> id) {
  final formats = ref.watch(messageFormatsProvider(id));
  return watchDb(ref, (db) => db.watchReceivedRanks(id, formats));
}

/// The newest event of each conversation a chat shows, which showing the
/// chat reads up to.
@riverpod
Map<GraphId, (int, EventId)> newestEvents(Ref ref, ChatRef chat) {
  final newest = <GraphId, (int, EventId)>{};
  for (final (id, event)
      in ref.watch(_syncEventsProvider(chat.profile, chat.graph)).value ??
          const <(EventId, SyncEvent)>[]) {
    if (isAfter((event.rank, id), newest[chat.graph])) {
      newest[chat.graph] = (event.rank, id);
    }
  }
  return newest;
}

bool isOnline(Facts live, PublicKey pk) =>
    live.find(
      Subject.friend(pk),
      (v) => v is ConnectionValue ? v.connection != Connection.none : null,
    ) ??
    false;

/// What Tox says now, as long as it runs.
@riverpod
Stream<Facts> liveFacts(Ref ref, Id<Profiles> id) =>
    watchDb(ref, (db) => db.watchLiveFacts(id));

@riverpod
Stream<Map<EventId, Transfer>> _transfers(Ref ref, Id<Profiles> id) =>
    watchDb(ref, (db) => db.watchTransfers(id)).map(
      (transfers) => {
        for (final transfer in transfers) ?transfer.event: transfer,
      },
    );

/// The account of a profile, which this device runs.
@riverpod
AsyncValue<AccountState> account(Ref ref, Id<Profiles> id) {
  final key = ref.watch(
    profilesProvider.select(
      (profiles) =>
          profiles.value?.where((p) => p.id == id).firstOrNull?.publicKey,
    ),
  );
  if (key == null) {
    return const AsyncLoading();
  }
  return ref.watch(_accountStateProvider(id, GraphId.account(key)));
}

/// What the account [graph] says, added to as its events come.
@riverpod
Stream<AccountState> _accountState(Ref ref, Id<Profiles> id, GraphId graph) {
  final fold = AccountFold();
  return watchDb(ref, (db) => db.watchSyncEvents(id, graph)).map(fold.update);
}

@riverpod
Map<PublicKey, String> friendRequests(Ref ref, Id<Profiles> id) => {
  for (final MapEntry(key: pk, value: friend)
      in ref.watch(accountProvider(id)).value?.friends.entries ??
          const <MapEntry<PublicKey, AccountFriend>>[])
    if (friend.request case final request? when !friend.wanted) pk: request,
};

@riverpod
AsyncValue<List<ChatSummary>> chatsForProfile(Ref ref, Id<Profiles> id) {
  final profile = ref.watch(profileProvider(id)).value;
  if (profile == null) {
    return const AsyncLoading();
  }
  final live = ref.watch(liveFactsProvider(id)).value ?? Facts();
  final received = ref.watch(_receivedRanksProvider(id)).value ?? {};
  final latest = ref.watch(_latestEntriesProvider(id)).value ?? {};
  final drafts = ref.watch(draftsProvider(id)).value ?? {};
  final account = ref.watch(accountProvider(id));
  final now = ref.watch(_muteClockProvider(id));
  return account.whenData(
    (account) => _chats(
      id,
      profile.publicKey,
      account,
      live,
      received,
      latest,
      drafts,
      now,
    ),
  );
}

/// Now, as the mutes of [id]'s chats see it, again when the next one ends.
@riverpod
DateTime _muteClock(Ref ref, Id<Profiles> id) {
  final now = clock.now();
  DateTime? next;
  for (final Mute(:until)
      in ref
              .watch(accountProvider(id))
              .value
              ?.settings
              .values
              .expand((settings) => settings.values)
              .map((kept) => kept.value)
              .whereType<Mute>() ??
          const <Mute>[]) {
    if (until != null &&
        until.isAfter(now) &&
        (next == null || until.isBefore(next))) {
      next = until;
    }
  }
  if (next != null) {
    final timer = Timer(next.difference(now), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return now;
}

/// A chat, also one no longer in the list, as a deleted friend's.
@riverpod
AsyncValue<ChatSummary> chat(Ref ref, ChatRef chat) => ref
    .watch(chatsForProfileProvider(chat.profile))
    .whenData(
      (chats) => chats.firstWhere(
        (c) => c.ref == chat,
        orElse: () => ChatSummary(ref: chat, key: chat.graph, closed: true),
      ),
    );

@riverpod
AsyncValue<ChatDetails> chatDetails(Ref ref, ChatRef chat) {
  final live = ref.watch(liveFactsProvider(chat.profile)).value;
  final account = ref.watch(accountProvider(chat.profile));
  final self = ref.watch(
    profilesProvider.select(
      (profiles) => profiles.value
          ?.where((p) => p.id == chat.profile)
          .firstOrNull
          ?.publicKey,
    ),
  );
  if (self == null) {
    return const AsyncLoading();
  }
  return ref
      .watch(chatProvider(chat))
      .whenData(
        (summary) => ChatDetails.of(
          summary,
          self,
          account.value ?? AccountState.of(const []),
          live,
        ),
      );
}

@riverpod
AsyncValue<List<ChatEntry>> chatEntries(Ref ref, ChatRef chat) {
  final transfers = ref.watch(_transfersProvider(chat.profile)).value;
  return ref
      .watch(_eventEntriesProvider(chat))
      .whenData(
        (entries) => [
          for (final entry in entries)
            switch ((entry.content, transfers?[entry.event])) {
              (final FileContent content, final transfer?) => entry.copyWith(
                content: content.copyWith(path: transfer.path),
                file: FileProgress(
                  state: transfer.state,
                  transferred: transfer.transferred,
                  transfer: transfer.id,
                ),
              ),
              _ => entry,
            },
        ],
      );
}

// One per chat, so its entries are added to as its events come.
@riverpod
ChatLog _chatLog(Ref ref, ChatRef chat) =>
    ChatLog(ref.watch(messageFormatsProvider(chat.profile)));

@riverpod
AsyncValue<List<ChatEntry>> _eventEntries(Ref ref, ChatRef chat) {
  final log = ref.watch(_chatLogProvider(chat));
  return ref
      .watch(_syncEventsProvider(chat.profile, chat.graph))
      .whenData(log.update);
}

List<ChatSummary> _chats(
  Id<Profiles> profile,
  PublicKey home,
  AccountState account,
  Facts live,
  Map<GraphId, List<int>> received,
  Map<GraphId, ChatEntry> latest,
  Map<GraphId, StoredDraft> drafts,
  DateTime now,
) {
  int unread(GraphId graph) => (received[graph] ?? const [])
      .where((rank) => rank > (account.read[graph]?.$1 ?? -1))
      .length;
  Mute? muteOf(GraphId graph) =>
      switch (account.setting<Mute>(Scope.conversation(graph))) {
        final mute? when mute.holdsAt(now) => mute,
        _ => null,
      };
  Content? draft(GraphId graph) => switch (drafts[graph]) {
    StoredDraft(:final message) when message.trim().isNotEmpty => TextContent(
      text: message,
    ),
    final draft? => draft.attachments.firstOrNull,
    null => null,
  };

  final chats = [
    for (final MapEntry(key: pk, value: friend) in account.friends.entries)
      if (friend.wanted)
        ChatSummary(
          ref: ChatRef(profile, GraphId.friend(home, pk)),
          name: friend.name,
          key: pk,
          online: isOnline(live, pk),
          unread: unread(GraphId.friend(home, pk)),
          mute: muteOf(GraphId.friend(home, pk)),
          last: latest[GraphId.friend(home, pk)],
          draft: draft(GraphId.friend(home, pk)),
        ),
    for (final MapEntry(key: chat, value: info) in account.chats.entries)
      if (info.joined)
        ChatSummary(
          ref: ChatRef(profile, chat.graph),
          name: info.name,
          key: chat.id,
          unread: unread(chat.graph),
          mute: muteOf(chat.graph),
          last: latest[chat.graph],
          draft: draft(chat.graph),
        ),
  ];
  return chats..sort(
    (a, b) => switch ((a.last?.timestamp, b.last?.timestamp)) {
      (final x?, final y?) => y.compareTo(x),
      (_?, null) => -1,
      (null, _?) => 1,
      (null, null) => (a.name ?? '').compareTo(b.name ?? ''),
    },
  );
}
