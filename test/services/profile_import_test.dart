// The analyzer resolves ToxLibrary's conditional export to the stub.
// ignore_for_file: argument_type_not_assignable

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/btox_app.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart' as gen;
import 'package:btox/ffi/tox_library.ffi.dart' as tox_lib;
import 'package:btox/ffi/toxcore.dart' show decryptToxSave, isToxSaveEncrypted;
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/contact_list_page.dart';
import 'package:btox/pages/create_profile_page.dart';
import 'package:btox/pages/settings_page.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/services/profile_import.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/sync/store.dart';
import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../mocks/fake_bootstrap_nodes.dart';
import '../mocks/fake_toxcore.dart';
import '../mocks/settle.dart';
import '../mocks/test_app.dart';

final _lib = tox_lib.ToxLibrary(
  malloc,
  gen.ToxFfi(DynamicLibrary.open('linux/vendored/libtoxcore.so')),
);
final _friendKey = PublicKey(Uint8List.fromList(List.filled(32, 7)));

/// A profile named Alice with one friend, exported with the passphrase
/// "secret" the way other clients do.
({Uint8List save, SecretKey secretKey, PublicKey publicKey, int nospam})
_exportFromOtherClient() {
  final f = _lib.ffi;
  final err = malloc<UnsignedInt>();
  Pointer<Uint8> bytes(List<int> data) =>
      malloc<Uint8>(data.length)..asTypedList(data.length).setAll(0, data);
  Uint8List read(int length, void Function(Pointer<Uint8>) get) {
    final ptr = malloc<Uint8>(length);
    get(ptr);
    return Uint8List.fromList(ptr.asTypedList(length));
  }

  final options = f.tox_options_new(err);
  f.tox_options_set_local_discovery_enabled(options, false);
  final tox = f.tox_new(options, err);
  f.tox_options_free(options);
  f.tox_self_set_name(tox, bytes(utf8.encode('Alice')), 5, err);
  f.tox_self_set_status_message(tox, bytes(utf8.encode('Away')), 4, err);
  f.tox_friend_add_norequest(tox, bytes(_friendKey.bytes), err);
  final saveSize = f.tox_get_savedata_size(tox);
  final plain = read(saveSize, (p) => f.tox_get_savedata(tox, p));
  final result = (
    save: read(
      saveSize + f.tox_pass_encryption_extra_length(),
      (p) => f.tox_pass_encrypt(
        bytes(plain),
        saveSize,
        bytes(utf8.encode('secret')),
        6,
        p,
        err,
      ),
    ),
    secretKey: SecretKey(read(32, (p) => f.tox_self_get_secret_key(tox, p))),
    publicKey: PublicKey(read(32, (p) => f.tox_self_get_public_key(tox, p))),
    nospam: f.tox_self_get_nospam(tox),
  );
  f.tox_kill(tox);
  return result;
}

final class _FakeFilePicker extends FilePicker {
  Uint8List? bytes;

  _FakeFilePicker([this.bytes]);

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(name: 'alice.tox', size: bytes!.length, bytes: bytes),
  ]);

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    this.bytes = bytes;
    return null;
  }
}

void main() {
  test('reads and imports a save from another client', () async {
    final export = _exportFromOtherClient();

    expect(isToxSaveEncrypted(_lib, export.save), isTrue);
    expect(
      () => decryptToxSave(_lib, export.save, 'wrong'),
      throwsA(isA<ApiException>()),
    );
    final profile = readToxSave(
      _lib,
      decryptToxSave(_lib, export.save, 'secret'),
    );
    expect(profile.secretKey, export.secretKey);
    expect(profile.publicKey, export.publicKey);
    expect(profile.nospam, ToxAddressNospam(export.nospam));
    expect((profile.name, profile.statusMessage), ('Alice', 'Away'));
    expect(profile.friends, [(_friendKey, '')]);
    expect(
      () => readToxSave(_lib, Uint8List.fromList(utf8.encode('not a save'))),
      throwsA(isA<ApiException>()),
    );

    final db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await importProfile(db, profile);
    expect((await db.watchProfile(id).first).signedIn, isTrue);
    final account = AccountState.of(
      rankOrder(
        await db.watchSyncEvents(id, GraphId.account(profile.publicKey)).first,
      ),
    );
    expect(account.name, 'Alice');
    expect(account.friends.keys, [_friendKey]);
    expect(account.friends[_friendKey]?.wanted, isTrue);
    await expectLater(
      importProfile(db, profile),
      throwsA(isA<ProfileExistsException>()),
    );
  });

  testWidgets('New profile imports an encrypted profile', (tester) async {
    FilePicker.platform = _FakeFilePicker(_exportFromOtherClient().save);
    final db = Database(NativeDatabase.memory());
    final tox = FakeToxcore();
    // Drift doesn't progress in the test's fake async zone.
    await tester.runAsync(
      () => db.addProfile(
        ProfilesCompanion.insert(
          settings: ProfileSettings(nickname: 'Old', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapNodesProvider.overrideWith(fakeBootstrapNodesProvider),
          databaseProvider.overrideWith((ref) => db),
          tox_lib.toxFfiProvider.overrideWith((ref) => _lib),
          toxProvider.overrideWith((ref, args) => tox),
        ],
        child: const BtoxApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Import data'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'wrong',
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'secret',
    );
    await tester.tap(find.text('Import'));
    await settle(
      tester,
      until: () =>
          find.byType(CreateProfilePage).evaluate().isEmpty &&
          find.text('Profile "Alice" imported').evaluate().isNotEmpty,
    );
    expect(find.byType(ContactListPage), findsOneWidget);
    expect(find.text('Profile "Alice" imported'), findsOneWidget);

    tox.kill();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
  });

  testWidgets('a backup from Settings restores the chosen accounts', (
    tester,
  ) async {
    final picker = _FakeFilePicker();
    FilePicker.platform = picker;
    ProfilesCompanion profile(String name, int key) => ProfilesCompanion.insert(
      settings: ProfileSettings(nickname: name, statusMessage: ''),
      secretKey: SecretKey(Uint8List(32)),
      publicKey: PublicKey(Uint8List.fromList(List.filled(32, key))),
      nospam: ToxAddressNospam(0),
    );
    final source = Database(NativeDatabase.memory());
    final alice = await tester.runAsync(() async {
      final id = await source.addProfile(profile('Alice', 1));
      await source.addProfile(profile('Bob', 2));
      return source.watchProfile(id).first;
    });

    await tester.pumpWidget(
      testApp(
        SettingsPage(profile: alice!),
        overrides: [
          connectionStatusProvider.overrideWithValue(null),
          databaseProvider.overrideWith((ref) => source),
          tox_lib.toxFfiProvider.overrideWith((ref) => _lib),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Export data'));
    await tester.tap(find.text('Export data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(picker.bytes, isNotNull);
    await tester.pumpWidget(const SizedBox());

    final tox = FakeToxcore();
    final target = Database(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapNodesProvider.overrideWith(fakeBootstrapNodesProvider),
          databaseProvider.overrideWith((ref) => target),
          tox_lib.toxFfiProvider.overrideWith((ref) => _lib),
          toxProvider.overrideWith((ref, args) => tox),
        ],
        child: const BtoxApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Import data'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'secret',
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(find.text('1 account restored'), findsOneWidget);
    final restored = await tester.runAsync(
      () => target.select(target.profiles).get(),
    );
    expect(restored!.map((p) => p.settings.nickname), ['Alice']);

    tox.kill();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(source.close);
    await tester.runAsync(target.close);
  });
}
