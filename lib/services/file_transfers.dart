import 'dart:convert';
import 'dart:math';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/api/toxcore/tox_constants.dart';
import 'package:btox/attachments/attachments.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_File_Control, Tox_File_Kind;
import 'package:btox/logger.dart';
import 'package:btox/models/app_defaults.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/messaging.dart';
import 'package:btox/models/persistence.dart';
import 'package:flutter/foundation.dart';

const _logger = Logger(['FileTransfers']);

/// A friend's file, by friend number and file number.
typedef _Key = (int, int);

final class _Transfer {
  final Id<Messages> id;
  final int size;
  final String path;
  Attachment? file;
  int transferred = 0;
  DateTime saved = DateTime.now();

  _Transfer(this.id, this.size, this.path, [this.file]);
}

/// Moves files between one profile's Tox and its attachments directory.
final class FileTransfers {
  final Database _db;
  final Tox _tox;
  final Future<String> Function() _directory;
  final _incoming = <_Key, _Transfer>{};
  final _outgoing = <_Key, _Transfer>{};
  final _random = Random.secure();

  /// Larger files wait until accepted.
  int autoAcceptSize = defaultAutoAcceptFileSize;

  FileTransfers(this._db, this._tox, this._directory);

  void dispose() {
    for (final transfer in [..._incoming.values, ..._outgoing.values]) {
      transfer.file?.close();
    }
    _incoming.clear();
    _outgoing.clear();
  }

  bool isSending(Id<Messages> id) => _outgoing.values.any((t) => t.id == id);

  Future<void> offered(
    Contact contact,
    int friendNumber,
    int fileNumber,
    int kind,
    int size,
    String name,
  ) async {
    // Avatars aren't supported yet.
    if (kind != Tox_File_Kind.TOX_FILE_KIND_DATA.value || !filesSupported) {
      _control(
        friendNumber,
        fileNumber,
        Tox_File_Control.TOX_FILE_CONTROL_CANCEL,
      );
      return;
    }
    final path = newAttachmentPath(await _directory(), name);
    final accept = size <= autoAcceptSize;
    final id = await _db.addMessage(
      newMessage(
        contactId: contact.id,
        parent: null,
        merged: null,
        author: contact.publicKey,
        timestamp: DateTime.now().toUtc(),
        content: FileContent(name: name, size: size, path: path),
      ).copyWith(
        fileState: Value(accept ? FileState.active : FileState.offered),
        fileTransferred: const Value(0),
      ),
    );
    _incoming[(friendNumber, fileNumber)] = _Transfer(id, size, path);
    if (accept) {
      _accept((friendNumber, fileNumber));
    }
  }

  /// Follows the user accepting or declining offered files.
  void incomingChanged(List<Message> messages) {
    final states = {for (final m in messages) m.id: m.fileState};
    for (final MapEntry(:key, value: transfer) in [..._incoming.entries]) {
      switch (states[transfer.id]) {
        case FileState.active when transfer.file == null:
          _accept(key);
        case FileState.cancelled:
          _control(key.$1, key.$2, Tox_File_Control.TOX_FILE_CONTROL_CANCEL);
          _incoming.remove(key);
        default:
          break;
      }
    }
  }

  void received(
    int friendNumber,
    int fileNumber,
    int position,
    Uint8List data,
  ) {
    final key = (friendNumber, fileNumber);
    final transfer = _incoming[key];
    if (transfer == null) {
      return;
    }
    if (data.isEmpty) {
      _incoming.remove(key);
      _finish(transfer);
      return;
    }
    transfer.file?.write(position, data);
    _progress(transfer, position + data.length);
  }

  void requested(int friendNumber, int fileNumber, int position, int length) {
    final key = (friendNumber, fileNumber);
    final transfer = _outgoing[key];
    if (transfer == null) {
      return;
    }
    if (length == 0) {
      _outgoing.remove(key);
      _run('mark file delivered', _db.markMessageDelivered(transfer.id));
      _finish(transfer);
      return;
    }
    try {
      final data = transfer.file!.read(position, length);
      _tox.fileSendChunk(friendNumber, fileNumber, position, data);
      _progress(transfer, position + length);
    } on ApiException catch (e) {
      _logger.w('Failed to send a file chunk: $e');
    }
  }

