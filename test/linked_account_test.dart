// The lint takes _app's root scope for a nested one.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/chat_page.dart';
import 'package:btox/pages/contact_list_page.dart';
import 'package:btox/pages/link_account_page.dart';
import 'package:btox/pages/user_profile_page.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/message_formats.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/widgets/chat_avatar.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:btox/widgets/message_input.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'finders.dart';
import 'mocks/fake_message_format.dart';
import 'mocks/settle.dart';
import 'mocks/test_app.dart';

final _home = ToxAddress.of(
  PublicKey(Uint8List(32)..fillRange(0, 32, 1)),
  ToxAddressNospam(0x01020304),
);
final _bob = PublicKey(Uint8List(32)..fillRange(0, 32, 2));
final _carol = PublicKey(Uint8List(32)..fillRange(0, 32, 3));
final _group = GroupChatId(Uint8List(32)..fillRange(0, 32, 4));

/// Events of one graph, each after the one before.
List<(EventId, SyncEvent, Uint8List)> _chain(
  GraphId graph,
  List<EventContent Function(List<EventId>)> contents,
) {
  final events = <(EventId, SyncEvent, Uint8List)>[];
  final ids = <EventId>[];
  for (final content in contents) {
    final event = SyncEvent(
      graph: graph,
      author: _home.publicKey,
      parents: [...ids.take(1)],
      rank: ids.length,
      time: 1700000000000 + ids.length,
      content: content(ids),
    );
    final bytes = event.encode();
    final id = EventId.of(bytes);
    ids.insert(0, id);
    events.add((id, event, bytes));
  }
  return events;
}

Widget _app(Database db, Profile current, Widget home) => testApp(
  home,
  overrides: [
    databaseProvider.overrideWith((ref) => db),
    connectionStatusProvider.overrideWithValue(null),
    currentProfileProvider.overrideWithValue(current),
    knownMessageFormatsProvider.overrideWithValue(const [FakeMessageFormat()]),
  ],
);

