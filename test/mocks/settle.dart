import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Lets the database and the background work it starts run in real time,
/// which they don't in the test's fake async zone, drawing as they go, until
/// [until] holds. Without it, lets what's pending finish.
Future<void> settle(
  WidgetTester tester, {
  FutureOr<bool> Function()? until,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  for (var i = 0; ; i++) {
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (until == null
        ? i >= 4
        : (await tester.runAsync(() async => until()))!) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('Gave up waiting after $timeout');
    }
  }
}
