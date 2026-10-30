import 'dart:async';
import 'dart:convert';

import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/messages/message_format.dart';
import 'package:btox/messages/split_message.dart';
import 'package:btox/models/app_defaults.dart';
import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/store.dart';
import 'package:drift/drift.dart';

export 'package:drift/drift.dart' show Value;

part 'database.drift.dart';

// Within SQLite's limit on variables in one statement.
const _idsPerStatement = 500;

@DriftDatabase(
  tables: [
    AppSettings,
    CachedBootstrapNodes,
    ChatDrafts,
    DeletedChats,
    Intents,
    LinkedNotified,
    LiveFacts,
    ChatReads,
    Profiles,
    SyncEvents,
    Transfers,
  ],
)
final class Database extends _$Database {
  Database(super.e);

  // Bump with every schema change, then run `tools/prepare`.
  @override
  int get schemaVersion => 1;

  // Events never change, so each is decoded once.
  final _decoded = <EventId, SyncEvent?>{};
  // Each chat's latest events of one rank, with how many events it had, and
  // the one it showed last: the same while it has no others.
  final _lastOfTied = <GraphId, (Set<EventId>, int, EventId)>{};

  Future<Id<Profiles>> addProfile(ProfilesCompanion entry) async =>
      Id(await into(profiles).insert(entry));

  Future<void> cacheBootstrapNodes(BootstrapNodeList nodes) async {
    await into(cachedBootstrapNodes).insertOnConflictUpdate(
      CachedBootstrapNodesCompanion.insert(
        id: const Value(0),
        json: jsonEncode(nodes.toJson()),
      ),
    );
  }

  /// Returns the paths of the profile's files, for the caller to delete.
  Future<List<String>> deleteProfile(Id<Profiles> id) => transaction(() async {
    // What belongs to the profile goes first, as it refers to the profile.
    final files = await _deleteWhere({'profile_id': Variable<int>(id.value)});
    await (delete(profiles)..where((p) => p.id.equals(id.value))).go();
    return files;
  });

  /// Deletes the rows with these [values] from every table that has their
  /// columns, apart from the [kept] ones, and returns the paths of the files
  /// whose transfers or drafts went.
  Future<List<String>> _deleteWhere(
    Map<String, Variable> values, {
    Set<TableInfo> kept = const {},
  }) async {
    final where = values.keys.map((column) => '$column = ?').join(' AND ');
    final files = [
      for (final row in await customSelect(
        'SELECT path FROM "${transfers.actualTableName}" WHERE $where',
        variables: [...values.values],
        readsFrom: {transfers},
      ).get())
        row.read<String>('path'),
      for (final row in await customSelect(
        'SELECT attachments FROM "${chatDrafts.actualTableName}" '
        'WHERE $where',
        variables: [...values.values],
        readsFrom: {chatDrafts},
      ).get())
        for (final content in const ContentListConverter().fromSql(
          row.read<String>('attachments'),
        ))
          if (content case FileContent(:final path)) path,
    ];
    for (final table in allTables) {
      if (!kept.contains(table) &&
          values.keys.every(table.columnsByName.containsKey)) {
        await customUpdate(
          'DELETE FROM "${table.actualTableName}" WHERE $where',
          variables: [...values.values],
          updates: {table},
          updateKind: UpdateKind.delete,
        );
      }
    }
    return files;
  }

  Future<void> addSyncEvents(
    Id<Profiles> profileId,
    Iterable<NewEvent> events,
  ) => batch((batch) {
    batch.insertAll(syncEvents, [
      for (final (id, event, bytes) in events)
        SyncEventsCompanion.insert(
          profileId: profileId,
          id: id,
          graph: event.graph,
          rank: event.rank,
          received: isIncoming(event.content),
          shown: Value(entryOf(id, event, MessageFormats.none) != null),
          bytes: bytes,
        ),
    ], mode: InsertMode.insertOrIgnore);
  });

