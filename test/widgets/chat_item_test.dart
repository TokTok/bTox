import 'dart:typed_data';

import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/providers/map_tile.dart';
import 'package:btox/widgets/chat_item.dart';
import 'package:btox/widgets/chat_location_bubble.dart';
import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:btox/widgets/sender_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../mocks/fake_tile_provider.dart';

ChatEntry _entry(
  int minute, {
  bool mine = false,
  String? sender,
  PublicKey? from,
  bool notice = false,
}) => ChatEntry(
  event: EventId(Uint8List(32)..[0] = minute),
  sender: sender,
  from: from,
  mine: mine,
  content: const TextContent(text: 'hi'),
  timestamp: DateTime(2026, 10, 20, 12, minute),
  notice: notice,
);

void main() {
  test('messages an author sends one after another make a run', () {
    expect(inRun(_entry(0), _entry(1)), isTrue);
    expect(inRun(_entry(0, sender: 'Bob'), _entry(1, sender: 'Bob')), isTrue);
    // Renamed, but the same key.
    final bob = PublicKey(Uint8List(32)..[0] = 2);
    expect(
      inRun(
        _entry(0, sender: 'Bob', from: bob),
        _entry(1, sender: 'Robert', from: bob),
      ),
      isTrue,
    );
    expect(
      inRun(
        _entry(0, sender: 'Bob', from: bob),
        _entry(1, sender: 'Bob', from: PublicKey(Uint8List(32))),
      ),
      isFalse,
    );

    expect(inRun(_entry(0), _entry(1, mine: true)), isFalse);
    expect(inRun(_entry(0, sender: 'Bob'), _entry(1, sender: 'Eve')), isFalse);
    expect(inRun(_entry(0), _entry(1, notice: true)), isFalse);
    // Too long after.
    expect(inRun(_entry(0), _entry(10)), isFalse);
  });

  testWidgets("a group message's sender shows in its run's first bubble", (
    tester,
  ) async {
    final chat = ChatRef(const Id(1), GraphId(Uint8List(32)));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Column(
            children: [
              ChatItem(
                chat: chat,
                entry: _entry(0, sender: 'Bob'),
                joinsBelow: true,
              ),
              ChatItem(
                chat: chat,
                entry: _entry(1, sender: 'Bob'),
                joinsAbove: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(ChatTextBubble).first,
        matching: find.text('Bob'),
      ),
      findsOneWidget,
    );
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('a sender keeps their colour when they rename themselves', (
    tester,
  ) async {
    final bob = PublicKey(Uint8List(32)..[0] = 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            SenderName('Bob', author: bob),
            SenderName('Robert', author: bob),
          ],
        ),
      ),
    );
    Color? colour(String name) =>
        tester.widget<Text>(find.text(name)).style?.color;
    expect(colour('Robert'), colour('Bob'));
  });

  testWidgets('a location shows as a map', (tester) async {
    final fakeTileProvider = FakeTileProvider();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapTileProvider.overrideWith((ref) => fakeTileProvider)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ChatItem(
            chat: ChatRef(const Id(1), GraphId(Uint8List(32))),
            entry: ChatEntry(
              event: EventId(Uint8List(32)),
              mine: true,
              // Greenwich Observatory
              content: const LocationContent(
                latitude: 51.476853468836715,
                longitude: -0.0005210189094241177,
              ),
              timestamp: DateTime(2026, 10, 20, 12),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChatLocationBubble), findsOneWidget);
    expect(fakeTileProvider.requests, hasLength(16));
    expect(fakeTileProvider.requests.first, TileCoordinates(4094, 2723, 13));
  });

  testWidgets("a group member's location shows under their name", (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapTileProvider.overrideWith((ref) => FakeTileProvider())],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ChatItem(
            chat: ChatRef(const Id(1), GraphId(Uint8List(32))),
            entry: ChatEntry(
              event: EventId(Uint8List(32)),
              sender: 'Bob',
              from: PublicKey(Uint8List(32)..[0] = 2),
              mine: false,
              content: const LocationContent(latitude: 51.48, longitude: 0),
              timestamp: DateTime(2026, 10, 20, 12),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SenderName), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
  });
}
