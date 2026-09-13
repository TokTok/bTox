import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sodium/sodium.dart';

import 'sodium_native_loader.dart'
    if (dart.library.js) 'sodium_web_loader.dart'
    as sodium_loader;

part 'sodium.g.dart';

@riverpod
Future<Sodium> sodium(Ref ref) async {
  return sodium_loader.loadSodium();
}
