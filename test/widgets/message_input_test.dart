import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/content.dart';
import 'package:btox/providers/map_tile.dart';
import 'package:btox/widgets/attachment_selector.dart';
import 'package:btox/widgets/chat_location_bubble.dart';
import 'package:btox/widgets/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_tile_provider.dart';

void main() {
  late List<Content> sent;

  Future<void> pumpInput(WidgetTester tester) async {
    sent = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapTileProvider.overrideWith((ref) => FakeTileProvider())],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: MessageInput(
              hintText: '',
              recentEmojis: false,
              onSend: sent.add,
              onTapCloseReply: () {},
            ),
          ),
        ),
      ),
    );
  }

  Future<void> attach(WidgetTester tester, Content content) async {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    tester
        .widget<AttachmentSelector>(find.byType(AttachmentSelector))
        .onSelected([content]);
    await tester.pump();
  }

  const location = LocationContent(latitude: 52.37, longitude: 4.89);

  testWidgets('attachments wait as drafts until sent with the text', (
    tester,
  ) async {
    await pumpInput(tester);
    await attach(tester, location);

    expect(sent, isEmpty);
    expect(find.byType(LocationMap), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'here');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, [location, const TextContent(text: 'here')]);
    expect(find.byType(LocationMap), findsNothing);
  });

  testWidgets('a removed draft is not sent', (tester) async {
    await pumpInput(tester);
    await attach(tester, location);

    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();

    expect(find.byType(LocationMap), findsNothing);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(sent, isEmpty);
  });

  testWidgets('a panel takes the keyboard\'s place', (tester) async {
    addTearDown(tester.view.reset);
    void keyboard(double height) => tester.view.viewInsets = FakeViewPadding(
      bottom: height * tester.view.devicePixelRatio,
    );
    keyboard(300);
    await pumpInput(tester);
    final field = tester.getRect(find.byType(TextField));

    await tester.tap(find.byIcon(Icons.add));
    keyboard(0);
    await tester.pump();
    expect(find.byType(AttachmentSelector), findsOneWidget);
    expect(tester.getRect(find.byType(TextField)), field);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.byType(AttachmentSelector), findsNothing);
    expect(tester.getRect(find.byType(TextField)), field);
    keyboard(300);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getRect(find.byType(TextField)), field);
  });

  testWidgets('back closes the panel', (tester) async {
    await pumpInput(tester);
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pump();
    expect(find.byKey(const Key('emojiPicker')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('emojiPicker')), findsNothing);
  });
}
