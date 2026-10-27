import 'package:btox/btox_app.dart';
import 'package:btox/db/database.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:clock/clock.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'mocks/fake_bootstrap_nodes.dart';
import 'mocks/fake_toxcore.dart';

void main() {
  final mySecretKey = SecretKey(Uint8List.fromList(List.filled(32, 0x7a)));
  final myPublicKey = PublicKey(Uint8List.fromList(List.filled(32, 0x61)));
  final myToxId = ToxAddress.fromString(
    String.fromCharCodes(Iterable.generate(76, (_) => '0'.codeUnits.first)),
  );
  // All 1s, but with a valid checksum.
  final friendToxId = ToxAddress.fromString('${'1' * 72}0000');

  testWidgets('Jump through all the screens', (WidgetTester tester) async {
    await withClock(
      Clock.fixed(DateTime(2024, 2, 14, 12, 33, 13, 456)),
      () async {
        final tox = FakeToxcore();

        // Create a database in memory.
        final Database db = Database(NativeDatabase.memory());

        final Future<ByteData> font = rootBundle.load(
          'assets/fonts/DejaVuSans.ttf',
        );

        // It's DejaVuSans, but the test wants Roboto.
        final FontLoader fontLoader = FontLoader('Roboto')..addFont(font);
        await fontLoader.load();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              bootstrapNodesProvider.overrideWith(fakeBootstrapNodesProvider),
              databaseProvider.overrideWith((ref) => db),
              newKeyPairProvider.overrideWith(
                (ref) => (mySecretKey, myPublicKey),
              ),
              toxProvider(
                mySecretKey,
                myToxId.nospam,
              ).overrideWith((ref) => tox),
            ],
            child: const BtoxApp(),
          ),
        );

        // Wait for the database to be loaded.
        await tester.pumpAndSettle();

        // Take a screenshot.
        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/entry.png'),
        );

        // Press the 'Create' button.
        await tester.tap(find.byKey(const Key('createProfileButton')));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/contact_list_empty.png'),
        );

        await tester.tap(find.byKey(const Key('addContactButton')));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/add_contact.png'),
        );

        // Fill in some letters, not done yet.
        await tester.enterText(find.byKey(const Key('toxId')), 'aaaaa');
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/add_contact_incomplete.png'),
        );

        // Fill in the rest of the letters.
        await tester.enterText(
          find.byKey(const Key('toxId')),
          friendToxId.toJson(),
        );
        // Put a too long message.
        await tester.enterText(
          find.byKey(const Key('friendRequestMessageField')),
          'This message is way too long. ' * 40,
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/add_contact_too_long_message.png'),
        );

        // Put an empty message.
        await tester.enterText(
          find.byKey(const Key('friendRequestMessageField')),
          '',
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/add_contact_empty_message.png'),
        );

        // Fill in a message.
        await tester.enterText(
          find.byKey(const Key('friendRequestMessageField')),
          'Add me on bTox!',
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/add_contact_filled.png'),
        );

        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/contact_list_one.png'),
        );

        // Open a conversation with the contact.
        await tester.tap(find.text('Unknown'));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/chat_empty.png'),
        );

        // Send a message.
        await tester.enterText(find.byKey(const Key('messageField')), 'Hello!');
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/chat_hello.png'),
        );

        // Close the chat.
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        // Open the drawer.
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/drawer.png'),
        );

        // Tap the header for the profile.
        await tester.tap(
          find.descendant(
            of: find.byType(DrawerHeader),
            matching: find.byType(ListTile),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/profile.png'),
        );

        // Change nicknameField and statusMessageField.
        await tester.enterText(find.byKey(const Key('nicknameField')), 'Alice');
        await tester.enterText(
          find.byKey(const Key('statusMessageField')),
          'Hello, world!',
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/profile_alice.png'),
        );

        // Press "Apply changes".
        await tester.tap(find.text('Apply changes'));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/profile_applied.png'),
        );

        // Close the profile page (back button).
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        // Open drawer again.
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/drawer_alice.png'),
        );

        // Click "Settings".
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/settings.png'),
        );

        // Press "Delete profile".
        await tester.scrollUntilVisible(find.text('Delete profile'), 300);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete profile'));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(BtoxApp),
          matchesGoldenFile('goldens/settings_delete.png'),
        );

        // Explicitly unmount the app to trigger disposal of Riverpod providers
        // and stop background event loops before closing the database.
        tox.kill();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        await db.close();
      },
    );
  });
}
