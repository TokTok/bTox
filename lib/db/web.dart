import 'package:btox/db/database.dart';
import 'package:drift/wasm.dart';

Future<Database> constructDb(String databaseKey) async {
  final db = await WasmDatabase.open(
    databaseName: 'bTox',
    sqlite3Uri: Uri(path: 'sqlite3.wasm'),
    driftWorkerUri: Uri(path: 'drift_worker.js'),
  );
  return Database(db.resolvedExecutor);
}

Future<Database> constructHostedDb(String databaseKey) async {
  throw UnimplementedError('Database hosting not supported on this platform');
}

Future<void> unhostDatabase() async {}

Future<Database> connectToHostedDatabase({
  Duration timeout = const Duration(seconds: 10),
}) async {
  throw UnimplementedError('Database hosting not supported on this platform');
}
