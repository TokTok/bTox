import 'package:btox/db/database.dart';

Future<Database> constructDb(String databaseKey) async {
  throw UnimplementedError('Database not supported on this platform');
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
