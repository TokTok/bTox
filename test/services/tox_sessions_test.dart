// The analyzer resolves ToxLibrary's conditional export to the stub.
// ignore_for_file: argument_type_not_assignable

import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart' as gen;
import 'package:btox/ffi/tox_library.ffi.dart' as tox_lib;
import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/messaging.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/attachments.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/services/tox_session.dart';
import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _timeout = Duration(seconds: 60);

/// Alice and Bob, signed in side by side, as friends. They find each other
/// through local discovery.
Future<
  (Database, Directory, Id<Profiles>, PublicKey, Id<Contacts>, Id<Contacts>)
>
_friends() async {
  final db = Database(NativeDatabase.memory());
  final dir = await Directory.systemTemp.createTemp('btox_files');
  final lib = tox_lib.ToxLibrary(
    malloc,
    gen.ToxFfi(DynamicLibrary.open('linux/vendored/libtoxcore.so')),
  );
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => db),
      tox_lib.toxFfiProvider.overrideWith((ref) => lib),
      attachmentsDirectoryProvider.overrideWith((ref) => dir.path),
      bootstrapNodesProvider.overrideWith(
        (ref, network) => Stream.value(const BootstrapNodeList(nodes: [])),
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
  container.listen(toxSessionsProvider, (_, _) {});

  final nospam = ToxAddressNospam(0);
  Future<(Id<Profiles>, ToxAddress)> signIn(String name, int seed) async {
    final secretKey = SecretKey(Uint8List.fromList(List.filled(32, seed)));
    final id = await db.addProfile(
      ProfilesCompanion.insert(
        signedIn: const Value(true),
        settings: ProfileSettings(nickname: name, statusMessage: ''),
        secretKey: secretKey,
        publicKey: PublicKey(Uint8List(32)),
        nospam: nospam,
      ),
    );
    final tox = await container.read(toxProvider(secretKey, nospam).future);
    return (id, tox.selfGetAddress());
  }

  final (alice, aliceAddress) = await signIn('Alice', 1);
  final (bob, bobAddress) = await signIn('Bob', 2);
  expect(container.read(toxSessionsProvider).keys, {alice, bob});

  final bobContact = await db.addContact(
    ContactsCompanion.insert(
      profileId: alice,
      publicKey: bobAddress.publicKey,
      friendRequestAddress: Value(bobAddress),
      friendRequestMessage: const Value('hi Bob'),
    ),
  );
  final request = await db
      .watchFriendRequestsFor(bob)
      .firstWhere((requests) => requests.isNotEmpty)
      .timeout(_timeout);
  expect(request.single.publicKey, aliceAddress.publicKey);
  final aliceContact = await db.acceptFriendRequest(request.single);
  return (db, dir, alice, aliceAddress.publicKey, bobContact, aliceContact);
}

Future<Id<Messages>> _send(
  Database db,
  Id<Contacts> to,
  PublicKey from,
  Content content,
) => db.addMessage(
  newMessage(
    contactId: to,
    parent: null,
    merged: null,
    author: from,
    timestamp: DateTime.now().toUtc(),
    content: content,
  ).copyWith(
    delivered: const Value(false),
    fileState: Value.absentIfNull(
      content is FileContent ? FileState.active : null,
    ),
  ),
);

void main() {
  test('signed-in profiles run side by side and talk', () async {
    final (db, _, _, alice, bobContact, aliceContact) = await _friends();

    final message = await _send(
      db,
      bobContact,
      alice,
      const TextContent(text: 'hello from Alice'),
    );
    final received = await db
        .watchMessagesFor(aliceContact)
        .firstWhere((messages) => messages.isNotEmpty)
        .timeout(_timeout);
    expect((received.single.content as TextContent).text, 'hello from Alice');
    await db
        .watchMessagesFor(bobContact)
        .firstWhere((messages) => messages.single.delivered == true)
        .timeout(_timeout);
    expect((await db.getMessage(message)).delivered, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('files arrive, larger ones once accepted', () async {
    final (db, dir, _, alice, bobContact, aliceContact) = await _friends();
    final random = Random(42);
    Future<FileContent> file(String name, int size) async {
      final path = '${dir.path}/out_$name';
      await File(path)
          .writeAsBytes([for (var i = 0; i < size; i++) random.nextInt(256)]);
      return FileContent(name: name, size: size, path: path);
    }

    Future<Message> bobsFile(bool Function(Message) until) async =>
        (await db
                .watchMessagesFor(aliceContact)
                .firstWhere((messages) => messages.any(until))
                .timeout(_timeout))
            .firstWhere(until);

    final small = await file('small.bin', 100 * 1024);
    await _send(db, bobContact, alice, small);
    final smallDone = await bobsFile((m) => m.fileState == FileState.done);
    final smallPath = (smallDone.content as FileContent).path;
    expect(
      await File(smallPath).readAsBytes(),
      await File(small.path).readAsBytes(),
    );

    await db.updateAppSettings(
      const AppSettingsCompanion(autoAcceptFileSize: Value(50 * 1024)),
    );
    final large = await file('large.bin', 100 * 1024);
    final sent = await _send(db, bobContact, alice, large);
    final offer = await bobsFile((m) => m.fileState == FileState.offered);
    expect((offer.content as FileContent).name, 'large.bin');
    await db.setFileState(offer.id, FileState.active);

    final largeDone = await bobsFile(
      (m) => m.id == offer.id && m.fileState == FileState.done,
    );
    expect(
      await File((largeDone.content as FileContent).path).readAsBytes(),
      await File(large.path).readAsBytes(),
    );
    await db
        .watchMessagesFor(bobContact)
        .firstWhere((m) => m.any((m) => m.id == sent && m.delivered == true))
        .timeout(_timeout);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
