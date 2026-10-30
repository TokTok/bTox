import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/attachments/attachments.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_File_Control;
import 'package:btox/logger.dart';
import 'package:btox/models/app_defaults.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/session_message.dart';
import 'package:btox/sync/store.dart';
import 'package:clock/clock.dart';

const _logger = Logger(['LinkedFiles']);

/// A file of the home device's, by friend number and file number.
typedef _Key = (int, int);

final class _Moving {
  final Transfer row;
  final Attachment file;
  DateTime saved = clock.now();

  _Moving(this.row, this.file);
}

/// Moves a linked account's files between this device and its home device:
/// the blobs of the files its chats send, and of those they show.
final class LinkedFiles implements ToxFiles {
  final Database _db;
  final Tox _tox;
  final Id<Profiles> _profileId;
  final PublicKey _device;
  final Future<String> Function() _directory;
  final void Function(SessionMessage) _toHome;

  /// Larger files are fetched when asked for.
  int autoAcceptSize = defaultAutoAcceptFileSize;

  var _transfers = const <Transfer>[];
  // The home device, while in a session with it.
  int? _home;
  // Asked of the home device in this session.
  final _wanted = <BlobId>{};
  // Files whose fetch was decided on, so it's decided once.
  final _ended = <EventId>{};
  // The ends of files whose start hasn't come yet.
  final _endsWaiting = <EventId, (SyncEvent, BlobId)>{};
  final _incoming = <_Key, _Moving>{};
  final _outgoing = <_Key, _Moving>{};

  LinkedFiles(
    this._db,
    this._tox,
    this._profileId,
    this._device,
    this._directory,
    this._toHome,
  );

  void dispose() => _stop();

  void transfersChanged(List<Transfer> transfers) {
    _transfers = transfers;
    _fetch();
  }

  /// A session with the home device, [home], started, or ended with null.
  /// Toxcore drops the transfers of a friend that goes offline, and blobs
  /// cut off are asked for again in the next session.
  void session(int? home) {
    _home = home;
    _wanted.clear();
    // A session started again asks for its blobs again, so those still
    // moving would stall.
    if (home != null) {
      for (final key in [..._incoming.keys, ..._outgoing.keys]) {
        _control(key, Tox_File_Control.TOX_FILE_CONTROL_CANCEL);
      }
    }
    _stop();
    _fetch();
  }

  void _stop() {
    for (final moving in [..._incoming.values, ..._outgoing.values]) {
      moving.file.close();
    }
    _incoming.clear();
    _outgoing.clear();
  }

  void _fetch() {
    if (_home == null) {
      return;
    }
    for (final row in _transfers) {
      if (row
          case Transfer(
            incoming: true,
            state: FileState.active,
            blobId: final blob?,
          )
          when _wanted.add(blob)) {
        _toHome(WantBlob(blob));
      }
    }
  }

  void received(SessionMessage message) {
    switch (message) {
      case WantBlob(:final blob):
        _send(blob);
      case NoBlob(:final blob):
        for (final row in _transfers) {
          if (row
              case Transfer(
                incoming: true,
                state: FileState.active,
                blobId: final b?,
              )
              when b == blob) {
            _logger.unawaited(
              'give up the file',
              _db.setTransferState(row.id, FileState.cancelled),
            );
          }
        }
      default:
        break;
    }
  }

  /// Fetches the files that [events] end well at the home device, those up
  /// to [autoAcceptSize] or that this device accepted.
  Future<void> fetchEnded(
    EventStore store,
    Iterable<(EventId, SyncEvent)> events,
  ) async {
    for (final (id, event) in events) {
      switch (event.content) {
        case FileEnded(ok: true, :final file, :final blob?):
          await _fetchFile(store, event, file, blob);
        // A file's end can come before its start.
        case FileStarted():
          if (_endsWaiting.remove(id) case (final ended, final blob)) {
            await _fetchFile(store, ended, id, blob);
          }
        default:
          break;
      }
    }
  }

  Future<void> _fetchFile(
    EventStore store,
    SyncEvent ended,
    EventId file,
    BlobId blob,
  ) async {
    switch (store[file]?.content) {
      case null:
        _endsWaiting[file] = (ended, blob);
      case FileStarted(:final name, :final size)
          when _ended.add(file) &&
              (size <= autoAcceptSize || _acceptedHere(store, ended, file)):
        await _db.fetchFile(
          _profileId,
          ended.graph,
          file,
          FileContent(name: name, size: size),
          blob,
          newAttachmentPath(await _directory(), name),
        );
      default:
        break;
    }
  }

  bool _acceptedHere(EventStore store, SyncEvent ended, EventId file) => store
      .eventsIn(ended.graph)
      .any(
        (e) =>
            e.$2.author == _device &&
            e.$2.content == FileAnswered(file: file, accepted: true),
      );

