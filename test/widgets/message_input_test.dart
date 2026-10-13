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
          home: Scaffold(
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
    await tester.tap(find.byIcon(Icons.add_circle));
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
    expect(find.byIcon(Icons.add_circle), findsOneWidget);
    expect(sent, isEmpty);
  });
}
