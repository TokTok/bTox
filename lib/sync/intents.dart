import 'dart:async';

import 'package:btox/db/database.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/setting.dart';
import 'package:clock/clock.dart';

const _logger = Logger(['EventWriter']);

/// Writes a device's events one after another, each made once the one before
/// it is saved, and the pages' intents as events.
final class EventWriter {
  final Database _db;
  final Id<Profiles> _profileId;
  final NewEvent Function(GraphId graph, DateTime time, EventContent content)
  _author;
  final void Function(NewEvent event) _saved;
  Future<void> _writing = Future.value();

  // Rows being written as events, so none is written twice.
  final _rows = <Id<Object>>{};

  EventWriter(this._db, this._profileId, this._author, this._saved);

  /// Writes what [content] says once the events before it are in, if it
  /// says anything, saved by [save] if given, or null if nothing was saved.
  Future<NewEvent?> write(
    GraphId graph,
    EventContent? Function() content, {
    Future<void> Function(NewEvent)? save,
  }) {
    final written = _writing.then((_) async {
      final next = content();
      if (next == null) {
        return null;
      }
      final event = _author(graph, clock.now(), next);
      try {
        await (save ?? (e) => _db.addSyncEvents(_profileId, [e]))(event);
      } on Object catch (e) {
        // Whatever went wrong, the event isn't saved.
        _logger.e('Failed to save an event: $e');
        return null;
      }
      _saved(event);
      return event;
    });
    _writing = written.then((_) {}, onError: (Object _) {});
    return written;
  }

  /// Writes the event for a row, unless it's being written. A row whose
  /// event couldn't be saved is tried again when the rows change.
  Future<void> once(Id<Object> row, Future<NewEvent?> Function() write) async {
    if (_rows.add(row) && await write() == null) {
      _rows.remove(row);
    }
  }

  /// Writes the pages' intents, in [account] where they name no chat, as
  /// [senderIn] each chat. One naming a chat that [canWrite] says no to
  /// waits for it. [save] stores the event in place of its intent.
  Future<void> intents(
    List<StoredIntent> intents,
    GraphId account,
    String Function(GraphId chat) senderIn, {
    bool Function(GraphId graph)? canWrite,
    Future<void> Function(StoredIntent intent, NewEvent event)? save,
  }) async {
    for (final intent in intents) {
      if (canWrite != null && !(_chatsOf(intent)?.every(canWrite) ?? false)) {
        continue;
      }
      final graph = intent.graph ?? account;
      await once(
        intent.id,
        () => write(
          graph,
          () => switch (intent.content) {
            final Send send => send.copyWith(sender: senderIn(graph)),
            final content => content,
          },
          save: (event) async => save == null
              ? _db.writeIntent(intent, event)
              : save(intent, event),
        ),
      );
    }
  }

  // The chats [intent] writes about, or null where none can write it.
  static List<GraphId>? _chatsOf(StoredIntent intent) =>
      switch (intent.content) {
        MergeChat(:final chat, :final into) => [chat.graph, into.graph],
        RelayBot(:final chat) => [chat.graph],
        SettingContent(:final scope) ||
        ClearSetting(:final scope) => switch (scope) {
          AccountScope() => [],
          ConversationScope(:final graph) => [graph],
          UnknownScope() => null,
        },
        _ => [?intent.graph],
      };

  /// Writes the files the chat pages send, as [senderIn] each chat.
  Future<void> files(
    List<Transfer> transfers,
    String Function(GraphId chat) senderIn,
    Future<BlobId> Function(String path) blobOf,
  ) async {
    for (final transfer in transfers) {
      if (transfer case Transfer(
        incoming: false,
        event: null,
        state: FileState.active,
      )) {
        await once(transfer.id, () async {
          final BlobId blob;
          try {
            blob = await blobOf(transfer.path);
          } on Exception catch (e) {
            _logger.w('Cannot read ${transfer.path}: $e');
            await _db.setTransferState(transfer.id, FileState.cancelled);
            return null;
          }
          return write(
            transfer.graph,
            () => FileStarted(
              sender: senderIn(transfer.graph),
              name: transfer.name,
              size: transfer.size,
              incoming: false,
              blob: blob,
            ),
            save: (event) =>
                _db.writeTransferEvent(transfer.id, event, blob: blob),
          );
        });
      }
    }
  }

  /// Writes a marker in [account] for each chat seen further than [state]
  /// says.
  Future<void> reads(
    GraphId account,
    List<ChatRead> reads,
    AccountState Function() state,
  ) async {
    for (final read in reads) {
      await write(
        account,
        () => isAfter((read.rank, read.event), state().read[read.graph])
            ? ReadUpTo(graph: read.graph, event: read.event, rank: read.rank)
            : null,
      );
    }
  }
}
