import 'dart:ffi';
import 'dart:io';

import 'package:sodium/sodium.dart';

Future<Sodium> loadSodium() => SodiumInit.init(_openLibSodium);

DynamicLibrary _openLibSodium() => DynamicLibrary.open(libSodiumFileName());

String libSodiumFileName([String? operatingSystem]) =>
    switch (operatingSystem ?? Platform.operatingSystem) {
      'linux' || 'android' => 'libsodium.so',
      'macos' || 'ios' => 'libsodium.dylib',
      'windows' => 'libsodium.dll',
      final os => throw UnsupportedError(
        'Unsupported platform for libsodium loading: $os',
      ),
    };