  /// Sends [blob] to the home device as a file, if it's here.
  void _send(BlobId blob) {
    final home = _home;
    if (home == null) {
      return;
    }
    final row = _transfers
        .where(
          (t) =>
              t.blobId == blob &&
              (t.incoming
                  ? t.state == FileState.done
                  : t.state != FileState.cancelled),
        )
        .firstOrNull;
    Attachment? file;
    try {
      file = row == null ? null : Attachment.open(row.path);
    } on Exception catch (e) {
      _logger.w('Cannot open the file of blob ${blob.toJson()}: $e');
      file = null;
    }
    if (row == null || file == null) {
      _toHome(NoBlob(blob));
      return;
    }
    try {
      final fileNumber = _tox.fileSend(
        home,
        blobFileKind,
        row.size,
        blob.bytes,
        Uint8List(0),
      );
      _outgoing[(home, fileNumber)] = _Moving(row, file);
    } on ApiException catch (e) {
      file.close();
      _logger.w('Failed to send blob ${blob.toJson()}: $e');
    }
  }

  /// Takes a file the home device sends if it's a blob asked of it, and
  /// cancels any other.
  void offered(int friendNumber, int fileNumber, int kind, int size) {
    final key = (friendNumber, fileNumber);
    final row = friendNumber == _home && kind == blobFileKind
        ? _fetchOf(BlobId(_tox.fileGetFileId(friendNumber, fileNumber)))
        : null;
    if (row == null) {
      _control(key, Tox_File_Control.TOX_FILE_CONTROL_CANCEL);
      return;
    }
    try {
      var file = Attachment.resume(row.path);
      if (file.length >= size) {
        file.close();
        file = Attachment.create(row.path);
      }
      if (file.length > 0) {
        _tox.fileSeek(friendNumber, fileNumber, file.length);
      }
      _incoming[key] = _Moving(row, file);
    } catch (e) {
      _logger.e('Cannot write ${row.path}: $e');
      _control(key, Tox_File_Control.TOX_FILE_CONTROL_CANCEL);
      return;
    }
    _control(key, Tox_File_Control.TOX_FILE_CONTROL_RESUME);
  }

  Transfer? _fetchOf(BlobId blob) => _wanted.contains(blob)
      ? _transfers
            .where(
              (t) =>
                  t.incoming && t.state == FileState.active && t.blobId == blob,
            )
            .firstOrNull
      : null;

  @override
  void chunk(int friendNumber, int fileNumber, int position, Uint8List data) {
    final key = (friendNumber, fileNumber);
    final moving = _incoming[key];
    if (moving == null) {
      return;
    }
    if (data.isEmpty) {
      _incoming.remove(key);
      moving.file.close();
      _logger.unawaited('keep the file', _keep(moving.row));
      return;
    }
    moving.file.write(position, data);
    _progress(moving, position + data.length);
  }

  /// Keeps a fetched file if it has the blob ID asked for.
  Future<void> _keep(Transfer row) async {
    final ok = await blobOf(row.path) == row.blobId;
    if (!ok) {
      _logger.w('Fetched ${row.path} is not what was asked for');
      await deleteAttachment(row.path);
    }
    await _db.setTransferState(
      row.id,
      ok ? FileState.done : FileState.cancelled,
      transferred: ok ? row.size : null,
    );
  }

  @override
  void requested(int friendNumber, int fileNumber, int position, int length) {
    final key = (friendNumber, fileNumber);
    final moving = _outgoing[key];
    if (moving == null) {
      return;
    }
    final row = moving.row;
    // Ours, on its first trip to the home device.
    final sending = !row.incoming && row.state == FileState.active;
    if (length == 0) {
      _outgoing.remove(key);
      moving.file.close();
      if (sending) {
        _logger.unawaited(
          'finish the file',
          _db.setTransferState(row.id, FileState.done, transferred: row.size),
        );
      }
      return;
    }
    try {
      _tox.fileSendChunk(
        friendNumber,
        fileNumber,
        position,
        moving.file.read(position, length),
      );
      if (sending) {
        _progress(moving, position + length);
      }
    } on ApiException catch (e) {
      _logger.w('Failed to send a file chunk: $e');
    }
  }

  /// A blob the home device cancelled is asked for again in the next
  /// session.
  @override
  void controlled(int friendNumber, int fileNumber, Tox_File_Control control) {
    if (control != Tox_File_Control.TOX_FILE_CONTROL_CANCEL) {
      return;
    }
    final key = (friendNumber, fileNumber);
    _incoming.remove(key)?.file.close();
    _outgoing.remove(key)?.file.close();
  }

  void _control(_Key key, Tox_File_Control control) {
    try {
      _tox.fileControl(key.$1, key.$2, control);
    } on ApiException catch (e) {
      _logger.w('Failed to control file ${key.$2}: $e');
    }
  }

  void _progress(_Moving moving, int transferred) {
    final now = clock.now();
    if (now.difference(moving.saved) > progressSaveInterval) {
      moving.saved = now;
      _logger.unawaited(
        'save progress',
        _db.setTransferred(moving.row.id, transferred),
      );
    }
  }
}
