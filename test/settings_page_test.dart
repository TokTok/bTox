import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_Connection;
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/connection_status.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/settings_page.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/providers/database.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> _withSettingsPage(
  WidgetTester tester,
  Future<void> Function(Database db, Profile profile) body, {
  ConnectionStatus? status,
}) async {
  // Tall enough for every setting.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = Database(NativeDatabase.memory());
  // Drift doesn't progress in the test's fake async zone.
  final profile = (await tester.runAsync(() async {
    final id = await db.addProfile(
      ProfilesCompanion.insert(
        signedIn: const Value(true),
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
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        connectionStatusProvider.overrideWithValue(status),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SettingsPage(profile: profile),
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

bool _switchValue(WidgetTester tester, String title) => tester
    .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title))
    .value;

Future<ProfileSettings> _saved(
  WidgetTester tester,
  Database db,
  Profile profile,
) async => (await tester.runAsync(() async {
  await pumpEventQueue();
  return db.watchProfile(profile.id).first;
}))!.settings;

void main() {
  testWidgets('toggling stay online saves the setting', (tester) async {
    await _withSettingsPage(tester, (db, profile) async {
      expect(_switchValue(tester, 'Stay online when closed'), isTrue);

      await tester.tap(find.text('Stay online when closed'));
      final saved = await tester.runAsync(() async {
        await pumpEventQueue();
        return db.watchAppSettings().first;
      });
      expect(saved!.stayOnline, isFalse);

      await tester.pumpAndSettle();
      expect(_switchValue(tester, 'Stay online when closed'), isFalse);
    });
  });

  testWidgets('network settings are saved', (tester) async {
    await _withSettingsPage(tester, (db, profile) async {
      await tester.tap(find.text('Use UDP'));
      expect((await _saved(tester, db, profile)).network.udpEnabled, isFalse);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Proxy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SOCKS5'));
      await tester.pumpAndSettle();
      final port = find.widgetWithText(TextFormField, 'Port');
      await tester.enterText(port, '99999');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a port from 1 to 65535'), findsOneWidget);

      await tester.enterText(port, '9150');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        (await _saved(tester, db, profile)).network,
        const NetworkSettings(
          udpEnabled: false,
          proxyType: ProxyType.socks5,
          proxyPort: 9150,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SOCKS5 127.0.0.1:9150'), findsOneWidget);
      expect(_switchValue(tester, 'Use UDP'), isFalse);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Local discovery'),
            )
            .onChanged,
        isNull,
      );
    });
  });

  testWidgets('a proxy problem shows on the proxy setting', (tester) async {
    await _withSettingsPage(
      tester,
      (db, profile) async {
        expect(
          find.text("Can't reach proxy at 127.0.0.1:9050"),
          findsOneWidget,
        );
      },
      status: const ConnectionStatus(
        connection: Tox_Connection.TOX_CONNECTION_NONE,
        proxyProblem: ProxyProblem.unreachable,
        proxy: '127.0.0.1:9050',
      ),
    );
  });
}
