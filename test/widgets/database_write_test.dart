import 'package:btox/db/database.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/widgets/database_write.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../mocks/test_app.dart';

void main() {
  testWidgets('change that fails to save informs user', (tester) async {
    final db = Database(NativeDatabase.memory());
    bool? saved;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async =>
                  saved = await ref.write(context, (_) async {
                    throw Exception('disk full');
                  }),
              child: const Text('Save'),
            ),
          ),
        ),
        overrides: [databaseProvider.overrideWith((ref) => db)],
      ),
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(find.text("Couldn't save that"), findsOneWidget);

    await tester.runAsync(db.close);
  });
}