  void controlled(int friendNumber, int fileNumber, Tox_File_Control control) {
    if (control != Tox_File_Control.TOX_FILE_CONTROL_CANCEL) {
      return;
    }
    final key = (friendNumber, fileNumber);
    for (final transfers in [_incoming, _outgoing]) {
      if (transfers.remove(key) case final transfer?) {
        _cancel(transfer);
      }
    }
  }

  void send(Message message, int friendNumber) {
    if (isSending(message.id) ||
        message.content is! FileContent ||
        message.fileState != FileState.active) {
      return;
    }
    final content = message.content as FileContent;
    final Attachment file;
    try {
      file = Attachment.open(content.path);
    } catch (e) {
      _logger.w('Cannot read ${content.path}: $e');
      _run('cancel file', _db.setFileState(message.id, FileState.cancelled));
      return;
    }
    try {
      final fileNumber = _tox.fileSend(
        friendNumber,
        Tox_File_Kind.TOX_FILE_KIND_DATA.value,
        content.size,
        _fileId(),
        utf8.encode(content.name),
      );
      _outgoing[(friendNumber, fileNumber)] = _Transfer(
        message.id,
        content.size,
        content.path,
        file,
      );
    } on ApiException catch (e) {
      file.close();
      _logger.w('Failed to send file ${message.id}: $e');
    }
  }

  /// Toxcore drops a friend's transfers when they go offline.
  void friendOffline(int friendNumber) {
    for (final key in [..._incoming.keys.where((k) => k.$1 == friendNumber)]) {
      _cancel(_incoming.remove(key)!);
    }
    for (final key in [..._outgoing.keys.where((k) => k.$1 == friendNumber)]) {
      final transfer = _outgoing.remove(key)!;
      transfer.file?.close();
      _run('restart file', _db.setFileTransferred(transfer.id, 0));
    }
  }

  void _accept(_Key key) {
    final transfer = _incoming[key]!;
    try {
      transfer.file = Attachment.create(transfer.path);
    } catch (e) {
      _logger.e('Cannot write ${transfer.path}: $e');
      _control(key.$1, key.$2, Tox_File_Control.TOX_FILE_CONTROL_CANCEL);
      _cancel(_incoming.remove(key)!);
      return;
    }
    _control(key.$1, key.$2, Tox_File_Control.TOX_FILE_CONTROL_RESUME);
  }

  void _finish(_Transfer transfer) {
    transfer.file?.close();
    _run(
      'finish file',
      _db.setFileState(transfer.id, FileState.done, transferred: transfer.size),
    );
  }

  void _cancel(_Transfer transfer) {
    transfer.file?.close();
    _run('cancel file', _db.setFileState(transfer.id, FileState.cancelled));
  }

  void _control(int friendNumber, int fileNumber, Tox_File_Control control) {
    try {
      _tox.fileControl(friendNumber, fileNumber, control);
    } on ApiException catch (e) {
      _logger.w('Failed to control file $fileNumber: $e');
    }
  }

  void _progress(_Transfer transfer, int transferred) {
    transfer.transferred = transferred;
    final now = DateTime.now();
    if (now.difference(transfer.saved) > const Duration(milliseconds: 500)) {
      transfer.saved = now;
      _run('save progress', _db.setFileTransferred(transfer.id, transferred));
    }
  }

  // Toxcore would make up a random one itself.
  Uint8List _fileId() => Uint8List.fromList([
    for (var i = 0; i < toxFileIdLength; i++) _random.nextInt(256),
  ]);

  void _run(String what, Future<void> future) {
    future.catchError((Object e) => _logger.e('Failed to $what: $e'));
  }
}
