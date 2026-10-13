// The analyzer resolves ToxLibrary's conditional export to the stub.
// ignore_for_file: argument_type_not_assignable

import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart' as gen;
import 'package:btox/ffi/tox_library.ffi.dart' as tox_lib;
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/services/backup.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

PublicKey _key(int n) => PublicKey(Uint8List.fromList(List.filled(32, n)));

/// An account with a friend, two messages (the second a reply to the
/// first) and the first one read.
Future<Id<Profiles>> _addAccount(Database db, String name, int key) async {
  final id = await db.addProfile(
    ProfilesCompanion.insert(
      settings: ProfileSettings(nickname: name, statusMessage: ''),
      secretKey: SecretKey(Uint8List(32)),
      publicKey: _key(key),
      nospam: ToxAddressNospam(0),
    ),
  );
  final contact = await db.addContact(
    ContactsCompanion.insert(
      profileId: id,
      publicKey: _key(key + 1),
      name: Value("$name's friend"),
    ),
  );
  MessagesCompanion message(String text) => MessagesCompanion.insert(
    contactId: contact,
    author: _key(key + 1),
    sha: Sha256(Uint8List(32)),
    timestamp: DateTime(2026),
    content: TextContent(text: text),
  );
  final first = await db.addMessage(message('Hi $name'));
  await db.addMessage(message('Reply').copyWith(parent: Value(first)));
  await (db.update(db.contacts)..where((c) => c.id.equals(contact.value)))
      .write(ContactsCompanion(lastReadMessage: Value(first)));
  return id;
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

  Future<Map<String, dynamic>> backup([Set<Id<Profiles>>? profiles]) async =>
      readBackup(await exportBackup(source, profiles ?? {alice, bob}))!;

  test('restores everything into an empty bTox', () async {
    final tables = await backup();
    expect(await restoreBackup(target, tables, {alice.value, bob.value}), 2);
    expect(
      await exportBackup(target, {alice, bob}),
      await exportBackup(source, {alice, bob}),
    );
  });

  test('exports every table', () async {
    expect(
      (await backup()).keys,
      unorderedEquals(source.allTables.map((t) => t.actualTableName)),
    );
  });

  test('exports only the chosen accounts', () async {
    final tables = await backup({bob});
    expect(backupAccounts(tables).values, ['Bob']);
    expect([for (final c in tables['contacts']) c['name']], ["Bob's friend"]);
    expect(tables['messages'], hasLength(2));
  });

  test('adds the chosen accounts next to existing ones', () async {
    final carol = await _addAccount(target, 'Carol', 5);
    await target.signIn(carol);
    expect(await restoreBackup(target, await backup(), {bob.value}), 1);

    final profiles = await target.select(target.profiles).get();
    expect([for (final p in profiles) p.settings.nickname], ['Carol', 'Bob']);
    expect((await target.watchAppSettings().first).currentProfile, carol);

    final contact = await (target.select(
      target.contacts,
    )..where((c) => c.profileId.equals(profiles.last.id.value))).getSingle();
    expect(contact.name, "Bob's friend");
    final messages = await (target.select(
      target.messages,
    )..where((m) => m.contactId.equals(contact.id.value))).get();
    expect(messages, hasLength(2));
    expect(messages.last.parent, messages.first.id);
    expect(contact.lastReadMessage, messages.first.id);
  });

  test('skips accounts that are already there', () async {
    final tables = await backup();
    await restoreBackup(target, tables, {alice.value, bob.value});
    expect(await restoreBackup(target, tables, {alice.value, bob.value}), 0);
    expect(await target.select(target.contacts).get(), hasLength(2));
  });

  test('restores a backup from an older or newer schema', () async {
    final tables = await backup({alice});
    final contact = (tables['contacts'] as List).single as Map;
    contact['removed_column'] = 1;
    contact.remove('online');

    await restoreBackup(target, tables, {alice.value});
    final contacts = await target.select(target.contacts).get();
    expect(contacts.single.name, "Alice's friend");
    expect(contacts.single.online, isFalse);
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