void main() {
  testWidgets('a pairing link adds a linked profile', (tester) async {
    final db = Database(NativeDatabase.memory());
    await tester.pumpWidget(
      testApp(
        const LinkAccountPage(),
        overrides: [
          databaseProvider.overrideWith((ref) => db),
          newKeyPairProvider.overrideWith(
            (ref) => (SecretKey(Uint8List(32)), PublicKey(Uint8List(32))),
          ),
        ],
      ),
    );

    await tester.enterText(find.byKey(const Key('pairingLink')), 'nope');
    await tester.tap(find.text('Link'));
    await tester.pump();
    expect(find.text("This isn't a pairing link"), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('pairingLink')),
      'tox:${_home.toJson()}?pair=00112233445566778899aabbccddeeff',
    );
    await tester.tap(find.text('Link'));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 50)),
    );

    final profile = (await tester.runAsync(
      () => db.select(db.profiles).getSingle(),
    ))!;
    expect(profile.home, _home);
    expect(profile.signedIn, isTrue);
    expect(profile.pairingMessage, 'pair:00112233445566778899aabbccddeeff');

    // Its profile page shows the account's Tox ID.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _app(db, profile, UserProfilePage(profileId: profile.id)),
    );
    await settle(
      tester,
      until: () => find.text(_home.toJson()).evaluate().isNotEmpty,
    );
    expect(find.text('Linked account'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.runAsync(db.close);
  });

  testWidgets("a linked account's chats come from its events", (tester) async {
    final db = Database(NativeDatabase.memory());
    final friendChat = GraphId.friend(_home.publicKey, _bob);
    final profile = (await tester.runAsync(() async {
      final id = await db.addProfile(
        ProfilesCompanion.insert(
          signedIn: const Value(true),
          settings: ProfileSettings(nickname: 'bTox', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
          home: Value(_home),
        ),
      );
      await db.addSyncEvents(id, [
        ..._chain(GraphId.account(_home.publicKey), [
          (_) => const FactContent(
            subject: Subject.account(),
            value: FactValue.name('Me'),
          ),
          // The home device pairs this one as a friend.
          (_) => WantFriend(pk: PublicKey(Uint8List(32))),
          (_) => FactContent(
            subject: Subject.friend(PublicKey(Uint8List(32))),
            value: FactValue.name('This phone'),
          ),
          (_) => WantFriend(pk: _bob),
          (_) => FactContent(
            subject: Subject.friend(_bob),
            value: FactValue.name('Bob'),
          ),
          (_) => FactContent(
            subject: Subject.chat(GroupChat(_group)),
            value: FactValue.name('Tox'),
          ),
          (_) => FactContent(
            subject: Subject.chat(GroupChat(_group)),
            value: FactValue.joined(true),
          ),
          (_) => ChatInvite(
            from: _bob,
            kind: ChatKind.group,
            name: 'Secret',
            invite: Uint8List(4),
          ),
        ]),
        ..._chain(friendChat, [
          (_) => Received(
            sender: 'Bob',
            // Read by a message format that's on.
            message: FakeMessageFormat.encode('hi', '1'),
            kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
          ),
          (_) => Send(
            sender: 'Me',
            message: utf8.encode('hello'),
            kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
          ),
          (ids) => Delivered(intent: ids.first),
        ]),
        ..._chain(GraphId.group(_group), [
          (_) => const Notice(text: 'Carol joined'),
          (_) => Received(
            from: _carol,
            sender: 'Carol',
            message: utf8.encode('hey all'),
            kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
          ),
        ]),
      ]);
      await db.updateLiveFacts(id, [
        (Subject.friend(_bob), const FactValue.connection(Connection.udp)),
      ]);
      return db.select(db.profiles).getSingle();
    }))!;

    await tester.pumpWidget(_app(db, profile, const ContactListPage()));
    await settle(tester, until: () => find.text('Tox').evaluate().isNotEmpty);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Tox'), findsOneWidget);
    expect(find.text('This phone'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is ChatAvatar && w.online == true),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);
    // Bob's and the group's messages are unread.
    expect(find.text('1'), findsNWidgets(2));

    // Tox takes a group's invite once, so the password goes with the answer.
    await tester.tap(find.byTooltip('Join'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'sesame',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Join'),
      ),
    );
    await settle(
      tester,
      until: () async => (await db.select(db.intents).get()).isNotEmpty,
    );
    final [answer] = (await tester.runAsync(
      () => db.select(db.intents).get(),
    ))!;
    expect(
      answer.content,
      isA<AnswerInvite>()
          .having((a) => a.join, 'join', true)
          .having((a) => a.password, 'password', 'sesame'),
    );

    await tester.pumpWidget(
      _app(db, profile, ChatPage(chat: ChatRef(profile.id, friendChat))),
    );
    await settle(
      tester,
      until: () async => (await db.select(db.chatReads).get()).isNotEmpty,
    );
    final [read] = (await tester.runAsync(
      () => db.select(db.chatReads).get(),
    ))!;
    expect((read.graph, read.rank), (friendChat, 2));
    expect(findMessage('hi'), findsOneWidget);
    expect(findMessage('hello'), findsOneWidget);

    // Left for the background service, which writes it as an event.
    await tester.enterText(
      find.descendant(
        of: find.byType(MessageInput),
        matching: find.byType(TextField),
      ),
      'from the phone',
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await settle(
      tester,
      until: () async => (await db.select(db.intents).get()).length > 1,
    );
    final [_, send] = (await tester.runAsync(
      () => db.select(db.intents).get(),
    ))!;
    expect(send.graph, friendChat);
    expect((send.content as Send).message, utf8.encode('from the phone'));

    await tester.pumpWidget(
      _app(
        db,
        profile,
        ChatPage(chat: ChatRef(profile.id, GraphId.group(_group))),
      ),
    );
    await settle(
      tester,
      until: () => findMessage('hey all').evaluate().isNotEmpty,
    );
    expect(find.text('Carol joined'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    expect(findMessage('hey all'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.runAsync(db.close);
  });

  testWidgets("a linked group's details show the account as you", (
    tester,
  ) async {
    final db = Database(NativeDatabase.memory());
    final chat = GroupChat(_group);
    final profile = (await tester.runAsync(() async {
      final id = await db.addProfile(
        ProfilesCompanion.insert(
          signedIn: const Value(true),
          settings: ProfileSettings(nickname: 'bTox', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
          home: Value(_home),
        ),
      );
      await db.addSyncEvents(id, [
        ..._chain(GraphId.account(_home.publicKey), [
          for (final value in const [
            FactValue.name('Tox'),
            FactValue.joined(true),
            FactValue.role(Role.moderator),
            FactValue.selfName('iphy'),
          ])
            (_) => FactContent(subject: Subject.chat(chat), value: value),
        ]),
      ]);
      await db.updateLiveFacts(id, [
        (const Subject.account(), const FactValue.connection(Connection.udp)),
      ], all: true);
      return db.select(db.profiles).getSingle();
    }))!;

    await tester.pumpWidget(
      _app(db, profile, ChatPage(chat: ChatRef(profile.id, chat.graph))),
    );
    await settle(tester, until: () => find.text('Tox').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('Chat details'));
    await settle(
      tester,
      until: () => find.text('You · Moderator').evaluate().isNotEmpty,
    );
    final you = find.descendant(
      of: find.widgetWithText(ListTile, 'iphy'),
      matching: find.byType(CircleIdenticon),
    );
    expect(tester.widget<CircleIdenticon>(you).bytes, _home.publicKey);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.runAsync(db.close);
  });
}
