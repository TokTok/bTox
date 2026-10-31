import 'package:btox/models/content.dart';
import 'package:btox/models/id.dart';
import 'package:btox/providers/drafts.dart';
import 'package:btox/providers/map_tile.dart';
import 'package:btox/widgets/attachment_selector.dart';
import 'package:btox/widgets/chat_location_bubble.dart';
import 'package:btox/widgets/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_tile_provider.dart';
import '../mocks/test_app.dart';

void main() {
  late List<Content> sent;
  late ChatDraft draft;
  var sending = true;

  Future<void> pumpInput(WidgetTester tester, {Content? replyingTo}) async {
    sent = [];
    sending = true;
    draft = ChatDraft();
    draft.replyingTo.value = replyingTo;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          resizeToAvoidBottomInset: false,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageInput(
              profile: const Id(1),
              hintText: '',
              draft: draft,
              recentEmojis: false,
              onSend: (content) async {
                if (sending) {
                  sent.add(content);
                }
                return sending;
              },
            ),
          ),
        ),
        overrides: [
          mapTileProvider.overrideWith((ref, _) => FakeTileProvider()),
        ],
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

    // Space around the text isn't sent.
    await tester.enterText(find.byType(TextField), ' here\n');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, [location, const TextContent(text: 'here')]);
    expect(find.byType(LocationMap), findsNothing);
  });

  testWidgets('a reply quotes what it answers', (tester) async {
    await pumpInput(
      tester,
      replyingTo: const TextContent(text: 'Are we on\nfor Saturday?'),
    );
    await tester.enterText(find.byType(TextField), 'Yes!');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, [
      const TextContent(text: '> Are we on\n> for Saturday?\nYes!'),
    ]);
  });

  testWidgets('what fails to send comes back to be sent again', (tester) async {
    await pumpInput(tester);
    await attach(tester, location);
    await tester.enterText(find.byType(TextField), 'here');
    sending = false;
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(draft.text.text, 'here');
    expect(draft.attachments.value, [location]);
    expect(find.byType(LocationMap), findsOneWidget);
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

  testWidgets('a slow keyboard takes the panel\'s place', (tester) async {
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

    await tester.tap(find.byType(TextField));
    for (final height in [100.0, 200.0, 300.0]) {
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(find.byType(TextField)), field);
      keyboard(height);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getRect(find.byType(TextField)), field);
  });

  testWidgets('without a keyboard, the panel\'s place goes', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    await pumpInput(tester);
    final field = tester.getRect(find.byType(TextField));
    await tester.tap(find.byIcon(Icons.add));
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.getRect(find.byType(TextField)), field);
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.getRect(find.byType(TextField)).bottom,
      greaterThan(field.bottom),
    );
  });

  testWidgets('in landscape, a panel leaves the field its place', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize =
        const Size(640, 360) * tester.view.devicePixelRatio;
    await pumpInput(tester, replyingTo: const TextContent(text: 'a\nb\nc'));
    await attach(tester, location);
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final field = tester.getRect(find.byType(TextField));
    expect(field.top, greaterThanOrEqualTo(0));
    expect(field.bottom, lessThanOrEqualTo(360));
  });

  testWidgets('the keyboard waits for a tap on the field', (tester) async {
    await pumpInput(tester);
    final field = find.byType(EditableText);
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
  });

  testWidgets('coming back from a page leaves the field without focus', (
    tester,
  ) async {
    await pumpInput(tester);
    final field = find.byType(EditableText);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
  });

  testWidgets(
    'on a desktop, coming back from a page leaves the field focused',
    variant: TargetPlatformVariant.desktop(),
    (tester) async {
      await pumpInput(tester);
      final field = find.byType(EditableText);
      await tester.tap(find.byType(TextField));
      await tester.pump();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    },
  );

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
