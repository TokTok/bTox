import 'dart:async';

import 'package:btox/db/database.dart';
import 'package:btox/messages/message_format.dart';
import 'package:btox/models/chat_details.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_merge.dart';
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
  for (final graph in _graphsOf(ref, chat)) {
    for (final (id, event)
        in ref.watch(_syncEventsProvider(chat.profile, graph)).value ??
            const <(EventId, SyncEvent)>[]) {
      if (isAfter((event.rank, id), newest[graph])) {
        newest[graph] = (event.rank, id);
      }
    }
  }
  return newest;
}

/// The chats [chat] shows with, itself first, where it's merged.
@riverpod
ChatMerge? chatMerge(Ref ref, ChatRef chat) => ref.watch(
  accountProvider(chat.profile).select(
    (account) => switch (account.value) {
      final account? => mergedChats(account)[chat.graph],
      null => null,
    },
  ),
);

@riverpod
PictureEncoding pictureFormat(Ref ref, ChatRef chat) => ref.watch(
  accountProvider(chat.profile).select(
    (account) =>
        account.value
            ?.setting<PictureFormat>(Scope.conversation(chat.graph))
            ?.format ??
        PictureEncoding.original,
  ),
);

typedef ChatSender = ({
  PublicKey key,
  String name,
  int messages,
  // Of them, those that look like a bot relayed them.
  int relayed,
});

/// Who has written in a group chat, by their last name, those whose
/// messages look relayed first.
@riverpod
List<ChatSender> chatSenders(Ref ref, ChatRef chat) {
  final senders = <PublicKey, ChatSender>{};
  for (final (_, event)
      in ref.watch(_syncEventsProvider(chat.profile, chat.graph)).value ??
          const <(EventId, SyncEvent)>[]) {
    if (event.content case Received(
      from: final from?,
      :final sender,
      :final message,
    )) {
      final known = senders[from];
      senders[from] = (
        key: from,
        name: sender,
        messages: (known?.messages ?? 0) + 1,
        relayed:
            (known?.relayed ?? 0) +
            (relayed(plainText(message)) == null ? 0 : 1),
      );
    }
  }
  return senders.values.toList()..sort(
    (a, b) => a.relayed != b.relayed
        ? b.relayed.compareTo(a.relayed)
        : b.messages.compareTo(a.messages),
  );
}

List<GraphId> _graphsOf(Ref ref, ChatRef chat) => [
  for (final side
      in ref.watch(chatMergeProvider(chat))?.sides ??
          [MergeSide(graph: chat.graph, bots: const {})])
    side.graph,
];

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

