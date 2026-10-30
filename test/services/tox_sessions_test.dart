// The analyzer resolves ToxLibrary's conditional export to the stub.
// ignore_for_file: argument_type_not_assignable

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_options.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart' as gen;
import 'package:btox/ffi/tox_library.ffi.dart' as tox_lib;
import 'package:btox/ffi/toxcore.dart' show Tox_Savedata_Type, Toxcore;
import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/attachments.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/services/tox_session.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/store.dart';
import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

const _timeout = Duration(seconds: 60);

/// Alice and Bob, signed in side by side, as friends. They find each other
/// through local discovery. Their chats with each other come last.
Future<(Database, Directory, Id<Profiles>, Id<Profiles>, GraphId, GraphId)>
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
    // Offline, only for the public key.
    final keys = Toxcore(
      lib,
      ToxOptions(
        udpEnabled: false,
        localDiscoveryEnabled: false,
        savedata: secretKey.bytes,
        savedataType: Tox_Savedata_Type.TOX_SAVEDATA_TYPE_SECRET_KEY,
      ),
    );
    final address = ToxAddress.of(keys.selfGetPublicKey(), nospam);
    keys.kill();
    final id = await db.addProfile(
      ProfilesCompanion.insert(
        signedIn: const Value(true),
        settings: ProfileSettings(nickname: name, statusMessage: ''),
        secretKey: secretKey,
        publicKey: address.publicKey,
        nospam: nospam,
      ),
    );
    final tox = await container.read(toxProvider(secretKey, nospam).future);
    expect(tox.selfGetAddress(), address);
    return (id, address);
  }

  final (alice, aliceAddress) = await signIn('Alice', 1);
  final (bob, bobAddress) = await signIn('Bob', 2);
  expect(container.read(toxSessionsProvider).keys, {alice, bob});

  await db.addIntent(
    alice,
    WantFriend(
      pk: bobAddress.publicKey,
      requestMessage: 'hi Bob',
      nospam: bobAddress.nospam,
    ),
  );
  await db
      .watchSyncEvents(bob, GraphId.account(bobAddress.publicKey))
      .map((events) => AccountState.of(rankOrder(events)))
      .firstWhere(
        (account) =>
            account.friends[aliceAddress.publicKey]?.request == 'hi Bob',
      )
      .timeout(_timeout);
  await db.addIntent(bob, WantFriend(pk: aliceAddress.publicKey));
  return (
    db,
    dir,
    alice,
    bob,
    GraphId.friend(aliceAddress.publicKey, bobAddress.publicKey),
    GraphId.friend(bobAddress.publicKey, aliceAddress.publicKey),
  );
}

Future<List<EventContent>> _until(
  Database db,
  Id<Profiles> profile,
  GraphId graph,
  bool Function(List<EventContent>) done,
) => db
    .watchSyncEvents(profile, graph)
    .map((events) => [for (final (_, e) in rankOrder(events)) e.content])
    .firstWhere(done)
    .timeout(_timeout);

void main() {
  test('signed-in profiles run side by side and talk', () async {
    final (db, _, alice, bob, toBob, toAlice) = await _friends();

    await db.addSend(alice, toBob, 'hello from Alice');
    final received = await _until(
      db,
      bob,
      toAlice,
      (contents) => contents.any((c) => c is Received),
    );
    expect(
      utf8.decode(received.whereType<Received>().single.message),
      'hello from Alice',
    );
    await _until(
      db,
      alice,
      toBob,
      (contents) => contents.any((c) => c is Delivered),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('files arrive, larger ones once accepted', () async {
    final (db, dir, alice, bob, toBob, _) = await _friends();
    final random = Random(42);
    Future<String> send(String name, int size) async {
      final path = '${dir.path}/out_$name';
      await File(path)
          .writeAsBytes([for (var i = 0; i < size; i++) random.nextInt(256)]);
      await db.addTransfer(
        TransfersCompanion.insert(
          profileId: alice,
          graph: toBob,
          incoming: false,
          name: name,
          size: size,
          path: path,
          state: FileState.active,
        ),
      );
      return path;
    }

    Future<Transfer> bobs(bool Function(Transfer) until) async =>
        (await db
                .watchTransfers(bob)
                .firstWhere((transfers) => transfers.any(until))
                .timeout(_timeout))
            .firstWhere(until);

    final small = await send('small.bin', 100 * 1024);
    final smallDone = await bobs((t) => t.state == FileState.done);
    expect(
      await File(smallDone.path).readAsBytes(),
      await File(small).readAsBytes(),
    );

    await db.updateAppSettings(
      const AppSettingsCompanion(autoAcceptFileSize: Value(50 * 1024)),
    );
    final large = await send('large.bin', 100 * 1024);
    final offer = await bobs((t) => t.state == FileState.offered);
    expect(offer.name, 'large.bin');
    await db.setTransferState(offer.id, FileState.active);

    final largeDone = await bobs(
      (t) => t.id == offer.id && t.state == FileState.done,
    );
    expect(
      await File(largeDone.path).readAsBytes(),
      await File(large).readAsBytes(),
    );
    await db
        .watchTransfers(alice)
        .firstWhere(
          (transfers) =>
              transfers.where((t) => t.state == FileState.done).length == 2,
        )
        .timeout(_timeout);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
