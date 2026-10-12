import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/widgets/tox_id_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copies the Tox ID', (tester) async {
    final copied = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text']);
        }
        return null;
      },
    );
    final address = ToxAddress.fromString('${'1' * 72}0000');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: ToxIdView(address: address)),
      ),
    );
    await tester.tap(find.byTooltip('Copy Tox ID'));
    await tester.pump();

    expect(copied, [address.toJson()]);
    expect(find.text('Tox ID copied'), findsOneWidget);
  });
}
