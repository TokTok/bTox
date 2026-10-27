import 'package:btox/api/toxcore/tox_constants.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/widgets/friend_request_message_field.dart';
import 'package:btox/widgets/nickname_field.dart';
import 'package:btox/widgets/status_message_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a text longer than Tox takes is refused, as Tox counts it in '
      'UTF-8 bytes', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    for (final (field, key, max) in [
      (
        NicknameField(controller: controller),
        'nicknameField',
        toxMaxNameLength,
      ),
      (
        StatusMessageField(controller: controller),
        'statusMessageField',
        toxMaxStatusMessageLength,
      ),
      (
        FriendRequestMessageField(
          controller: controller,
          onEditingComplete: () {},
        ),
        'friendRequestMessageField',
        toxMaxFriendRequestLength,
      ),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: SingleChildScrollView(child: field)),
        ),
      );
      Future<bool> refuses(String text) async {
        await tester.enterText(find.byKey(Key(key)), text);
        await tester.pump();
        return tester
                .widget<TextField>(find.byType(TextField))
                .decoration
                ?.errorText !=
            null;
      }

      // Two bytes each.
      expect(await refuses('é' * (max ~/ 2)), isFalse, reason: key);
      expect(await refuses('é' * (max ~/ 2 + 1)), isTrue, reason: key);
    }
  });
}
