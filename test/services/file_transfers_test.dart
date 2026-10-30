import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/services/file_transfers.dart';
import 'package:btox/sync/event.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_toxcore.dart';

final _me = PublicKey(Uint8List(32));
final _chat = GraphId.friend(_me, PublicKey(Uint8List(32)..[0] = 1));
const _data = Tox_File_Kind.TOX_FILE_KIND_DATA;
const _resume = Tox_File_Control.TOX_FILE_CONTROL_RESUME;
const _cancel = Tox_File_Control.TOX_FILE_CONTROL_CANCEL;

Future<void> _settle() => Future.delayed(const Duration(milliseconds: 50));

void main() {
  late Database db;
  late FakeToxcore tox;
  late Directory directory;
  late List<EventContent> recorded;
  late FileTransfers files;
  late Id<Profiles> profileId;

  setUp(() async {
    db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    directory = await Directory.systemTemp.createTemp();
    addTearDown(() => directory.delete(recursive: true));
    tox = FakeToxcore();
    profileId = await db.addProfile(
      ProfilesCompanion.insert(
        settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: _me,
        nospam: ToxAddressNospam(0),
      ),
    );
    recorded = [];
    files = FileTransfers(db, tox, profileId, () async => directory.path, (
      graph,
      content,
    ) async {
      recorded.add(content);
      final event = SyncEvent(
        graph: graph,
        author: _me,
        parents: const [],
        rank: recorded.length,
        time: 0,
        content: content,
      );
      return (EventId.of(event.encode()), event, event.encode());
    });
    addTearDown(files.dispose);
  });

  Future<Transfer> transfer() async =>
      (await db.watchTransfers(profileId).first).single;

  test('a file sent again after it stopped goes on where it stopped', () async {
    tox.fileIds[(0, 0)] = tox.fileIds[(0, 1)] = Uint8List(32)..[0] = 7;
    await files.offered(_chat, 'Bob', 0, 0, _data.value, 6, 'a.txt');
    files.chunk(0, 0, 0, utf8.encode('abc'));
    files.friendOffline(0);
    await _settle();
    expect((await transfer()).state, FileState.paused);

    await files.offered(_chat, 'Bob', 0, 1, _data.value, 6, 'a.txt');
    expect(tox.fileSeeks, [(0, 1, 3)]);
    expect(tox.fileControls, [(0, 0, _resume), (0, 1, _resume)]);
    files.chunk(0, 1, 3, utf8.encode('def'));
    files.chunk(0, 1, 6, Uint8List(0));
    await _settle();

    final done = await transfer();
    expect(done.state, FileState.done);
    expect(await File(done.path).readAsString(), 'abcdef');
    expect(recorded.whereType<FileStarted>(), hasLength(1));
  });

  test('a file sent again is new where it was cancelled or its size is '
      'not the same', () async {
    files.autoAcceptSize = 10;
    tox.fileIds[(0, 0)] = tox.fileIds[(0, 1)] = Uint8List(32)..[0] = 7;
    tox.fileIds[(0, 2)] = tox.fileIds[(0, 3)] = Uint8List(32)..[0] = 8;
    await files.offered(_chat, 'Bob', 0, 0, _data.value, 6, 'a.txt');
    files.chunk(0, 0, 0, utf8.encode('abc'));
    files.controlled(0, 0, _cancel);
    await files.offered(_chat, 'Bob', 0, 2, _data.value, 6, 'b.txt');
    files.chunk(0, 2, 0, utf8.encode('abc'));
    files.friendOffline(0);
    await _settle();

    await files.offered(_chat, 'Bob', 0, 1, _data.value, 6, 'a.txt');
    await files.offered(_chat, 'Bob', 0, 3, _data.value, 1 << 30, 'b.txt');
    expect(tox.fileSeeks, isEmpty);
    expect(tox.fileControls, [
      (0, 0, _resume),
      (0, 2, _resume),
      (0, 1, _resume),
    ]);
    expect(recorded.whereType<FileStarted>(), hasLength(4));
  });

  test('a file cancelled while it is recorded ends cancelled', () async {
    final offered = files.offered(_chat, 'Bob', 0, 0, _data.value, 6, 'a.txt');
    files.controlled(0, 0, _cancel);
    await offered;
    await _settle();

    expect(tox.fileControls, isEmpty);
    expect((await transfer()).state, FileState.cancelled);
  });

  test('a file cancelled while it is recorded, its number taken by the next '
      'one, ends cancelled', () async {
    final first = files.offered(_chat, 'Bob', 0, 0, _data.value, 6, 'a.txt');
    files.controlled(0, 0, _cancel);
    final next = files.offered(_chat, 'Bob', 0, 0, _data.value, 6, 'b.txt');
    await first;
    await next;
    await _settle();

    expect(tox.fileControls, [(0, 0, _resume)]);
    expect(
      {
        for (final t in await db.watchTransfers(profileId).first)
          t.name: t.state,
      },
      {'a.txt': FileState.cancelled, 'b.txt': FileState.active},
    );
  });

  test('a file declined while it comes keeps how much came', () async {
    await files.offered(_chat, 'Bob', 0, 0, _data.value, 6, 'a.txt');
    files.chunk(0, 0, 0, utf8.encode('abc'));
    files.incomingChanged([
      (await transfer()).copyWith(state: FileState.cancelled),
    ]);
    await _settle();

    expect(tox.fileControls.last, (0, 0, _cancel));
    expect((await transfer()).transferred, 3);
    expect(recorded.last, isA<FileEnded>().having((e) => e.ok, 'ok', false));
  });

  test('a chunk Tox has no room for is sent again', () async {
    final path = '${directory.path}/b.txt';
    await File(path).writeAsString('abc');
    final event = EventId(Uint8List(32)..[0] = 9);
    await db.addTransfer(
      TransfersCompanion.insert(
        profileId: profileId,
        graph: _chat,
        event: Value(event),
        incoming: false,
        name: 'b.txt',
        size: 3,
        path: path,
        state: FileState.active,
      ),
    );
    files.send(await transfer(), 0);
    // The friend can go on with it if it stops.
    expect(tox.fileSendKinds.single.$2, event.bytes);

    // Tox asks for chunks ahead, and takes each only after the one before.
    tox.fullChunkQueues = 1;
    for (final position in [0, 1, 2]) {
      files.requested(0, 0, position, 1);
    }
    await Future.delayed(chunkRetryDelay * 3);
    expect(
      [
        for (final (_, _, position, data) in tox.fileChunks)
          (position, utf8.decode(data)),
      ],
      [(0, 'a'), (1, 'b'), (2, 'c')],
    );
  });
}
