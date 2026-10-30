import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart' show FileState;
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/chat_page.dart';
import 'package:btox/providers/attachments.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/drafts.dart';
import 'package:btox/providers/map_tile.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/setting.dart' show PictureEncoding;
import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:btox/widgets/message_input.dart';
import 'package:btox/widgets/system_gestures.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import 'finders.dart';
import 'mocks/fake_tile_provider.dart';
import 'mocks/test_app.dart';

final _event = EventId(Uint8List(32));

void main() {
  final profile = Profile(
    id: Id(0),
    signedIn: true,
    settings: ProfileSettings(
      nickname: 'Yeetman',
      statusMessage: 'Yeeting everyone.',
    ),
    secretKey: SecretKey.fromJson(
      'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    ),
    publicKey: PublicKey.fromJson(
      '0000000000000000000000000000000000000000000000000000000000000000',
    ),
    nospam: ToxAddressNospam(0),
  );

  final contact = PublicKey.fromJson(
    '1111111111111111111111111111111111111111111111111111111111111111',
  );

  final chat = ChatRef(profile.id, GraphId.friend(profile.publicKey, contact));

  // [shown]: the chat's account is the one the app shows.
  List<Override> overrides(
    List<ChatEntry> entries, {
    bool shown = true,
    ChatSummary? summary,
  }) => [
    currentProfileProvider.overrideWithValue(shown ? profile : null),
    profileProvider(profile.id).overrideWith((ref) => Stream.value(profile)),
    chatProvider(chat).overrideWithValue(
      AsyncData(
        summary ??
            ChatSummary(ref: chat, name: 'Testman', key: contact, online: true),
      ),
    ),
    chatEntriesProvider(chat).overrideWithValue(AsyncData(entries)),
    newestEventsProvider(chat).overrideWithValue(const {}),
    pictureFormatProvider(chat).overrideWithValue(PictureEncoding.original),
  ];

  testWidgets('Empty chat page should display message entry box', (
    WidgetTester tester,
  ) async {
    final messages = <ChatEntry>[];

    await tester.pumpWidget(
      testApp(ChatPage(chat: chat), overrides: overrides(messages)),
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ChatPage),
      matchesGoldenFile('goldens/chat_page/empty.png'),
    );
  });

  testWidgets('Chat page should display messages', (WidgetTester tester) async {
    final messages = <ChatEntry>[];

    messages.add(
      ChatEntry(
        event: _event,
        mine: false,
        timestamp: DateTime(2025, 1, 1, 0, 1, 12),
        content: TextContent(text: 'Happy New Year!'),
      ),
    );
    messages.add(
      ChatEntry(
        event: EventId(Uint8List(32)..[0] = 1),
        mine: true,
        timestamp: DateTime(2025, 1, 1, 0, 2, 23),
        content: TextContent(text: 'Thank you! Happy New Year to you too!'),
        state: ChatContentState.delivered,
      ),
    );

    await tester.pumpWidget(
      testApp(ChatPage(chat: chat), overrides: overrides(messages)),
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ChatPage),
      matchesGoldenFile('goldens/chat_page/messages.png'),
    );
  });

  testWidgets('Long messages should be shown in a big bubble', (
    WidgetTester tester,
  ) async {
    final messages = <ChatEntry>[];

    messages.add(
      ChatEntry(
        event: _event,
        mine: true,
        timestamp: DateTime(2025, 1, 1, 0, 1, 12),
        content: TextContent(text: 'Here is a long message.\n' * 10),
      ),
    );

    await tester.pumpWidget(
      testApp(ChatPage(chat: chat), overrides: overrides(messages)),
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ChatPage),
      matchesGoldenFile('goldens/chat_page/messages_long.png'),
    );
  });

  testWidgets('Only the last of a run says when, until tapped', (
    WidgetTester tester,
  ) async {
    final messages = [
      for (final (minute, text) in [(1, 'Happy New Year!'), (2, 'Again!')])
        ChatEntry(
          event: EventId(Uint8List(32)..[0] = minute),
          mine: false,
          timestamp: DateTime(2025, 1, 1, 0, minute),
          content: TextContent(text: text),
        ),
    ];

    await tester.pumpWidget(
      testApp(ChatPage(chat: chat), overrides: overrides(messages)),
    );
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('12:01 AM')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('12:02 AM')), findsOneWidget);

    await tester.tap(findMessage('Happy New Year!'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('12:01 AM')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Tapping smiley shows emoji picker', (WidgetTester tester) async {
    final messages = <ChatEntry>[];

    await tester.pumpWidget(
      testApp(
        ChatPage(chat: chat, recentEmojis: false),
        overrides: overrides(messages),
      ),
    );

    await tester.pumpAndSettle();

    // Tap the smiley.
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ChatPage),
      matchesGoldenFile('goldens/chat_page/emoji_picker.png'),
    );

    // Tap the smiley again to close the emoji picker.
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ChatPage),
      matchesGoldenFile('goldens/chat_page/emoji_picker_closed.png'),
    );
  });

  testWidgets(
    'Tapping an emoji in the emoji picker puts an emoji in the input',
    (WidgetTester tester) async {
      final messages = <ChatEntry>[];

      await tester.pumpWidget(
        testApp(
          ChatPage(chat: chat, recentEmojis: false),
          overrides: overrides(messages),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the smiley.
      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pumpAndSettle();

      // Tap the emoji.
      await tester.tap(find.text('😀'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(ChatPage),
        matchesGoldenFile('goldens/chat_page/emoji_picker_tapped.png'),
      );
    },
  );

  testWidgets('Sending a single emoji shows a big emoji', (
    WidgetTester tester,
  ) async {
    final messages = <ChatEntry>[
      ChatEntry(
        event: _event,
        mine: true,
        timestamp: DateTime(2025, 1, 1, 0, 1, 12),
        content: TextContent(text: '😀'),
      ),
    ];

    await tester.pumpWidget(
      testApp(
        ChatPage(chat: chat, recentEmojis: false),
        overrides: overrides(messages),
      ),
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ChatPage),
      matchesGoldenFile('goldens/chat_page/emoji_sent.png'),
    );
  });

  testWidgets('Long-pressing a message shows a context menu', (
    WidgetTester tester,
  ) async {
    final messages = <ChatEntry>[];

    messages.add(
      ChatEntry(
        event: _event,
        mine: false,
        timestamp: DateTime(2025, 1, 1, 0, 1, 12),
        content: TextContent(text: 'Happy New Year!'),
      ),
    );

    await tester.pumpWidget(
      testApp(ChatPage(chat: chat), overrides: overrides(messages)),
    );

    await tester.pumpAndSettle();

    // Long-press the message.
    await tester.longPress(find.byType(ChatTextBubble));
    await tester.pumpAndSettle();

    // MaterialApp instead of ChatPage because the context menu is a separate
    // route and is displayed on top of the ChatPage, not inside it.
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chat_page/message_context_menu.png'),
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Not available yet'), findsOneWidget);
  });

  testWidgets('selected messages are copied in order, and back unselects', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await tester.pumpWidget(
      testApp(
        ChatPage(chat: chat),
        overrides: overrides([
          ChatEntry(
            event: _event,
            mine: false,
            timestamp: DateTime(2025, 1, 1, 0, 1),
            content: const TextContent(text: 'First'),
          ),
          ChatEntry(
            event: EventId(Uint8List(32)..[0] = 1),
            mine: true,
            timestamp: DateTime(2025, 1, 1, 0, 2),
            content: const TextContent(text: 'Second'),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    Finder message(String text) => find.textContaining(text);

    await tester.longPress(message('Second'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byType(MessageInput), findsNothing);

    await tester.tap(find.byTooltip('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'Testman: First\nYeetman: Second');
    expect(find.text('2 messages copied'), findsOneWidget);
    expect(find.text('Testman'), findsOneWidget);
    expect(find.byType(MessageInput), findsOneWidget);

    await tester.longPress(message('Second'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
    expect(find.byType(ChatPage), findsOneWidget);
  });

  testWidgets('message details show its times and sender', (tester) async {
    await tester.pumpWidget(
      testApp(
        ChatPage(chat: chat),
        overrides: overrides([
          ChatEntry(
            event: _event,
            mine: true,
            timestamp: DateTime(2025, 1, 1, 0, 1),
            content: const TextContent(text: 'Hello'),
            state: ChatContentState.delivered,
            delivered: DateTime(2025, 1, 1, 0, 2),
          ),
          ChatEntry(
            event: EventId(Uint8List(32)..[0] = 1),
            mine: false,
            timestamp: DateTime(2025, 1, 1, 0, 3),
            content: const TextContent(text: 'Hi'),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.textContaining('Hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(find.text('Message details'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.longPress(find.textContaining('Hi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('Testman\n${contact.toJson()}'), findsOneWidget);
  });

  testWidgets('a forwarded message goes to the chosen chat', (tester) async {
    final db = Database(NativeDatabase.memory());
    final other = ChatRef(
      profile.id,
      GraphId.friend(profile.publicKey, PublicKey(Uint8List(32)..[0] = 2)),
    );
    await tester.pumpWidget(
      testApp(
        ChatPage(chat: chat),
        overrides: [
          ...overrides([
            ChatEntry(
              event: _event,
              mine: false,
              timestamp: DateTime(2025, 1, 1, 0, 1),
              content: const TextContent(text: 'Pass it on'),
            ),
          ]),
          databaseProvider.overrideWith((ref) => db),
          chatsForProfileProvider(profile.id).overrideWithValue(
            AsyncData([
              ChatSummary(ref: other, name: 'Friendo', key: other.graph),
            ]),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(ChatTextBubble));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forward'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friendo'));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Message forwarded'), findsOneWidget);
    final sends = await tester.runAsync(() => db.select(db.intents).get());
    expect(
      [for (final s in sends!) (s.graph, _sent(s))],
      [(other.graph, 'Pass it on')],
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('a forwarded file goes only to friends, as a copy', (
    tester,
  ) async {
    final db = Database(NativeDatabase.memory());
    final dir = Directory.systemTemp.createTempSync('forward');
    addTearDown(() => dir.deleteSync(recursive: true));
    final notes = File('${dir.path}/notes.txt')..writeAsStringSync('notes');
    final friend = PublicKey(Uint8List(32)..[0] = 2);
    final other = ChatRef(
      profile.id,
      GraphId.friend(profile.publicKey, friend),
    );
    final group = ChatRef(
      profile.id,
      GraphId.conference(ConferenceId(Uint8List(32))),
    );
    await tester.pumpWidget(
      testApp(
        ChatPage(chat: chat),
        overrides: [
          ...overrides([
            ChatEntry(
              event: _event,
              mine: false,
              timestamp: DateTime(2025, 1, 1, 0, 1),
              content: const TextContent(text: 'Look'),
            ),
            ChatEntry(
              event: EventId(Uint8List(32)..[0] = 1),
              mine: true,
              timestamp: DateTime(2025, 1, 1, 0, 2),
              content: FileContent(
                name: 'notes.txt',
                size: 5,
                path: notes.path,
              ),
              file: const FileProgress(state: FileState.done),
            ),
          ]),
          databaseProvider.overrideWith((ref) => db),
          attachmentsDirectoryProvider.overrideWith((ref) => dir.path),
          chatsForProfileProvider(profile.id).overrideWithValue(
            AsyncData([
              ChatSummary(ref: other, name: 'Friendo', key: friend),
              ChatSummary(ref: group, name: 'Groupies', key: group.graph),
            ]),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.textContaining('Look'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Forward'));
    await tester.pumpAndSettle();
    expect(find.text('Groupies'), findsNothing);
    await tester.tap(find.text('Friendo'));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 messages forwarded'), findsOneWidget);
    final (sends, transfers) = (await tester.runAsync(
      () async => (
        await db.select(db.intents).get(),
        await db.select(db.transfers).get(),
      ),
    ))!;
    expect(
      [for (final s in sends) (s.graph, _sent(s))],
      [(other.graph, 'Look')],
    );
    final [copy] = transfers;
    expect((copy.graph, copy.name), (other.graph, 'notes.txt'));
    expect(copy.path, isNot(notes.path));
    expect(File(copy.path).readAsStringSync(), 'notes');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
  });

  testWidgets('a swipe in from the edge, as for going back, keeps the chat '
      'where it was', (tester) async {
    // Where Android's gesture navigation takes swipes, in physical pixels.
    tester.view.systemGestureInsets = const FakeViewPadding(
      left: 60,
      right: 60,
    );
    addTearDown(tester.view.resetSystemGestureInsets);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides([
            for (var i = 0; i < 40; i++)
              ChatEntry(
                event: EventId(Uint8List(32)..[0] = i),
                mine: i.isEven,
                timestamp: DateTime(2025, 1, 1, 0, i),
                content: TextContent(text: 'Message $i'),
              ),
          ]),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: leaveSystemSwipes,
          home: ChatPage(chat: chat),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byKey(const Key('messages'));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;

    final edge = tester.getRect(list).centerRight - const Offset(2, 0);
    await tester.dragFrom(edge, const Offset(-200, 40));
    await tester.pumpAndSettle();
    expect(position.pixels, 0);

    await tester.dragFrom(edge, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
  });

  testWidgets("a chat opened before the database switches to the chat's "
      'account', (tester) async {
    final db = Database(NativeDatabase.memory());
    final opened = Completer<Database>();
    await tester.pumpWidget(
      testApp(
        ChatPage(chat: chat),
        overrides: [
          ...overrides(const [], shown: false),
          databaseProvider.overrideWith((ref) => opened.future),
        ],
      ),
    );

    opened.complete(db);
    final settings = await tester.runAsync(() async {
      await pumpEventQueue();
      return db.watchAppSettings().first;
    });
    expect(settings!.currentProfile, chat.profile);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('what is being written stays, leaving or reopening the chat', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides([]),
        child: MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(),
        ),
      ),
    );
    ChatPage.open(navigator.currentState!, chat);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('messageField')), 'draft');

    // A notification for the open chat leaves it as it is.
    final route = ModalRoute.of(tester.element(find.byType(ChatPage)));
    ChatPage.open(navigator.currentState!, chat);
    await tester.pumpAndSettle();
    expect(ModalRoute.of(tester.element(find.byType(ChatPage))), route);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    ChatPage.open(navigator.currentState!, chat);
    await tester.pumpAndSettle();
    expect(find.text('draft'), findsOneWidget);
  });

  testWidgets('what is sent goes in all its parts, also when the chat '
      'closes meanwhile', (tester) async {
    final db = Database(NativeDatabase.memory());
    final opened = Completer<Database>();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides([]),
          databaseProvider.overrideWith((ref) => opened.future),
          mapTileProvider.overrideWith((ref, _) => FakeTileProvider()),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(),
        ),
      ),
    );
    ChatPage.open(navigator.currentState!, chat);
    await tester.pumpAndSettle();
    const location = LocationContent(latitude: 52.37, longitude: 4.89);
    ProviderScope.containerOf(tester.element(find.byType(ChatPage)))
        .read(chatDraftProvider(chat))
        .attachments
        .value = [
      location,
    ];
    await tester.enterText(find.byKey(const Key('messageField')), 'here');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    opened.complete(db);
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 50)),
    );
    final sends = await tester.runAsync(() => db.select(db.intents).get());
    expect(
      [for (final s in sends!) _sent(s)],
      [messageTextOf(location), 'here'],
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  ChatEntry message(int i) => ChatEntry(
    event: EventId(Uint8List(32)..[0] = i),
    mine: false,
    timestamp: DateTime(2025, 1, 1, 0, i),
    content: TextContent(text: 'message $i'),
  );
  Future<void> show(WidgetTester tester, List<ChatEntry> entries) => tester
      .pumpWidget(testApp(ChatPage(chat: chat), overrides: overrides(entries)));

  testWidgets('reading further up keeps its place as new messages come, '
      'which wait below', (tester) async {
    final entries = [for (var i = 0; i < 50; i++) message(i)];
    await show(tester, entries);
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('messages')), const Offset(0, 1000));
    await tester.pumpAndSettle();
    final shown = [
      for (var i = 0; i < 50; i++)
        if (findMessage('message $i').evaluate().isNotEmpty) i,
    ];
    final reading = findMessage('message ${shown[shown.length ~/ 2]}');
    final place = tester.getRect(reading);

    await show(tester, [...entries, message(50), message(51)]);
    await tester.pump();
    expect(tester.getRect(reading), place);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip('Newest messages'));
    await tester.pumpAndSettle();
    expect(findMessage('message 51'), findsOneWidget);
    expect(find.byTooltip('Newest messages'), findsNothing);
  });

  testWidgets('what is sent while reading further up shows at the bottom', (
    tester,
  ) async {
    final db = Database(NativeDatabase.memory());
    Future<void> show(List<ChatEntry> entries) => tester.pumpWidget(
      testApp(
        ChatPage(chat: chat),
        overrides: [
          ...overrides(entries),
          databaseProvider.overrideWith((ref) => db),
        ],
      ),
    );
    final entries = [for (var i = 0; i < 50; i++) message(i)];
    await show(entries);
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('messages')), const Offset(0, 1000));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('messageField')), 'mine');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await show([
      ...entries,
      ChatEntry(
        event: EventId(Uint8List(32)..[0] = 99),
        mine: true,
        timestamp: DateTime(2025, 1, 1, 1),
        content: const TextContent(text: 'mine'),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(findMessage('mine'), findsOneWidget);
    expect(find.byTooltip('Newest messages'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('a chat no longer a friend\'s takes no messages', (tester) async {
    await tester.pumpWidget(
      testApp(
        ChatPage(chat: chat),
        overrides: overrides([
          message(1),
        ], summary: ChatSummary(ref: chat, key: chat.graph, closed: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(findMessage('message 1'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text("You can't send messages to this chat any more"),
      findsOneWidget,
    );
  });

  testWidgets('a message keeps its state as new ones come in', (tester) async {
    await show(tester, [message(1), message(2)]);
    await tester.pumpAndSettle();
    await tester.tap(findMessage('message 2'));
    await tester.pump();
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('12:02')), findsOneWidget);

    await show(tester, [message(1), message(2), message(3)]);
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('12:02')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('calls show among the messages as they went', (tester) async {
    ChatEntry call(int i, CallContent content) => ChatEntry(
      event: EventId(Uint8List(32)..[0] = i),
      mine: !content.incoming,
      notice: true,
      timestamp: DateTime(2025, 1, 1, 0, i),
      content: content,
    );
    await show(tester, [
      call(1, const CallContent(incoming: true, ended: true)),
      call(2, const CallContent(incoming: true, video: true, ended: true)),
      call(
        3,
        const CallContent(
          incoming: false,
          video: true,
          ended: true,
          duration: Duration(hours: 1, minutes: 2, seconds: 31),
        ),
      ),
      call(4, const CallContent(incoming: true, ended: true, declined: true)),
      call(5, const CallContent(incoming: false)),
    ]);
    await tester.pumpAndSettle();

    for (final text in [
      'Missed voice call',
      'Missed video call',
      'Outgoing video call · 1:02:31',
      'Incoming voice call',
      'Voice call',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });
}

String _sent(StoredIntent intent) =>
    utf8.decode((intent.content as Send).message);