  /// The latest entry of each chat, as the chat shows it.
  Stream<Map<GraphId, ChatEntry>> watchLatestEntries(
    Id<Profiles> profileId,
    MessageFormats formats,
  ) =>
      customSelect(
        'SELECT e.id, e.bytes FROM sync_events e JOIN ('
        'SELECT graph, MAX(rank) AS rank FROM sync_events '
        'WHERE profile_id = ?1 AND shown GROUP BY graph'
        ') latest ON e.graph = latest.graph AND e.rank = latest.rank '
        'WHERE e.profile_id = ?1 AND e.shown',
        variables: [Variable<int>(profileId.value)],
        readsFrom: {syncEvents},
      ).watch().asyncMap((rows) async {
        final candidates = <GraphId, Map<EventId, ChatEntry>>{};
        for (final row in rows) {
          final id = EventId.fromJson(row.read<String>('id'));
          final event = _decoded[id] ??= _readable(
            row.read<Uint8List>('bytes'),
          );
          if (event case final event?) {
            if (entryOf(id, event, formats) case final entry?) {
              (candidates[event.graph] ??= {})[id] = entry;
            }
          }
        }
        final latest = <GraphId, (EventId, ChatEntry)>{};
        for (final MapEntry(key: graph, value: entries) in candidates.entries) {
          var last = entries.keys.last;
          if (entries.length > 1) {
            final ids = entries.keys.toSet();
            final count = await _countIn(profileId, graph);
            last = switch (_lastOfTied[graph]) {
              (final tied, final events, final known)
                  when events == count &&
                      tied.length == ids.length &&
                      tied.containsAll(ids) =>
                known,
              // Of events of the same rank, the one the chat shows last: it
              // also orders them by when they came after their parents.
              _ =>
                ChatLog(formats)
                    .update(await _syncEventsIn(profileId, graph))
                    .map((e) => e.event)
                    .lastWhere(entries.containsKey, orElse: () => last),
            };
            _lastOfTied[graph] = (ids, count, last);
          }
          latest[graph] = (last, entries[last]!);
        }
        return {
          for (final MapEntry(:key, value: (id, entry)) in latest.entries)
            key: switch (entry.content) {
              CallContent(ended: false) => await _callAsEnded(
                profileId,
                key,
                id,
                entry,
              ),
              _ => entry,
            },
        };
      });

  /// If it has ended: its end isn't an entry, so it's later than the latest.
  Future<ChatEntry> _callAsEnded(
    Id<Profiles> profileId,
    GraphId graph,
    EventId call,
    ChatEntry entry,
  ) async {
    final rows = await customSelect(
      'SELECT id, bytes FROM sync_events WHERE profile_id = ? AND graph = ? '
      'AND rank > ? AND NOT shown',
      variables: [
        Variable<int>(profileId.value),
        Variable(graph.toJson()),
        Variable<int>(_decoded[call]?.rank ?? 0),
      ],
      readsFrom: {syncEvents},
    ).get();
    for (final row in rows) {
      final id = EventId.fromJson(row.read<String>('id'));
      final event = _decoded[id] ??= _readable(row.read<Uint8List>('bytes'));
      if (event?.content case final CallEnded end when end.call == call) {
        return endedAs(entry, end);
      }
    }
    return entry;
  }

  Future<BootstrapNodeList?> getCachedBootstrapNodes() async {
    final row = await select(cachedBootstrapNodes).getSingleOrNull();
    return row == null
        ? null
        : BootstrapNodeList.fromJson(jsonDecode(row.json));
  }

  /// Signs the profile in and shows it.
  Future<void> signIn(Id<Profiles> id) => transaction(() async {
    await (update(profiles)..where((p) => p.id.equals(id.value))).write(
      ProfilesCompanion(signedIn: Value(true)),
    );
    await updateAppSettings(AppSettingsCompanion(currentProfile: Value(id)));
  });

  Future<void> signOut(Id<Profiles> id) async {
    await (update(profiles)..where((p) => p.id.equals(id.value))).write(
      ProfilesCompanion(signedIn: Value(false)),
    );
  }

  Future<void> updateAppSettings(AppSettingsCompanion settings) async {
    await into(appSettings).insert(
      settings.copyWith(id: const Value(0)),
      onConflict: DoUpdate((_) => settings),
    );
  }

  /// Changes the settings as they are now, so quick changes don't undo
  /// each other.
  Future<void> updateProfileSettings(
    Id<Profiles> id,
    ProfileSettings Function(ProfileSettings) change,
  ) => transaction(() async {
    final row = profiles.id.equals(id.value);
    final current = await (select(profiles)..where((_) => row)).getSingle();
    await (update(profiles)..where((_) => row)).write(
      ProfilesCompanion(settings: Value(change(current.settings))),
    );
  });

