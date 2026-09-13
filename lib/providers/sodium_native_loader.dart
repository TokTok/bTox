import 'dart:ffi';
import 'dart:io';

import 'package:sodium/sodium.dart';

Future<Sodium> loadSodium() {
  return SodiumInit.init(_openLibSodium);
}

DynamicLibrary _openLibSodium() => DynamicLibrary.open(libSodiumFileName());

String libSodiumFileName([String? operatingSystem]) {
  final os = operatingSystem ?? Platform.operatingSystem;
  switch (os) {
    case 'linux':
    case 'android':
      return 'libsodium.so';
    case 'macos':
    case 'ios':
      return 'libsodium.dylib';
    case 'windows':
      return 'libsodium.dll';
    default:
      throw UnsupportedError('Unsupported platform for libsodium loading: $os');
  }
}
