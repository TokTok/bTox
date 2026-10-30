import 'dart:convert';
// The analyzer resolves ToxLibrary's conditional export to the stub.
// ignore_for_file: argument_type_not_assignable

import 'dart:io';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart' as gen;
import 'package:btox/ffi/tox_library.ffi.dart' as tox_lib;
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/services/backup.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/home.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/sync/store.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

PublicKey _key(int n) => PublicKey(Uint8List.fromList(List.filled(32, n)));

/// An account with a friend who sent two messages, the first one read, and
/// the chat being unmuted.
Future<Id<Profiles>> _addAccount(Database db, String name, int key) async {
  final settings = ProfileSettings(nickname: name, statusMessage: '');
  final id = await db.addProfile(
    ProfilesCompanion.insert(
      settings: settings,
      secretKey: SecretKey(Uint8List(32)),
      publicKey: _key(key),
      nospam: ToxAddressNospam(0),
    ),
  );
  final account = AccountWriter(_key(key), settings);
  final friend = _key(key + 1);
  final chat = GraphId.friend(_key(key), friend);
  final time = DateTime.utc(2026);
  Received said(String text) => Received(
    sender: "$name's friend",
    message: utf8.encode(text),
    kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
  );
  account
    ..add(account.account, time, WantFriend(pk: friend))
    ..add(
      account.account,
      time,
      FactContent(
        subject: Subject.friend(friend),
        value: FactValue.name("$name's friend"),
      ),
    );
  final first = account.add(chat, time, said('Hi $name'));
  account
    ..add(chat, time, said('Reply'))
    ..add(account.account, time, ReadUpTo(graph: chat, event: first, rank: 0));
  await db.addSyncEvents(id, account.events);
  await db.addIntent(
    id,
    ClearSetting(scope: Scope.conversation(chat), kind: Setting.muteKind),
  );
  return id;
}

Future<AccountState> _account(Database db, Id<Profiles> id) async {
  final profile = await db.watchProfile(id).first;
  return AccountState.of(
    rankOrder(
      await db.watchSyncEvents(id, GraphId.account(profile.publicKey)).first,
    ),
  );
}

Future<List<String>> _said(Database db, Id<Profiles> id, PublicKey to) async {
  final profile = await db.watchProfile(id).first;
  return [
    for (final (_, event) in rankOrder(
      await db.watchSyncEvents(id, GraphId.friend(profile.publicKey, to)).first,
    ))
      if (event.content case Received(:final message)) utf8.decode(message),
  ];
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Database source;
  late Database target;
  late Id<Profiles> alice;
  late Id<Profiles> bob;

  setUp(() async {
    source = Database(NativeDatabase.memory());
    target = Database(NativeDatabase.memory());
    alice = await _addAccount(source, 'Alice', 1);
    bob = await _addAccount(source, 'Bob', 3);
    await source.signIn(bob);
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  Future<Backup> backup([Set<Id<Profiles>>? profiles]) async =>
      readBackup(await exportBackup(source, profiles ?? {alice, bob}))!;

  test('restores everything into an empty bTox', () async {
    final backedUp = await backup();
    expect(await restoreBackup(target, backedUp, {alice.value, bob.value}), 2);
    expect(
      await exportBackup(target, {alice, bob}),
      await exportBackup(source, {alice, bob}),
    );
  });

  test('a linked account comes back linked, to sync again', () async {
    final home = ToxAddress.of(_key(9), ToxAddressNospam(0x01020304));
    final linked = await source.addProfile(
      ProfilesCompanion.insert(
        settings: ProfileSettings(nickname: 'bTox', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)..fillRange(0, 32, 5)),
        publicKey: _key(5),
        nospam: ToxAddressNospam(0),
        home: Value(home),
      ),
    );
    await source.updateLiveFacts(linked, [
      (Subject.friend(_key(10)), const FactValue.connection(Connection.udp)),
    ]);

    final backedUp = await backup({linked});
    expect(backupAccounts(backedUp.tables).values, [null]);
    expect(await restoreBackup(target, backedUp, {linked.value}), 1);
    final restored = await target.select(target.profiles).getSingle();
    expect(
      (restored.home, restored.publicKey, restored.secretKey),
      (home, _key(5), SecretKey(Uint8List(32)..fillRange(0, 32, 5))),
    );
    expect(await target.select(target.liveFacts).get(), isEmpty);
  });

  test("a file the backup didn't bring is left to download again", () async {
    final kept = File('${Directory.systemTemp.createTempSync().path}/cat.png')
      ..writeAsStringSync('meow');
    for (final path in [kept.path, '/gone/dog.png']) {
      await source.addTransfer(
        TransfersCompanion.insert(
          profileId: alice,
          graph: GraphId.friend(_key(1), _key(2)),
          incoming: true,
          name: path,
          size: 4,
          path: path,
          state: FileState.done,
        ),
      );
    }

    await restoreBackup(target, await backup({alice}), {alice.value});
    expect(
      [for (final t in await target.select(target.transfers).get()) t.path],
      [kept.path],
    );
  });

  test('exports every table', () async {
    expect({
      ...(await backup()).tables.keys,
      'live_facts',
    }, unorderedEquals(source.allTables.map((t) => t.actualTableName)));
  });

  test('exports only the chosen accounts', () async {
    final (version: _, :tables) = await backup({bob});
    expect(backupAccounts(tables).values, ['Bob']);
    expect(
      {for (final e in tables['sync_events']) e['profile_id']},
      {bob.value},
    );
    expect(tables['sync_events'], hasLength(7));
  });

  test('adds the chosen accounts next to existing ones', () async {
    final carol = await _addAccount(target, 'Carol', 5);
    await target.signIn(carol);
    expect(await restoreBackup(target, await backup(), {bob.value}), 1);

    final profiles = await target.select(target.profiles).get();
    expect([for (final p in profiles) p.settings.nickname], ['Carol', 'Bob']);
    expect((await target.watchAppSettings().first).currentProfile, carol);

    final restored = profiles.last.id;
    final account = await _account(target, restored);
    expect(account.friends[_key(4)]?.name, "Bob's friend");
    expect(account.read, hasLength(1));
    expect(await _said(target, restored, _key(4)), ['Hi Bob', 'Reply']);
  });

  test('skips accounts that are already there', () async {
    final backedUp = await backup();
    await restoreBackup(target, backedUp, {alice.value, bob.value});
    expect(await restoreBackup(target, backedUp, {alice.value, bob.value}), 0);
    expect(await target.select(target.syncEvents).get(), hasLength(14));
  });

  test('restores a backup from an older or newer schema', () async {
    final backedUp = await backup({alice});
    final profile = (backedUp.tables['profiles'] as List).single as Map;
    profile['removed_column'] = 1;
    profile.remove('signed_in');

    await restoreBackup(target, backedUp, {alice.value});
    final restored = await target.select(target.profiles).getSingle();
    expect(restored.settings.nickname, 'Alice');
    expect(restored.signedIn, isFalse);
  });

  test('other files are not backups', () {
    expect(readBackup(Uint8List.fromList([0, 0, 0, 0, 0x1f, 0x1b])), isNull);
  });

  test('a backup is encrypted with the password', () async {
    final lib = tox_lib.ToxLibrary(
      malloc,
      gen.ToxFfi(DynamicLibrary.open('linux/vendored/libtoxcore.so')),
    );
    final backup = await exportBackup(source, {alice});
    final encrypted = passEncrypt(lib, backup, 'secret');

    expect(isToxSaveEncrypted(lib, encrypted), isTrue);
    expect(decryptToxSave(lib, encrypted, 'secret'), backup);
  });
}
