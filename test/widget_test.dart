import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:btox/btox_app.dart';
import 'package:btox/db/database.dart';

// The database can't be constructed/torn down in the Flutter test framework
// setUp and tearDown functions as that leads to leaks being reported due to
// Drift's timers being created during the test and then only torn down during
// the tearDown after being reported as leaks at the test end.
void main() {
  final String allZeroToxId =
      String.fromCharCodes(Iterable.generate(76, (_) => '0'.codeUnits.first));
  testWidgets('Add contact adds a contact', (WidgetTester tester) async {
    Database db = Database(NativeDatabase.memory());
    final profileId = await db.addProfile(
      ProfilesCompanion.insert(
        active: Value(true),
        settings: ProfileSettings(
          nickname: 'Yeetman',
          statusMessage: 'Yeeting everyone',
        ),
      ),
    );

    expect(profileId.value, 1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) => db)],
        child: const BtoxApp(),
      ),
    );

    // Wait for the database to be loaded.
    await tester.pumpAndSettle();

    // Take a screenshot.
    await expectLater(find.byType(BtoxApp), matchesGoldenFile('btox_app.png'));

    // Check that no contact with all 0s for the public key exists.
    expect(find.textContaining('00000000'), findsNothing);

    // Navigate to the 'add contact' screen.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    // Fill in the contact data.
    await tester.enterText(find.byKey(const Key('toxId')), allZeroToxId);
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Verify that the contact appeared.
    expect(find.textContaining('00000000'), findsOneWidget);

    await db.close();
  });
}
