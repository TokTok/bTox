import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/contact_list_page.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mocks/fake_tox_constants.dart';

void main() {
  testWidgets('friend requests can be accepted, rejected, then deleted', (
    tester,
  ) async {
    final db = Database(NativeDatabase.memory());
    final alice = PublicKey(Uint8List.fromList(List.filled(32, 1)));
    final bob = PublicKey(Uint8List.fromList(List.filled(32, 2)));
    // Drift doesn't progress in the test's fake async zone.
    await tester.runAsync(() async {
      final profileId = await db.addProfile(
        ProfilesCompanion.insert(
          active: const Value(true),
          settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );
      for (final (key, message) in [(alice, 'Hi, Alice here'), (bob, 'Bob')]) {
        await db.addFriendRequest(
          FriendRequestsCompanion.insert(
            profileId: profileId,
            publicKey: key,
            message: message,
            timestamp: DateTime.utc(2026),
          ),
        );
      }
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => db),
          toxConstantsProvider.overrideWith((ref) => fakeToxcoreConstants),
          connectionStatusProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const ContactListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hi, Alice here'), findsOneWidget);

    await tester.tap(find.byTooltip('Accept friend request').first);
    await tester.tap(find.byTooltip('Reject friend request').last);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Accept friend request'), findsNothing);
    expect(find.text(alice.toJson()), findsOneWidget);
    expect(find.text(bob.toJson()), findsNothing);

    await tester.longPress(find.text(alice.toJson()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text(alice.toJson()), findsNothing);
    expect(find.text('Contact "Unknown" deleted'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
  });
}
