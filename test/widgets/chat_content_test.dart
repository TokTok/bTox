import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/content.dart';
import 'package:btox/providers/map_tile.dart';
import 'package:btox/widgets/chat_content.dart';
import 'package:btox/widgets/chat_location_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_tile_provider.dart';

void main() {
  testWidgets('Location content is displayed as map',
      (WidgetTester tester) async {
    final fakeTileProvider = FakeTileProvider();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapTileProvider.overrideWith(
            (ref) => fakeTileProvider,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ChatContent(
            // Greenwich Observatory
            content: LocationContent(
              latitude: 51.476853468836715,
              longitude: -0.0005210189094241177,
            ),
            color: Colors.white,
            textStyle: const TextStyle(color: Colors.black),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(ChatLocationBubble), findsOneWidget);
    expect(fakeTileProvider.requests, hasLength(16));
    expect(fakeTileProvider.requests.first, TileCoordinates(4094, 2723, 13));
  });
}
