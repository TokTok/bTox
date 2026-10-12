import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/settings_page.dart';
import 'package:btox/providers/database.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _withSettingsPage(
  WidgetTester tester,
  Future<void> Function(Database db, Profile profile) body,
) async {
  final db = Database(NativeDatabase.memory());
  // Drift doesn't progress in the test's fake async zone.
  final profile = (await tester.runAsync(() async {
    final id = await db.addProfile(
      ProfilesCompanion.insert(
        active: const Value(true),
        settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(0),
      ),
    );
    return db.watchProfile(id).first;
  }))!;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWith((ref) => db)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SettingsPage(database: db, profile: profile),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await body(db, profile);

  // Unmount so the profile stream closes before the database.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await tester.runAsync(db.close);
}

bool _switchValue(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value;

void main() {
  testWidgets('toggling stay online saves the setting', (tester) async {
    await _withSettingsPage(tester, (db, profile) async {
      expect(_switchValue(tester), isTrue);

      await tester.tap(find.text('Stay online when closed'));
      final saved = await tester.runAsync(() async {
        await pumpEventQueue();
        return db.watchProfile(profile.id).first;
      });
      expect(saved!.settings.stayOnline, isFalse);

      await tester.pumpAndSettle();
      expect(_switchValue(tester), isFalse);
    });
  });
}
