import 'package:btox/providers/sodium_native_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('libSodiumFileName', () {
    test('returns libsodium.so on Linux', () {
      expect(libSodiumFileName('linux'), 'libsodium.so');
    });

    test('returns libsodium.so on Android', () {
      expect(libSodiumFileName('android'), 'libsodium.so');
    });

    test('returns libsodium.dylib on macOS', () {
      expect(libSodiumFileName('macos'), 'libsodium.dylib');
    });

    test('returns libsodium.dylib on iOS', () {
      expect(libSodiumFileName('ios'), 'libsodium.dylib');
    });

    test('returns libsodium.dll on Windows', () {
      expect(libSodiumFileName('windows'), 'libsodium.dll');
    });

    test('throws on an unsupported platform', () {
      expect(() => libSodiumFileName('fuchsia'), throwsUnsupportedError);
    });
  });
}