  Future<List<Uint8List>> getSyncEvents(Id<Profiles> profileId) async =>
      (selectOnly(syncEvents)
            ..addColumns([syncEvents.bytes])
            ..where(syncEvents.profileId.equals(profileId.value)))
          .map((row) => row.read(syncEvents.bytes)!)
          .get();

  /// Forgets events this version can't read, which then sync again in a form
  /// it can, and the read positions that name them.
  Future<void> dropSyncEvents(
    Id<Profiles> profileId,
    List<EventId> ids,
  ) => transaction(() async {
    for (var i = 0; i < ids.length; i += _idsPerStatement) {
      final batch = ids.skip(i).take(_idsPerStatement);
      await (delete(syncEvents)..where(
            (e) => e.profileId.equals(profileId.value) & e.id.isInValues(batch),
          ))
          .go();
      await (delete(chatReads)..where(
            (r) =>
                r.profileId.equals(profileId.value) & r.event.isInValues(batch),
          ))
          .go();
    }
  });

  /// Sends [message], as several where it's longer than an event takes.
  Future<void> addSend(Id<Profiles> profileId, GraphId graph, String message) =>
      batch(
        (batch) => batch.insertAll(intents, [
          for (final part in splitMessage(utf8.encode(message), maxSendBytes))
            IntentsCompanion.insert(
              profileId: profileId,
              graph: Value(graph),
              // The background service knows our name in the chat.
              content: Send(
                sender: '',
                message: part,
                kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
              ),
            ),
        ]),
      );

  Future<void> addFileSend(
    Id<Profiles> profileId,
    GraphId graph,
    FileContent file,
  ) => addTransfer(
    TransfersCompanion.insert(
      profileId: profileId,
      graph: graph,
      incoming: false,
      name: file.name,
      size: file.size,
      path: file.path,
      state: FileState.active,
    ),
  );

  Future<Map<GraphId, int>> getLinkedNotified(Id<Profiles> profileId) async => {
    for (final row in await (select(
      linkedNotified,
    )..where((n) => n.profileId.equals(profileId.value))).get())
      row.graph: row.rank,
  };

  Future<void> setLinkedNotified(
    Id<Profiles> profileId,
    GraphId graph,
    int rank,
  ) async {
    await into(linkedNotified).insertOnConflictUpdate(
      LinkedNotifiedCompanion.insert(
        profileId: profileId,
        graph: graph,
        rank: rank,
      ),
    );
  }

  Future<void> setRead(
    Id<Profiles> profileId,
    GraphId graph,
    (int, EventId) upTo,
  ) async {
    await into(chatReads).insertOnConflictUpdate(
      ChatReadsCompanion.insert(
        profileId: profileId,
        graph: graph,
        event: upTo.$2,
        rank: upTo.$1,
      ),
    );
  }

  Stream<List<ChatRead>> watchReads(Id<Profiles> profileId) => (select(
    chatReads,
  )..where((r) => r.profileId.equals(profileId.value))).watch();

  Future<StoredDraft?> getDraft(Id<Profiles> profileId, GraphId graph) =>
      (select(chatDrafts)..where(
            (d) =>
                d.profileId.equals(profileId.value) &
                d.graph.equalsValue(graph),
          ))
          .getSingleOrNull();

  Stream<Map<GraphId, StoredDraft>> watchDrafts(Id<Profiles> profileId) =>
      (select(chatDrafts)..where((d) => d.profileId.equals(profileId.value)))
          .watch()
          .map((drafts) => {for (final draft in drafts) draft.graph: draft});

  Future<void> setDraft(StoredDraft draft) async {
    await into(chatDrafts).insertOnConflictUpdate(draft);
  }

  Future<void> clearDraft(Id<Profiles> profileId, GraphId graph) async {
    await (delete(chatDrafts)..where(
          (d) =>
              d.profileId.equals(profileId.value) & d.graph.equalsValue(graph),
        ))
        .go();
  }

  /// The ranks of others' messages and files, by conversation, but for
  /// messages that repeat an earlier one as [formats] read them.
  Stream<Map<GraphId, List<int>>> watchReceivedRanks(
    Id<Profiles> profileId,
    MessageFormats formats,
  ) {
    var received = _Received(formats);
    return _addedEvents('profile_id = ? AND received', [
      Variable<int>(profileId.value),
    ]).map((added) {
      if (added.all) {
        received = _Received(formats);
      }
      added.events.forEach(received.add);
      return received.ranks;
    });
  }

