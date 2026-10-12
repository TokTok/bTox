import 'package:btox/db/database.dart';
import 'package:btox/db/shared.dart';
import 'package:btox/logger.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'database.g.dart';

const _logger = Logger(['DatabaseProvider']);

/// The app's database. On mobile, the background service owns it (see
/// [hostedDatabase]) and the UI connects to it.
@riverpod
Future<Database> database(Ref ref) async {
  if (AnyPlatform.instance.isMobile) {
    _logger.d('Connecting to background service database');
    final db = await connectToHostedDatabase();
    ref.onDispose(() => db.close());
    return db;
  }

  final databaseKey = await ref.read(databaseKeyProvider.future);

  _logger.d('Opening database');
  final db = await constructDb(databaseKey);
  ref.onDispose(() => db.close());
  _logger.d('Database opened: schema version ${db.schemaVersion}');
  return db;
}

/// Overrides [databaseProvider] in the database owner (the background service
/// on mobile) to open the database and serve it to the UI.
Future<Database> hostedDatabase(Ref ref) async {
  final databaseKey = await ref.read(databaseKeyProvider.future);

  _logger.d('Opening hosted database');
  final db = await constructHostedDb(databaseKey);
  ref.onDispose(() async {
    await db.close();
    await unhostDatabase();
  });
  _logger.d('Database opened: schema version ${db.schemaVersion}');
  return db;
}
