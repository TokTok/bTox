import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/widgets/chat_file_bubble.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an offered file can be accepted', (tester) async {
    final db = Database(NativeDatabase.memory());
    final friend = PublicKey(Uint8List.fromList(List.filled(32, 1)));
    // Drift doesn't progress in the test's fake async zone.
    final id = (await tester.runAsync(() async {
      final profile = await db.addProfile(
        ProfilesCompanion.insert(
          settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );
      final contact = await db.addContact(
        ContactsCompanion.insert(profileId: profile, publicKey: friend),
      );
      return db.addMessage(
        MessagesCompanion.insert(
          contactId: contact,
          author: friend,
          sha: Sha256(Uint8List(32)),
          timestamp: DateTime(2026),
          content: const FileContent(name: 'notes.txt', size: 2048),
          fileState: const Value(FileState.offered),
        ),
      );
    }))!;

    Future<void> show() async {
      final message = await tester.runAsync(() => db.getMessage(id));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) => db)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: ChatFileBubble(
              message: message!,
              isSender: false,
              color: Colors.white,
              textStyle: const TextStyle(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.runAsync(pumpEventQueue);
    await show();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Accept'), findsNothing);

    await tester.runAsync(() => db.setFileState(id, FileState.cancelled));
    await show();
    expect(find.text('Cancelled'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
