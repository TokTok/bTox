import 'package:btox/providers/keyboard_height.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keyboardHeight has no events on non-mobile platforms', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final states = <AsyncValue<double>>[];
    container.listen(
      keyboardHeightProvider,
      (previous, next) => states.add(next),
      fireImmediately: true,
    );

    await Future<void>.delayed(Duration.zero);

    expect(states, [const AsyncLoading<double>()]);
  });

  test('keyboardHeightStream forwards events on mobile platforms', () async {
    const channel = EventChannel('keyboardHeightEventChannel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          channel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              events.success(123.0);
              events.endOfStream();
            },
          ),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(channel, null),
    );

    final heights = await keyboardHeightStream(isMobile: true).toList();

    expect(heights, [123.0]);
  });
}