  Future<void> addIntent(
    Id<Profiles> profileId,
    EventContent content, {
    GraphId? graph,
    bool deleteChat = false,
  }) async {
    await intents.insertOne(
      IntentsCompanion.insert(
        profileId: profileId,
        graph: Value(graph),
        content: content,
        deleteChat: Value(deleteChat),
      ),
    );
  }

  Future<void> showApart(
    Id<Profiles> profileId,
    GraphId chat,
    Map<ChatId, AccountMerge> merges,
  ) async {
    for (final MapEntry(key: other, value: merge) in merges.entries) {
      if (merge.into.graph == chat) {
        await addIntent(
          profileId,
          MergeChat(
            chat: other,
            bot: merge.bot,
            into: merge.into,
            intoBot: merge.intoBot,
            merged: false,
          ),
        );
      }
    }
  }

  Stream<List<StoredIntent>> watchIntents(Id<Profiles> profileId) =>
      (select(intents)
            ..where((i) => i.profileId.equals(profileId.value))
            ..orderBy([(i) => OrderingTerm(expression: i.id)]))
          .watch();

  /// Returns the [deleted] chat's files.
  Future<List<String>> writeIntent(
    StoredIntent intent,
    NewEvent event, {
    (GraphId, int)? deleted,
  }) => transaction(() async {
    await addSyncEvents(intent.profileId, [event]);
    await intents.deleteOne(intent);
    return deleted == null ? const [] : _deleteChat(intent.profileId, deleted);
  });

  /// Deletes a [chat]'s rows, remembering the rank its next event takes, and
  /// returns the paths of its files.
  Future<List<String>> _deleteChat(
    Id<Profiles> profileId,
    (GraphId, int) chat,
  ) async {
    final (graph, rank) = chat;
    final files = await _deleteWhere(
      {
        'profile_id': Variable<int>(profileId.value),
        'graph': Variable<String>(graph.toJson()),
      },
      kept: {deletedChats},
    );
    await into(deletedChats).insertOnConflictUpdate(
      DeletedChatsCompanion.insert(
        profileId: profileId,
        graph: graph,
        rank: rank,
      ),
    );
    return files;
  }

  /// The chats deleted on this device, by the rank their next event takes.
  Future<Map<GraphId, int>> getDeletedChats(Id<Profiles> profileId) async => {
    for (final row in await (select(
      deletedChats,
    )..where((c) => c.profileId.equals(profileId.value))).get())
      row.graph: row.rank,
  };

  Future<Id<Transfers>> addTransfer(TransfersCompanion entry) async =>
      Id(await into(transfers).insert(entry));

