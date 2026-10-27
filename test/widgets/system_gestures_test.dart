import 'package:btox/widgets/system_gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a swipe up from the bottom, as for going home, scrolls nothing',
    (tester) async {
      // Where Android's gesture navigation takes swipes, in physical pixels.
      tester.view.systemGestureInsets = const FakeViewPadding(bottom: 90);
      addTearDown(tester.view.resetSystemGestureInsets);
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: leaveSystemSwipes,
          home: Scaffold(
            body: ListView(
              children: [
                for (var i = 0; i < 40; i++)
                  ListTile(title: Text('Row $i'), onTap: () => tapped++),
              ],
            ),
          ),
        ),
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      final bottom =
          tester.getBottomLeft(find.byType(ListView)) + const Offset(100, -4);

      await tester.dragFrom(bottom, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(position.pixels, 0);

      await tester.tapAt(bottom);
      expect(tapped, 1);

      await tester.dragFrom(
        bottom - const Offset(0, 100),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
    },
  );
  testWidgets('a swipe in from a side, as for going back, moves no page', (
    tester,
  ) async {
    // Where Android's back gesture takes swipes, in physical pixels.
    tester.view.systemGestureInsets = const FakeViewPadding(
      left: 60,
      right: 60,
    );
    addTearDown(tester.view.resetSystemGestureInsets);
    final pages = PageController();
    addTearDown(pages.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: leaveSystemSwipes,
        home: PageView(
          controller: pages,
          children: [for (var i = 0; i < 3; i++) Text('Page $i')],
        ),
      ),
    );
    final size = tester.getSize(find.byType(PageView));
    final middle = size.height / 2;

    await tester.dragFrom(
      Offset(size.width - 4, middle),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(pages.page, 0);

    await tester.dragFrom(
      Offset(size.width / 2, middle),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(pages.page, 1);

    await tester.dragFrom(Offset(4, middle), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(pages.page, 1);
  });
}
