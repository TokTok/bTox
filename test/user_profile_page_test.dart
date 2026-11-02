import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/user_profile_page.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/widgets/avatar.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mocks/fake_file_picker.dart';
import 'mocks/png.dart';
import 'mocks/settle.dart';
import 'mocks/test_app.dart';

final _picture = find.descendant(
  of: find.byType(Avatar),
  matching: find.byType(Image),
);

void main() {
  late Database db;
  late Id<Profiles> profileId;

  setUp(() async {
    db = Database(NativeDatabase.memory());
    profileId = await db.addProfile(
      ProfilesCompanion.insert(
        settings: ProfileSettings(nickname: 'bTox', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: PublicKey(Uint8List(32)),
        nospam: ToxAddressNospam(0),
      ),
    );
  });

  Future<BlobId?> avatar() async =>
      (await db.watchProfile(profileId).first).settings.avatar;

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      testApp(
        UserProfilePage(profileId: profileId),
        overrides: [databaseProvider.overrideWith((ref) => db)],
      ),
    );
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.runAsync(db.close);
  }

  testWidgets('shows the chosen picture until it is removed', (tester) async {
    FilePicker.platform = FakeFilePicker(
      await tester.runAsync(() => png(600, 400)),
    );
    await show(tester);
    expect(find.byType(CircleIdenticon), findsOneWidget);

    await tester.tap(find.text('Choose picture'));
    await settle(tester, until: () => _picture.evaluate().isNotEmpty);
    final blob = (await tester.runAsync(avatar))!;
    expect(
      await tester.runAsync(() => db.getAvatar(profileId, blob)),
      isNotNull,
    );
    expect(find.byType(CircleIdenticon), findsNothing);

    await tester.tap(find.text('Remove picture'));
    await settle(
      tester,
      until: () => find.byType(CircleIdenticon).evaluate().isNotEmpty,
    );
    expect(await tester.runAsync(avatar), isNull);
    expect(find.text('Remove picture'), findsNothing);
    await done(tester);
  });

  testWidgets('refuses what is no picture', (tester) async {
    FilePicker.platform = FakeFilePicker(Uint8List.fromList([1, 2, 3]));
    await show(tester);

    await tester.tap(find.text('Choose picture'));
    await settle(
      tester,
      until: () =>
          find.text("This picture can't be used").evaluate().isNotEmpty,
    );
    expect(await tester.runAsync(avatar), isNull);
    await done(tester);
  });

  testWidgets('shows no avatar with too many pixels', (tester) async {
    await tester.runAsync(() async {
      final bytes = await png(4096, 1025);
      final blob = BlobId(Uint8List(32));
      await db.setAvatar(profileId, blob, bytes);
      await db.updateProfileSettings(
        profileId,
        (s) => s.copyWith(avatar: blob),
      );
    });
    await show(tester);

    expect(find.text('Remove picture'), findsOneWidget);
    expect(find.byType(CircleIdenticon), findsOneWidget);
    expect(_picture, findsNothing);
    await done(tester);
  });
}