  /// The latest file from a friend in [graph] under [fileId], of [size],
  /// that stopped before it arrived whole, to go on with it. One cancelled
  /// or declined is offered again as a new one.
  Future<Transfer?> unfinishedTransfer(
    Id<Profiles> profileId,
    GraphId graph,
    FileId fileId,
    int size,
  ) =>
      (select(transfers)
            ..where(
              (t) =>
                  t.profileId.equals(profileId.value) &
                  t.graph.equalsValue(graph) &
                  t.incoming &
                  t.fileId.equalsValue(fileId) &
                  t.size.equals(size) &
                  t.state.isNotInValues([FileState.done, FileState.cancelled]),
            )
            ..orderBy([
              (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();

  Stream<List<Transfer>> watchTransfers(Id<Profiles> profileId) =>
      (select(transfers)
            ..where((t) => t.profileId.equals(profileId.value))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .watch();

  /// Saves [event], which started [transfer], with the blob it names.
  Future<void> writeTransferEvent(
    Id<Transfers> transfer,
    NewEvent event, {
    BlobId? blob,
  }) => transaction(() async {
    final row = await (select(
      transfers,
    )..where((t) => t.id.equals(transfer.value))).getSingle();
    await addSyncEvents(row.profileId, [event]);
    await (update(transfers)..where((t) => t.id.equals(transfer.value))).write(
      TransfersCompanion(
        event: Value(event.$1),
        blobId: Value.absentIfNull(blob),
      ),
    );
  });

  /// Fetches a linked account's [file], which [event] started, into [path]
  /// from the home device, unless it's fetched already.
  Future<void> fetchFile(
    Id<Profiles> profileId,
    GraphId graph,
    EventId event,
    FileContent file,
    BlobId blob,
    String path,
  ) => transaction(() async {
    final fetched =
        await (select(transfers)..where(
              (t) =>
                  t.profileId.equals(profileId.value) &
                  t.event.equalsValue(event),
            ))
            .get();
    if (fetched.isEmpty) {
      await addTransfer(
        TransfersCompanion.insert(
          profileId: profileId,
          graph: graph,
          event: Value(event),
          incoming: true,
          name: file.name,
          size: file.size,
          path: path,
          state: FileState.active,
          blobId: Value(blob),
        ),
      );
    }
  });

  Future<void> setTransferState(
    Id<Transfers> id,
    FileState state, {
    int? transferred,
  }) async {
    await (update(transfers)..where((t) => t.id.equals(id.value))).write(
      TransfersCompanion(
        state: Value(state),
        transferred: Value.absentIfNull(transferred),
      ),
    );
  }

  /// Accepts a file offered here, or declines one not yet ended, unless it
  /// ended meanwhile.
  Future<void> answerTransfer(Id<Transfers> id, {required bool accept}) async {
    await (update(transfers)..where(
          (t) =>
              t.id.equals(id.value) &
              t.state.isInValues([
                FileState.offered,
                if (!accept) ...[FileState.active, FileState.paused],
              ]),
        ))
        .write(
          TransfersCompanion(
            state: Value(accept ? FileState.active : FileState.cancelled),
          ),
        );
  }

  Future<void> setTransferred(Id<Transfers> id, int transferred) async {
    await (update(transfers)..where((t) => t.id.equals(id.value))).write(
      TransfersCompanion(transferred: Value(transferred)),
    );
  }

  Future<void> clearPairingMessage(Id<Profiles> id) async {
    await (update(profiles)..where((p) => p.id.equals(id.value))).write(
      const ProfilesCompanion(pairingMessage: Value(null)),
    );
  }

  Future<void> clearLiveFacts(Id<Profiles> profileId) async {
    await (delete(
      liveFacts,
    )..where((f) => f.profileId.equals(profileId.value))).go();
  }

  /// Takes in live facts as [Facts.update] does. With [all], they're all
  /// there are.
  Future<void> updateLiveFacts(
    Id<Profiles> profileId,
    Iterable<Fact> facts, {
    bool all = false,
  }) => transaction(() async {
    if (all) {
      await clearLiveFacts(profileId);
    }
    for (final (subject, value) in facts) {
      // A newer home device's, which shows nothing here.
      if (value is UnknownValue) {
        continue;
      }
      final key = encodeSubject(subject);
      if (value == const FactValue.present(false)) {
        await (delete(liveFacts)..where(
              (f) =>
                  f.profileId.equals(profileId.value) & f.subject.equals(key),
            ))
            .go();
      } else {
        await into(liveFacts).insertOnConflictUpdate(
          LiveFactsCompanion.insert(
            profileId: profileId,
            subject: key,
            kind: value.kind,
            fact: encodeFact(subject, value).encode(),
          ),
        );
      }
    }
  });

  Stream<AppSetting> watchAppSettings() =>
      select(appSettings).watchSingleOrNull().map(
        (settings) =>
            settings ??
            const AppSetting(
              id: 0,
              stayOnline: true,
              autoAcceptFileSize: defaultAutoAcceptFileSize,
            ),
      );

  Stream<Facts> watchLiveFacts(Id<Profiles> id) =>
      (select(liveFacts)..where((f) => f.profileId.equals(id.value)))
          .watch()
          .map((rows) => Facts.of(rows.map((row) => decodeFact(row.fact))));

  Stream<List<(EventId, SyncEvent)>> watchSyncEvents(
    Id<Profiles> id,
    GraphId graph,
  ) {
    var events = const <(EventId, SyncEvent)>[];
    return _addedEvents('profile_id = ? AND graph = ?', [
      Variable<int>(id.value),
      Variable<String>(graph.toJson()),
    ]).map(
      (added) =>
          events = added.all ? added.events : [...events, ...added.events],
    );
  }

  Stream<List<(EventId, SyncEvent)>> watchCalls(Id<Profiles> id) {
    bool isCall((EventId, SyncEvent) e) =>
        e.$2.content is Call || e.$2.content is CallEnded;
    var calls = const <(EventId, SyncEvent)>[];
    return _addedEvents('profile_id = ?', [
      Variable<int>(id.value),
    ]).where((added) => added.all || added.events.any(isCall)).map((added) {
      final more = added.events.where(isCall);
      return calls = added.all ? [...more] : [...calls, ...more];
    });
  }

  /// The readable events [where] picks, each read from the database once:
  /// first all of them, then those added since, in the order they were.
  /// Deleting events starts over with all.
  Stream<({bool all, List<(EventId, SyncEvent)> events})> _addedEvents(
    String where,
    List<Variable> variables,
  ) {
    late final StreamController<({bool all, List<(EventId, SyncEvent)> events})>
    controller;
    StreamSubscription<Set<TableUpdate>>? updates;
    var last = 0;
    var fetching = Future<void>.value();
    void fetch({required bool all}) {
      fetching = fetching
          .then((_) async {
            final rows = await customSelect(
              'SELECT rowid, id, bytes FROM sync_events '
              'WHERE $where AND rowid > ? ORDER BY rowid',
              variables: [...variables, Variable<int>(all ? 0 : last)],
              readsFrom: {syncEvents},
            ).get();
            if (rows.isNotEmpty) {
              last = rows.last.read<int>('rowid');
            } else if (all) {
              // Rows deleted from the end leave their rowids to new ones.
              last = 0;
            }
            if (all || rows.isNotEmpty) {
              controller.add((
                all: all,
                events: [for (final row in rows) ?_decodedRow(row)],
              ));
            }
          })
          .catchError(controller.addError);
    }

    controller = StreamController(
      onListen: () {
        // Listened to first, so nothing added meanwhile is missed.
        updates = tableUpdates(TableUpdateQuery.onTable(syncEvents)).listen(
          (changes) => fetch(
            all: changes.any(
              (change) =>
                  change.kind != UpdateKind.insert &&
                  change.kind != UpdateKind.update,
            ),
          ),
        );
        fetch(all: true);
      },
      onCancel: () => updates?.cancel(),
    );
    return controller.stream;
  }

  Future<int> _countIn(Id<Profiles> id, GraphId graph) async =>
      (await customSelect(
        'SELECT COUNT(*) AS count FROM sync_events '
        'WHERE profile_id = ? AND graph = ?',
        variables: [Variable<int>(id.value), Variable<String>(graph.toJson())],
        readsFrom: {syncEvents},
      ).getSingle()).read<int>('count');

  Future<List<(EventId, SyncEvent)>> _syncEventsIn(
    Id<Profiles> id,
    GraphId graph,
  ) async => [
    for (final row in await customSelect(
      'SELECT id, bytes FROM sync_events WHERE profile_id = ? AND graph = ?',
      variables: [Variable<int>(id.value), Variable<String>(graph.toJson())],
      readsFrom: {syncEvents},
    ).get())
      ?_decodedRow(row),
  ];

  (EventId, SyncEvent)? _decodedRow(QueryRow row) {
    final id = EventId.fromJson(row.read<String>('id'));
    return switch (_decoded[id] ??= _readable(row.read<Uint8List>('bytes'))) {
      final event? => (id, event),
      null => null,
    };
  }

  Stream<Profile> watchProfile(Id<Profiles> id) =>
      (select(profiles)..where((p) => p.id.equals(id.value))).watchSingle();

  Stream<List<Profile>> watchProfiles() => select(profiles).watch();
}

/// Null for an event this version can't read, which the background service
/// drops to sync again.
SyncEvent? _readable(Uint8List bytes) {
  try {
    return SyncEvent.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// The ranks of received messages and files, by conversation, as they come
/// in any order: of messages with the same key, only the first counts.
final class _Received {
  final MessageFormats _formats;
  final _ranks = <GraphId, List<int>>{};
  final _first = <GraphId, Map<MessageKey, (int, EventId)>>{};

  _Received(this._formats);

  Map<GraphId, List<int>> get ranks => {
    for (final MapEntry(:key, :value) in _ranks.entries) key: [...value],
  };

  void add((EventId, SyncEvent) received) {
    final (id, event) = received;
    final ranks = _ranks.putIfAbsent(event.graph, () => []);
    final key = keyOf(event.content, _formats);
    if (key == null) {
      ranks.add(event.rank);
      return;
    }
    final firsts = _first.putIfAbsent(event.graph, () => {});
    final first = firsts[key];
    if (first == null || compareRanks((event.rank, id), first) < 0) {
      if (first != null) {
        ranks.remove(first.$1);
      }
      firsts[key] = (event.rank, id);
      ranks.add(event.rank);
    }
  }
}
