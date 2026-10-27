// The analyzer resolves ToxLibrary's conditional export to the stub.
// ignore_for_file: argument_type_not_assignable

import 'dart:ffi' show DynamicLibrary;
import 'dart:typed_data';

import 'package:btox/btox_app.dart';
import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart' as gen;
import 'package:btox/ffi/tox_library.ffi.dart' as tox_lib;
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/contact_list_page.dart';
import 'package:btox/pages/create_profile_page.dart';
import 'package:btox/pages/link_account_page.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'mocks/fake_bootstrap_nodes.dart';
import 'mocks/fake_toxcore.dart';
import 'mocks/settle.dart';

void main() {
  testWidgets('creating a profile from Select Profile opens it', (
    tester,
  ) async {
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
          tox_lib.toxFfiProvider.overrideWith(
            (ref) => tox_lib.ToxLibrary(
              malloc,
              gen.ToxFfi(DynamicLibrary.open('linux/vendored/libtoxcore.so')),
            ),
          ),
          toxProvider.overrideWith((ref, args) => tox),
        ],
        child: const BtoxApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('createProfileButton')));
    await tester.tap(find.byKey(const Key('createProfileButton')));
    await settle(
      tester,
      until: () => find.byType(ContactListPage).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(find.byType(CreateProfilePage), findsNothing);
    expect(find.byType(ContactListPage), findsOneWidget);
    final profiles = (await tester.runAsync(
      () => db.select(db.profiles).get(),
    ))!;
    expect(profiles.map((p) => (p.settings.nickname, p.signedIn)), [
      ('Old', false),
      ('Yanciman', true),
    ]);
    expect(profiles.last.publicKey, isNot(profiles.first.publicKey));

    tox.kill();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
  });

  testWidgets('new and linked profiles fit a small screen with the keyboard '
      'open and large text', (tester) async {
    addTearDown(tester.view.reset);
    tester.view
      ..physicalSize = const Size(360, 560) * tester.view.devicePixelRatio
      ..viewInsets = FakeViewPadding(
        bottom: 300 * tester.view.devicePixelRatio,
      );
    for (final (page, button) in [
      (const CreateProfilePage(), find.byKey(const Key('createProfileButton'))),
      (const LinkAccountPage(), find.widgetWithText(FilledButton, 'Link')),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: page,
          ),
        ),
      );
      await tester.ensureVisible(button);
      await tester.pump();
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(260));
    }
  });
}
