import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'secure_storage.g.dart';

@riverpod
Future<String> databaseKey(Ref ref) async {
  // TODO(iphydf): Use flutter_secure_storage.
  return 'password';
}
