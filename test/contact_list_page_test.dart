import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/pages/contact_list_page.dart';
import 'package:btox/providers/calls.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/home.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/widgets/chat_list_item.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'mocks/settle.dart';

Finder _chatWith(PublicKey pk) =>
    find.byWidgetPredicate((w) => w is ChatListItem && w.chat.key == pk);

void main() {
  testWidgets('friend requests can be accepted, rejected, then deleted', (
    tester,
  ) async {
    final db = Database(NativeDatabase.memory());
    final alice = PublicKey(Uint8List.fromList(List.filled(32, 1)));
    final bob = PublicKey(Uint8List.fromList(List.filled(32, 2)));
    // Drift doesn't progress in the test's fake async zone.
    final home = (await tester.runAsync(() async {
      final profileId = await db.addProfile(
        ProfilesCompanion.insert(
          signedIn: const Value(true),
          settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );
      final home = await Home.load(db, await db.watchProfile(profileId).first);
      for (final (key, message) in [(alice, 'Hi, Alice here'), (bob, 'Bob')]) {
        await home.record(
          home.account,
          FriendRequested(pk: key, message: message),
        );
      }
      return home;
    }))!;
    Future<List<(PublicKey, bool, bool)>> changes() async => [
      for (final change in (await tester.runAsync(
        () => db.select(db.friendChanges).get(),
      ))!)
        (change.publicKey, change.wanted, change.deleteChat),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => db),
          connectionStatusProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const ContactListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hi, Alice here'), findsOneWidget);

    await tester.tap(find.byTooltip('Accept friend request').first);
    await tester.tap(find.byTooltip('Reject friend request').last);
    await tester.pumpAndSettle();
    expect(await changes(), [(alice, true, false), (bob, false, false)]);

    // As the background service records it.
    home.record(home.account, WantFriend(pk: alice));
    home.record(home.account, UnwantFriend(pk: bob));
    await settle(
      tester,
      until: () => find.byTooltip('Accept friend request').evaluate().isEmpty,
    );
    expect(find.byTooltip('Accept friend request'), findsNothing);
    expect(_chatWith(alice), findsOneWidget);
    expect(_chatWith(bob), findsNothing);

    await tester.longPress(_chatWith(alice));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('For 1 hour'));
    Future<List<SettingChange>> mutes() => db.select(db.settingChanges).get();
    await settle(tester, until: () async => (await mutes()).isNotEmpty);
    final muted = (await tester.runAsync(mutes))!;
    expect(
      [for (final c in muted) (c.scope, (c.setting!.value as Mute).mentions)],
      [(Scope.conversation(home.chatWith(alice)), false)],
    );
    // As the background service records it.
    home.settings(muted);
    await settle(
      tester,
      until: () =>
          find.byIcon(Icons.notifications_off_outlined).evaluate().isNotEmpty,
    );

    await tester.longPress(_chatWith(alice));
    await tester.pumpAndSettle();
    expect(find.text('Unmute notifications'), findsOneWidget);
    await tester.tap(find.text('Delete contact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // The chat goes too, unless unticked.
    expect(await changes(), [
      (alice, true, false),
      (bob, false, false),
      (alice, false, true),
    ]);
    expect(find.text('Contact "Unknown" deleted'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
  });

  testWidgets('the drawer switches to another signed-in account', (
    tester,
  ) async {
    final db = Database(NativeDatabase.memory());
    final other = await tester.runAsync(() async {
      ProfilesCompanion profile(String name, int key) =>
          ProfilesCompanion.insert(
            signedIn: const Value(true),
            settings: ProfileSettings(nickname: name, statusMessage: ''),
            secretKey: SecretKey(Uint8List(32)),
            publicKey: PublicKey(Uint8List.fromList(List.filled(32, key))),
            nospam: ToxAddressNospam(0),
          );
      await db.addProfile(profile('Me', 0));
      return db.addProfile(profile('Other', 1));
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => db),
          connectionStatusesProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const ContactListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    final settings = await tester.runAsync(() async {
      await pumpEventQueue();
      return db.watchAppSettings().first;
    });
    expect(settings!.currentProfile, other);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
  });

  testWidgets('a draft stays, also after a restart, until sent', (
    tester,
  ) async {
    final db = Database(NativeDatabase.memory());
    final alice = PublicKey(Uint8List.fromList(List.filled(32, 1)));
    await tester.runAsync(() async {
      final profileId = await db.addProfile(
        ProfilesCompanion.insert(
          signedIn: const Value(true),
          settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );
      final home = await Home.load(db, await db.watchProfile(profileId).first);
      await home.record(home.account, WantFriend(pk: alice));
    });
    Future<void> start() async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            databaseProvider.overrideWith((ref) => db),
            connectionStatusProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const ContactListPage(),
          ),
        ),
      );
      await settle(tester, until: () => _chatWith(alice).evaluate().isNotEmpty);
    }

    final draft = find.text('Draft: See you', findRichText: true);
    await start();
    await tester.tap(_chatWith(alice));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('messageField')), 'See you');
    await tester.pageBack();
    await settle(tester, until: () => draft.evaluate().isNotEmpty);

    await tester.pumpWidget(const SizedBox());
    await start();
    expect(draft, findsOneWidget);
    await tester.tap(_chatWith(alice));
    await settle(
      tester,
      until: () => find.text('See you').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pageBack();
    await settle(tester, until: () => draft.evaluate().isEmpty);
    expect(await tester.runAsync(() => db.select(db.chatDrafts).get()), []);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
  });

  testWidgets('the calls tab lists calls, the missed ones marked, with a '
      'button to call friends online back', (tester) async {
    final db = Database(NativeDatabase.memory());
    final alice = PublicKey(Uint8List.fromList(List.filled(32, 1)));
    final bob = PublicKey(Uint8List.fromList(List.filled(32, 2)));
    final profileId = (await tester.runAsync(
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
    CallRecord call(PublicKey friend, String name, CallContent content) => (
      chat: ChatSummary(
        ref: ChatRef(
          profileId,
          GraphId.friend(PublicKey(Uint8List(32)), friend),
        ),
        name: name,
        key: friend,
        online: friend == alice,
      ),
      entry: ChatEntry(
        event: EventId(Uint8List(32)..[0] = name.length),
        mine: !content.incoming,
        notice: true,
        timestamp: DateTime(2025, 1, 1),
        content: content,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => db),
          connectionStatusProvider.overrideWithValue(null),
          callHistoryProvider(profileId).overrideWithValue([
            call(
              alice,
              'Alice',
              const CallContent(
                incoming: false,
                ended: true,
                duration: Duration(minutes: 2, seconds: 31),
              ),
            ),
            call(bob, 'Bob', const CallContent(incoming: true, ended: true)),
          ]),
          canCallProvider(profileId).overrideWithValue(true),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const ContactListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calls'));
    await tester.pumpAndSettle();

    expect(find.textContaining('· 2:31'), findsOneWidget);
    expect(find.byIcon(Icons.call_made), findsOneWidget);
    expect(find.byIcon(Icons.call_missed), findsOneWidget);
    final buttons = tester.widgetList<IconButton>(
      find.widgetWithIcon(IconButton, Icons.call),
    );
    expect([for (final b in buttons) b.onPressed != null], [true, false]);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
  });
}
