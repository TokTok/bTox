import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/select_profile_page.dart';
import 'package:btox/providers/database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mocks/test_app.dart';

void main() {
  testWidgets('long-pressing a profile deletes it', (tester) async {
    final db = Database(NativeDatabase.memory());
    // Drift doesn't progress in the test's fake async zone.
    await tester.runAsync(() async {
      for (final nickname in ['Keep', 'Duplicate']) {
        await db.addProfile(
          ProfilesCompanion.insert(
            settings: ProfileSettings(nickname: nickname, statusMessage: ''),
            secretKey: SecretKey(Uint8List(32)),
            publicKey: PublicKey(Uint8List(32)),
            nospam: ToxAddressNospam(0),
          ),
        );
      }
    });

    await tester.pumpWidget(
      testApp(
        const SelectProfilePage(),
        overrides: [databaseProvider.overrideWith((ref) => db)],
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Duplicate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Duplicate'), findsNothing);
    expect(find.text('Keep'), findsOneWidget);
    expect(find.text('Profile "Duplicate" deleted'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
  });
}
