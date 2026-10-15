import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/merge_chat_page.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'mocks/settle.dart';

PublicKey _key(int i) => PublicKey(Uint8List(32)..fillRange(0, 32, i));

final _conferenceBot = _key(3);
final _alice = _key(4);
final _groupBot = _key(5);

void main() {
  late Database db;
  late Id<Profiles> profile;
  late ChatSummary conference;
  late ChatSummary group;

  Future<void> open(WidgetTester tester, Widget Function() page) async {
    db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    profile = (await tester.runAsync(
      () => db.addProfile(
        ProfilesCompanion.insert(
          signedIn: const Value(true),
          settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      ),
    ))!;
    final conferenceId = ConferenceId(Uint8List(32)..[0] = 1);
    final groupId = GroupChatId(Uint8List(32)..[0] = 2);
    conference = ChatSummary(
      ref: ChatRef(profile, GraphId.conference(conferenceId)),
      name: 'Conference',
      key: conferenceId,
    );
    group = ChatSummary(
      ref: ChatRef(profile, GraphId.group(groupId)),
      name: 'Group',
      key: groupId,
    );
    final friend = ChatSummary(
      ref: ChatRef(profile, GraphId.friend(PublicKey(Uint8List(32)), _alice)),
      name: 'Friend',
      key: _alice,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => db),
          chatsForProfileProvider(profile)
              .overrideWithValue(AsyncData([conference, group, friend])),
          chatMergeProvider(group.ref).overrideWithValue(null),
          chatSendersProvider(conference.ref).overrideWithValue([
            (key: _conferenceBot, name: 'bot', messages: 10, relayed: 8),
            (key: _alice, name: 'alice', messages: 2, relayed: 0),
          ]),
          chatSendersProvider(group.ref).overrideWithValue([
            (key: _groupBot, name: 'relay', messages: 5, relayed: 5),
          ]),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(),
        ),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (context) => page()));
    await tester.pumpAndSettle();
  }

  testWidgets('a conference merges into a group, through the bot picked in '
      'each', (tester) async {
    await open(tester, () => MergeChatPage(chat: conference));

    // Only other group chats can be merged with.
    expect(find.text('Friend'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Group'));
    await tester.pumpAndSettle();
    expect(find.text('8 of 10 messages relayed'), findsOneWidget);
    await tester.tap(find.text('alice'));
    await tester.tap(find.text('Merge'));
    await settle(
      tester,
      until: () async => (await db.select(db.chatMerges).get()).isNotEmpty,
    );

    final merges = (await tester.runAsync(
      () => db.select(db.chatMerges).get(),
    ))!;
    expect(
      [for (final m in merges) (m.chat, m.bot, m.into, m.intoBot, m.merged)],
      [(conference.ref.graph, _alice, group.ref.graph, _groupBot, true)],
    );
    await tester.pumpAndSettle();
    expect(find.byType(MergeChatPage), findsNothing);
  });
  testWidgets("a relay bot's names show in its chat", (tester) async {
    await open(tester, () => RelayBotPage(chat: conference));

    await tester.tap(find.text('alice'));
    await tester.tap(find.text('bot'));
    await tester.tap(find.text('Show names'));
    await settle(
      tester,
      until: () async => (await db.select(db.relayBots).get()).isNotEmpty,
    );

    final bots = (await tester.runAsync(() => db.select(db.relayBots).get()))!;
    expect(
      [for (final b in bots) (b.chat, b.bot, b.relays)],
      [(conference.ref.graph, _conferenceBot, true)],
    );
    await tester.pumpAndSettle();
    expect(find.byType(RelayBotPage), findsNothing);
  });
}
