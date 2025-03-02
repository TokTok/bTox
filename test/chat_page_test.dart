import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/messaging.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/chat_page.dart';
import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final profile = Profile(
    id: Id(0),
    active: true,
    settings: ProfileSettings(
        nickname: 'Yeetman', statusMessage: 'Yeeting everyone.'),
    secretKey: SecretKey.fromJson(
        'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'),
    publicKey: PublicKey.fromJson(
        '0000000000000000000000000000000000000000000000000000000000000000'),
    nospam: ToxAddressNospam(0),
  );

  final contact = Contact(
    id: Id(1),
    profileId: profile.id,
    name: 'Testman',
    publicKey: PublicKey.fromJson(
        '1111111111111111111111111111111111111111111111111111111111111111'),
  );

  testWidgets('Empty chat page should display message entry box',
      (WidgetTester tester) async {
    final messages = <Message>[];

    await tester.pumpWidget(
      ProviderScope(
          child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChatPage(
          profile: profile,
          contact: Stream.value(contact),
          messages: Stream.value(messages),
        ),
      )),
    );

    await tester.pumpAndSettle();

    await expectLater(find.byType(ChatPage),
        matchesGoldenFile('goldens/chat_page/empty.png'));
  });

  testWidgets('Chat page should display messages', (WidgetTester tester) async {
    final messages = <Message>[];

    messages.add(_fakeInsertMessage(
      Id(0),
      newMessage(
        contactId: contact.id,
        parent: null,
        merged: null,
        author: contact.publicKey,
        timestamp: DateTime(2025, 1, 1, 0, 1, 12),
        content: TextContent(text: 'Happy New Year!'),
      ),
    ));
    messages.add(_fakeInsertMessage(
      Id(1),
      newMessage(
        contactId: contact.id,
        parent: messages.last,
        merged: null,
        author: profile.publicKey,
        timestamp: DateTime(2025, 1, 1, 0, 2, 23),
        content: TextContent(text: 'Thank you! Happy New Year to you too!'),
      ),
    ));

    await tester.pumpWidget(
      ProviderScope(
          child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChatPage(
          profile: profile,
          contact: Stream.value(contact),
          messages: Stream.value(messages),
        ),
      )),
    );

    await tester.pumpAndSettle();

    await expectLater(find.byType(ChatPage),
        matchesGoldenFile('goldens/chat_page/messages.png'));
  });

  testWidgets('Long messages should be shown in a big bubble',
      (WidgetTester tester) async {
    final messages = <Message>[];

    messages.add(_fakeInsertMessage(
      Id(0),
      newMessage(
        contactId: contact.id,
        parent: null,
        merged: null,
        author: profile.publicKey,
        timestamp: DateTime(2025, 1, 1, 0, 1, 12),
        content: TextContent(text: 'Here is a long message.\n' * 10),
      ),
    ));

    await tester.pumpWidget(
      ProviderScope(
          child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChatPage(
          profile: profile,
          contact: Stream.value(contact),
          messages: Stream.value(messages),
        ),
      )),
    );

    await tester.pumpAndSettle();

    await expectLater(find.byType(ChatPage),
        matchesGoldenFile('goldens/chat_page/messages_long.png'));
  });

  testWidgets('Tapping a message shows the time', (WidgetTester tester) async {
    final messages = <Message>[];

    messages.add(_fakeInsertMessage(
      Id(0),
      newMessage(
        contactId: contact.id,
        parent: null,
        merged: null,
        author: contact.publicKey,
        timestamp: DateTime(2025, 1, 1, 0, 1, 12),
        content: TextContent(text: 'Happy New Year!'),
      ),
    ));

    await tester.pumpWidget(
      ProviderScope(
          child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChatPage(
          profile: profile,
          contact: Stream.value(contact),
          messages: Stream.value(messages),
        ),
      )),
    );

    await tester.pumpAndSettle();

    // Tap the message.
    // TODO(iphydf): This is a hack. Find a better way to tap the message.
    final bubble = find.byType(GestureDetector).first.evaluate().first.widget
        as GestureDetector;
    bubble.onTap!();

    await tester.pumpAndSettle();

    await expectLater(find.byType(ChatPage),
        matchesGoldenFile('goldens/chat_page/messages_time.png'));
  });

  testWidgets('Tapping smiley shows emoji picker', (WidgetTester tester) async {
    final messages = <Message>[];

    await tester.pumpWidget(
      ProviderScope(
          child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChatPage(
          profile: profile,
          contact: Stream.value(contact),
          messages: Stream.value(messages),
          recentEmojis: false,
        ),
      )),
    );

    await tester.pumpAndSettle();

    // Tap the smiley.
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();

    await expectLater(find.byType(ChatPage),
        matchesGoldenFile('goldens/chat_page/emoji_picker.png'));

    // Tap the smiley again to close the emoji picker.
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();

    await expectLater(find.byType(ChatPage),
        matchesGoldenFile('goldens/chat_page/emoji_picker_closed.png'));
  });

  testWidgets('Tapping an emoji in the emoji picker puts an emoji in the input',
      (WidgetTester tester) async {
    final messages = <Message>[];

    await tester.pumpWidget(
      ProviderScope(
          child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChatPage(
          profile: profile,
          contact: Stream.value(contact),
          messages: Stream.value(messages),
          recentEmojis: false,
        ),
      )),
    );

    await tester.pumpAndSettle();

    // Tap the smiley.
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();

    // Tap the emoji.
    await tester.tap(find.text('😀'));
    await tester.pumpAndSettle();

    await expectLater(find.byType(ChatPage),
        matchesGoldenFile('goldens/chat_page/emoji_picker_tapped.png'));
  });

  testWidgets('Sending a single emoji shows a big emoji',
      (WidgetTester tester) async {
    final messages = <Message>[
      _fakeInsertMessage(
        Id(0),
        newMessage(
          contactId: contact.id,
          parent: null,
          merged: null,
          author: profile.publicKey,
          timestamp: DateTime(2025, 1, 1, 0, 1, 12),
          content: TextContent(text: '😀'),
        ),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
          child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChatPage(
          profile: profile,
          contact: Stream.value(contact),
          messages: Stream.value(messages),
          recentEmojis: false,
        ),
      )),
    );

    await tester.pumpAndSettle();

    await expectLater(find.byType(ChatPage),
        matchesGoldenFile('goldens/chat_page/emoji_sent.png'));
  });

  testWidgets('Long-pressing a message shows a context menu',
      (WidgetTester tester) async {
    final messages = <Message>[];

    messages.add(_fakeInsertMessage(
      Id(0),
      newMessage(
        contactId: contact.id,
        parent: null,
        merged: null,
        author: contact.publicKey,
        timestamp: DateTime(2025, 1, 1, 0, 1, 12),
        content: TextContent(text: 'Happy New Year!'),
      ),
    ));

    await tester.pumpWidget(
      ProviderScope(
          child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ChatPage(
          profile: profile,
          contact: Stream.value(contact),
          messages: Stream.value(messages),
        ),
      )),
    );

    await tester.pumpAndSettle();

    // Long-press the message.
    await tester.longPress(find.byType(ChatTextBubble));
    await tester.pumpAndSettle();

    // MaterialApp instead of ChatPage because the context menu is a separate
    // route and is displayed on top of the ChatPage, not inside it.
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/chat_page/message_context_menu.png'));
  });
}

Message _fakeInsertMessage(Id<Messages> id, MessagesCompanion message) {
  return Message(
    id: id,
    contactId: message.contactId.value,
    parent: message.parent.value,
    merged: message.merged.value,
    author: message.author.value,
    sha: message.sha.value,
    timestamp: message.timestamp.value,
    content: message.content.value,
  );
}
