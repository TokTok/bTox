import 'dart:convert';

import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart' show Tox_Message_Type;
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/chat_details_page.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'mocks/settle.dart';

final _self = PublicKey(Uint8List(32)..fillRange(0, 32, 1));
final _bob = PublicKey(Uint8List(32)..fillRange(0, 32, 2));
final _carol = PublicKey(Uint8List(32)..fillRange(0, 32, 3));
final _group = GroupChat(GroupChatId(Uint8List(32)..fillRange(0, 32, 4)));

/// [contents] in [graph], each after the one before, at its time.
List<(EventId, SyncEvent, Uint8List)> _events(
  GraphId graph,
  List<(int, EventContent)> contents,
) {
  final events = <(EventId, SyncEvent, Uint8List)>[];
  for (final (time, content) in contents) {
    final event = SyncEvent(
      graph: graph,
      author: _self,
      parents: [?events.lastOrNull?.$1],
      rank: events.length,
      time: time,
      content: content,
    );
    final bytes = event.encode();
    events.add((EventId.of(bytes), event, bytes));
  }
  return events;
}

/// A profile whose account has [contents], each after the one before.
Future<Id<Profiles>> _account(Database db, List<EventContent> contents) async {
  final id = await db.addProfile(
    ProfilesCompanion.insert(
      signedIn: const Value(true),
      settings: ProfileSettings(nickname: 'iphy', statusMessage: ''),
      secretKey: SecretKey(Uint8List(32)),
      publicKey: _self,
      nospam: ToxAddressNospam(0),
    ),
  );
  await db.addSyncEvents(
    id,
    _events(GraphId.account(_self), [
      for (final (i, content) in contents.indexed) (1700000000000 + i, content),
    ]),
  );
  return id;
}

Future<void> _show(WidgetTester tester, Database db, ChatRef chat) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) => db)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ChatDetailsPage(chat: chat),
        ),
      ),
    );

Future<void> _close(WidgetTester tester, Database db) async {
  await tester.pumpWidget(const SizedBox());
  await settle(tester);
  await tester.runAsync(db.close);
}

void main() {
  testWidgets("a group's details say who is in it", (tester) async {
    final db = Database(NativeDatabase.memory());
    Fact member(PublicKey pk, FactValue value) =>
        (Subject.peer(_group, pk), value);
    final profile = (await tester.runAsync(() async {
      final id = await _account(db, [
        for (final value in const [
          FactValue.name('Tox'),
          FactValue.joined(true),
          FactValue.topic('Talk about Tox'),
          FactValue.role(Role.moderator),
          FactValue.selfName('iphy'),
        ])
          FactContent(subject: Subject.chat(_group), value: value),
      ]);
      await db.updateLiveFacts(id, [
        (const Subject.account(), const FactValue.connection(Connection.udp)),
        member(_bob, const FactValue.name('Bob')),
        member(_bob, const FactValue.role(Role.user)),
        member(_bob, const FactValue.status(UserStatus.away)),
        member(_carol, const FactValue.name('Carol')),
        member(_carol, const FactValue.role(Role.founder)),
      ], all: true);
      return id;
    }))!;

    await _show(tester, db, ChatRef(profile, _group.graph));
    await settle(
      tester,
      until: () => find.text('3 members').evaluate().isNotEmpty,
    );
    expect(find.text('Tox'), findsOneWidget);
    expect(find.text('Talk about Tox'), findsOneWidget);
    expect(find.text('You · Moderator'), findsOneWidget);
    // The founder first.
    expect(
      tester.getTopLeft(find.text('Carol')).dy,
      lessThan(tester.getTopLeft(find.text('Bob')).dy),
    );
    expect(find.text('Founder'), findsOneWidget);
    expect(find.text('Away'), findsOneWidget);
    expect(find.text('Mute notifications'), findsOneWidget);

    // Only Tox can say, while it runs.
    await tester.runAsync(() => db.clearLiveFacts(profile));
    await settle(tester, until: () => find.text('Bob').evaluate().isEmpty);
    expect(
      find.text("Who is here shows while the account's home device is online"),
      findsOneWidget,
    );

    await _close(tester, db);
  });

  testWidgets('the names a relay bot relayed show under it, recent first', (
    tester,
  ) async {
    final db = Database(NativeDatabase.memory());
    final profile = (await tester.runAsync(() async {
      final id = await _account(db, [
        FactContent(
          subject: Subject.chat(_group),
          value: const FactValue.joined(true),
        ),
        RelayBot(chat: _group, bot: _bob, relays: true),
      ]);
      await db.addSyncEvents(
        id,
        _events(_group.graph, [
          for (final (time, text) in [
            (1700000000000, '<Eve> hi'),
            (DateTime.now().millisecondsSinceEpoch, '<Dan> yo'),
          ])
            (
              time,
              Received(
                from: _bob,
                sender: 'relay',
                message: utf8.encode(text),
                kind: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
              ),
            ),
        ]),
      );
      await db.updateLiveFacts(id, [
        (const Subject.account(), const FactValue.connection(Connection.udp)),
        (Subject.peer(_group, _bob), const FactValue.name('relay')),
      ], all: true);
      return id;
    }))!;

    await _show(tester, db, ChatRef(profile, _group.graph));
    await settle(
      tester,
      until: () => find.text('Seen through relay').evaluate().isNotEmpty,
    );
    expect(find.text('Dan'), findsOneWidget);
    expect(find.text('Eve'), findsNothing);
    await tester.tap(find.text('Show 1 more'));
    await tester.pump();
    expect(find.text('Eve'), findsOneWidget);

    // From history, when the bot is gone.
    await tester.runAsync(() => db.clearLiveFacts(profile));
    await settle(tester, until: () => find.text('relay').evaluate().isEmpty);
    expect(find.text('Seen through relay'), findsOneWidget);
    expect(find.text('Dan'), findsOneWidget);

    await _close(tester, db);
  });

  testWidgets("a friend's details say how they are", (tester) async {
    final db = Database(NativeDatabase.memory());
    final profile = (await tester.runAsync(() async {
      final id = await _account(db, [
        WantFriend(pk: _bob),
        FactContent(
          subject: Subject.friend(_bob),
          value: const FactValue.name('Bob'),
        ),
        FactContent(
          subject: Subject.friend(_bob),
          value: const FactValue.statusMessage('Out for lunch'),
        ),
      ]);
      await db.updateLiveFacts(id, [
        (Subject.friend(_bob), const FactValue.status(UserStatus.busy)),
      ]);
      return id;
    }))!;

    await _show(tester, db, ChatRef(profile, GraphId.friend(_self, _bob)));
    await settle(tester, until: () => find.text('Bob').evaluate().isNotEmpty);
    expect(find.text('Out for lunch'), findsOneWidget);
    expect(find.text('Busy'), findsOneWidget);
    expect(find.text('3 members'), findsNothing);

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
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(copied, [_bob.toJson()]);
    expect(find.text('Public key copied'), findsOneWidget);

    await _close(tester, db);
  });
}
