import 'package:btox/db/database.dart';
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
  final events = <(EventId, SyncEvent, Uint8List)>[];
  for (final content in contents) {
    final event = SyncEvent(
      graph: GraphId.account(_self),
      author: _self,
      parents: [?events.lastOrNull?.$1],
      rank: events.length,
      time: 1700000000000 + events.length,
      content: content,
    );
    final bytes = event.encode();
    events.add((EventId.of(bytes), event, bytes));
  }
  await db.addSyncEvents(id, events);
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
