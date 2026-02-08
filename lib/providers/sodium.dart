import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sodium_libs/sodium_libs.dart';

part 'sodium.g.dart';

@riverpod
Future<Sodium> sodium(Ref ref) async {
  return SodiumInit.init();
}
