import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/widgets/tox_id_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<String?> validate(WidgetTester tester, String toxId) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Form(
            key: formKey,
            child: ToxIdField(controller: TextEditingController(text: toxId)),
          ),
        ),
      ),
    );
    formKey.currentState!.validate();
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    return field.decoration?.errorText;
  }

  testWidgets('rejects a bad checksum', (tester) async {
    expect(await validate(tester, '${'1' * 72}0000'), isNull);
    expect(
      await validate(tester, '1' * 76),
      'Not a valid Tox ID, please check it for typos',
    );
  });
}
