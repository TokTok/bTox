import 'dart:io';

import 'package:btox/providers/provider_error_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> logged;

  setUp(() {
    logged = [];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = print);
  });

  ProviderContainer container() {
    final container = ProviderContainer(
      observers: const [ProviderErrorLogger()],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('failures that are retried are logged', () async {
    final provider = FutureProvider<int>(
      (ref) async => throw const FileSystemException('no disk'),
    );
    container().listen(provider, (_, _) {});
    await pumpEventQueue();
    expect(logged.join('\n'), contains('failed, retrying:'));
  });

  test('failures that are not retried are logged', () async {
    final provider = FutureProvider<int>((ref) => throw StateError('bug'));
    await expectLater(container().read(provider.future), throwsStateError);
    expect(logged.join('\n'), contains('failed: Bad state: bug'));
  });
}