/// The account of a profile: a linked one's, or the one this device runs.
@riverpod
AsyncValue<AccountState> account(Ref ref, Id<Profiles> id) {
  final key = ref.watch(
    profilesProvider.select((profiles) {
      final profile = profiles.value?.where((p) => p.id == id).firstOrNull;
      return profile == null ? null : _accountKey(profile);
    }),
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

PublicKey _accountKey(Profile profile) =>
    profile.home?.publicKey ?? profile.publicKey;

/// A linked account's name as last synced, read once.
Future<String?> linkedAccountName(Database db, Profile profile) async {
  final home = profile.home;
  if (home == null) {
    return null;
  }
  final events = await db
      .watchSyncEvents(profile.id, GraphId.account(home.publicKey))
      .first;
  return AccountState.of(events).name;
}

typedef ProfileIdentity = ({
  String? name,
  String statusMessage,
  ToxAddress address,
});

/// A linked profile shows its account's identity, not this device's key.
@riverpod
ProfileIdentity profileIdentity(Ref ref, Profile profile) {
  if (profile.home case final home?) {
    final account = ref.watch(accountProvider(profile.id)).value;
    return (
      name: account?.name,
      statusMessage: account?.statusMessage ?? '',
      address: home,
    );
  }
  return (
    name: profile.settings.nickname,
    statusMessage: profile.settings.statusMessage,
    address: ToxAddress.of(profile.publicKey, profile.nospam),
  );
}

@riverpod
Map<PublicKey, String> friendRequests(Ref ref, Id<Profiles> id) => {
  for (final MapEntry(key: pk, value: friend)
      in ref.watch(accountProvider(id)).value?.friends.entries ??
          const <MapEntry<PublicKey, AccountFriend>>[])
    if (friend.request case final request? when !friend.wanted) pk: request,
};

@riverpod
List<(EventId, AccountInvite)> chatInvites(Ref ref, Id<Profiles> id) => [
  for (final MapEntry(key: event, value: invite)
      in ref.watch(accountProvider(id)).value?.invites.entries ??
          const <MapEntry<EventId, AccountInvite>>[])
    if (invite.status
        case InviteStatus.pending ||
            InviteStatus.joining ||
            InviteStatus.failed)
      (event, invite),
];

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
  final merges = mergedChats(account.value ?? AccountState.of(const []));
  final merged = {
    for (final graph in merges.keys)
      graph: ?ref.watch(_mergedEntriesProvider(ChatRef(id, graph))).value,
  };
  return account.whenData(
    (account) => _chats(
      id,
      _accountKey(profile),
      profile.publicKey,
      account,
      live,
      received,
      latest,
      drafts,
      merges,
      merged,
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
          .map(_accountKey)
          .firstOrNull,
    ),
  );
  if (self == null) {
    return const AsyncLoading();
  }
  // Only a chat with a relay bot, merged with none, has one side.
  final relayed = switch (ref.watch(chatMergeProvider(chat))?.sides) {
    [MergeSide(:final bots)] => relayedNames(
      ref.watch(_syncEventsProvider(chat.profile, chat.graph)).value ??
          const [],
      bots.single,
    ),
    _ => null,
  };
  return ref
      .watch(chatProvider(chat))
      .whenData(
        (summary) => ChatDetails.of(
          summary,
          self,
          account.value ?? AccountState.of(const []),
          live,
          relayed: relayed,
        ),
      );
}

@riverpod
AsyncValue<List<ChatEntry>> chatEntries(Ref ref, ChatRef chat) {
  final transfers = ref.watch(_transfersProvider(chat.profile)).value;
  final linked = ref.watch(
    profileProvider(chat.profile).select((p) => p.value?.home != null),
  );
  return ref
      .watch(_eventEntriesProvider(chat))
      .whenData(
        (entries) => [
          for (final entry in entries)
            switch ((entry.content, transfers?[entry.event])) {
              (final FileContent content, final transfer?) => entry.copyWith(
                content: content.copyWith(path: transfer.path),
                file: linked
                    ? _linkedProgress(entry.file, transfer)
                    : FileProgress(
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

/// How far a linked account's file got: the home device's progress, with
/// this device's transfer to or from the home on top.
FileProgress _linkedProgress(FileProgress? home, Transfer here) => switch ((
  home?.state,
  here,
)) {
  (FileState.done || FileState.cancelled, Transfer(incoming: false)) => home!,
  (_, Transfer(incoming: false, state: FileState.cancelled)) =>
    const FileProgress(state: FileState.cancelled),
  // Ours on its way to the home device, then the home's to send on,
  // which it doesn't show.
  (_, Transfer(incoming: false, :final state, :final transferred)) =>
    FileProgress(
      state: FileState.active,
      transferred: state == FileState.active ? transferred : null,
    ),
  (
    FileState.done,
    Transfer(incoming: true, :final state, :final transferred),
  ) =>
    home!.copyWith(state: state, transferred: transferred),
  _ => home ?? const FileProgress(),
};

// One per chat, so its entries are added to as its events come.
@riverpod
ChatLog _chatLog(Ref ref, ChatRef chat) =>
    ChatLog(ref.watch(messageFormatsProvider(chat.profile)));

@riverpod
AsyncValue<List<ChatEntry>> _eventEntries(Ref ref, ChatRef chat) {
  if (ref.watch(chatMergeProvider(chat)) != null) {
    return ref
        .watch(_mergedEntriesProvider(chat))
        .whenData((entries) => [for (final e in entries) e.entry]);
  }
  final log = ref.watch(_chatLogProvider(chat));
  return ref
      .watch(_syncEventsProvider(chat.profile, chat.graph))
      .whenData(log.update);
}

// One per merged chat, so each of its chats' entries are added to as their
// events come.
@riverpod
MergedLog _mergedLog(Ref ref, ChatRef chat) =>
    MergedLog(ref.watch(messageFormatsProvider(chat.profile)));

@riverpod
AsyncValue<List<MergedEntry>> _mergedEntries(Ref ref, ChatRef chat) {
  final merge = ref.watch(chatMergeProvider(chat));
  if (merge == null) {
    return const AsyncData([]);
  }
  final log = ref.watch(_mergedLogProvider(chat));
  final events = <List<(EventId, SyncEvent)>>[];
  for (final side in merge.sides) {
    switch (ref.watch(_syncEventsProvider(chat.profile, side.graph))) {
      case AsyncData(:final value):
        events.add(value);
      case AsyncError(:final error, :final stackTrace):
        return AsyncError(error, stackTrace);
      case AsyncLoading():
        return const AsyncLoading();
    }
  }
  return AsyncData(log.update(merge, events));
}

List<ChatSummary> _chats(
  Id<Profiles> profile,
  PublicKey home,
  PublicKey device,
  AccountState account,
  Facts live,
  Map<GraphId, List<int>> received,
  Map<GraphId, ChatEntry> latest,
  Map<GraphId, StoredDraft> drafts,
  Map<GraphId, ChatMerge> merges,
  Map<GraphId, List<MergedEntry>> merged,
  DateTime now,
) {
  int unread(GraphId graph) => switch (merged[graph]) {
    final entries? => unreadIn(entries, account.read),
    null =>
      (received[graph] ?? const [])
          .where((rank) => rank > (account.read[graph]?.$1 ?? -1))
          .length,
  };
  Mute? muteOf(GraphId graph) =>
      switch (account.setting<Mute>(Scope.conversation(graph))) {
        final mute? when mute.holdsAt(now) => mute,
        _ => null,
      };
  ChatEntry? last(GraphId graph) =>
      merged[graph]?.lastOrNull?.entry ?? latest[graph];
  Content? draft(GraphId graph) => switch (drafts[graph]) {
    StoredDraft(:final message) when message.trim().isNotEmpty => TextContent(
      text: message,
    ),
    final draft? => draft.attachments.firstOrNull,
    null => null,
  };
  // Shown with the chats they're merged into.
  final hidden = {
    for (final merge in merges.values)
      for (final side in merge.sides.skip(1)) side.graph,
  };

  final chats = [
    for (final MapEntry(key: pk, value: friend) in account.friends.entries)
      // This device is one of the home device's friends.
      if (friend.wanted && pk != device)
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
      if (info.joined && !hidden.contains(chat.graph))
        ChatSummary(
          ref: ChatRef(profile, chat.graph),
          name: info.name,
          key: chat.id,
          unread: unread(chat.graph),
          mute: muteOf(chat.graph),
          last: last(chat.graph),
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
