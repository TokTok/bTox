import 'dart:async';
import 'dart:convert';

import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
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

  /// Writes what the chat pages send, as [senderIn] each chat.
  Future<void> sends(
    List<ChatSend> sends,
    String Function(GraphId chat) senderIn,
  ) async {
    for (final send in sends) {
      await once(
        send.id,
        () => write(
          send.graph,
          () => Send(
            sender: senderIn(send.graph),
            message: utf8.encode(send.message),
            kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
          ),
          save: (event) => _db.writeSend(send, event),
        ),
      );
    }
  }

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

  /// Writes the chat pages' answers to files offered to the home device.
  Future<void> answers(List<FileAnswer> answers) async {
    for (final answer in answers) {
      await once(
        answer.id,
        () => write(
          answer.graph,
          () => FileAnswered(file: answer.file, accepted: answer.accepted),
          save: (event) => _db.writeFileAnswer(answer, event),
        ),
      );
    }
  }

  Future<void> inviteAnswers(
    GraphId account,
    List<InviteAnswer> answers,
  ) async {
    for (final answer in answers) {
      await once(
        answer.id,
        () => write(
          account,
          () => AnswerInvite(
            invite: answer.invite,
            join: answer.accepted,
            password: answer.password,
          ),
          save: (event) => _db.writeInviteAnswer(answer, event),
        ),
      );
    }
  }

  Future<void> settings(GraphId account, List<SettingChange> changes) async {
    for (final change in changes) {
      await once(
        change.id,
        () => write(
          account,
          () => switch (change.setting) {
            final setting? => SettingContent(
              scope: change.scope,
              setting: setting,
            ),
            null => ClearSetting(scope: change.scope, kind: change.kind),
          },
          save: (event) => _db.writeSetting(change, event),
        ),
      );
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
