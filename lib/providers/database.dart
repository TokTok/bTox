import 'package:btox/db/database.dart';
import 'package:btox/db/shared.dart';
import 'package:btox/logger.dart';
import 'package:btox/providers/secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'database.g.dart';

const _logger = Logger(['DatabaseProvider']);

@riverpod
Future<Database> database(Ref ref) async {
  final databaseKey = await ref.read(databaseKeyProvider.future);

  _logger.d('Opening database');
  final db = await constructDb(databaseKey);
  ref.onDispose(() => db.close());
  _logger.d('Database opened: schema version ${db.schemaVersion}');
  return db;
}
