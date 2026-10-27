import 'dart:io';

import 'package:btox/providers/secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:riverpod/riverpod.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Map<String, String> keyring;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('btox_key_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    keyring = {};
    addTearDown(() => _keyring(null));
  });

  void keyringFails(String code, String message) => _keyring(
    (_) async => throw PlatformException(code: code, message: message),
  );

  Future<String> readKey() {
    final container = ProviderContainer(retry: (_, _) => null);
    addTearDown(container.dispose);
    return container.read(databaseKeyProvider.future);
  }

  test('a new key is kept in the keyring', () async {
    _keyring((call) async {
      final args = call.arguments as Map;
      return switch (call.method) {
        'read' => keyring[args['key']],
        _ => keyring[args['key'] as String] = args['value'] as String,
      };
    });
    final key = await readKey();
    expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(await readKey(), key);
    expect(keyring, {'databaseKey': key});
    expect(dir.listSync(), isEmpty);
  });

  test('without a Secret Service, the key is kept in a file', () async {
    keyringFails('Libsecret error', 'secret_service_get_sync: no D-Bus');
    final key = await readKey();
    final file = File('${dir.path}/databaseKey');
    expect(file.readAsStringSync(), key);
    expect(file.statSync().modeString(), 'rw-------');
    expect(await readKey(), key);
  });

  test('a locked keyring is not replaced by a key file', () async {
    keyringFails('KeyringLocked', 'KeyringLocked');
    await expectLater(readKey(), throwsA(isA<PlatformException>()));
    expect(dir.listSync(), isEmpty);
  });
}

void _keyring(Future<Object?> Function(MethodCall)? handler) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handler);
