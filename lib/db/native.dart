import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:btox/db/database.dart';
import 'package:btox/logger.dart';
import 'package:drift/drift.dart' show DatabaseConnection, QueryExecutor;
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

const _logger = Logger(['NativeDatabase']);

const _hostPortName = 'btox-database';

// https://drift.simonbinder.eu/platforms/encryption/#setup
final _setupSqlCipher = Future<void>(() async {
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
});

Future<Database> constructDb(String databaseKey) async =>
    Database(await _openFile(databaseKey));

/// Opens the database file and serves it to other isolates in this process,
/// e.g. from the background service to the UI. Returns this isolate's own
/// connection to it.
Future<Database> constructHostedDb(String databaseKey) async =>
    hostDatabase(await _openFile(databaseKey));

Future<QueryExecutor> _openFile(String databaseKey) async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbFolder = await getApplicationDocumentsDirectory();
  final file = File(path.join(dbFolder.path, 'bTox.sqlite'));
  _logger.d('Database file: ${file.path}');

  await _setupSqlCipher;

  // https://drift.simonbinder.eu/platforms/encryption/#using
  return NativeDatabase(
    file,
    setup: (database) {
      // https://drift.simonbinder.eu/platforms/encryption/#important-notice
      final cipherVersion = database.select('PRAGMA cipher_version;');
      if (cipherVersion.isEmpty) {
        throw Exception('Failed to get cipher version');
      }
      _logger.d('Encrypted database: ${cipherVersion.first}');

      final escapedKey = databaseKey.replaceAll("'", "''");
      database.execute("PRAGMA key = '$escapedKey';");

      // Recommended option, not enabled by default on SQLCipher
      database.config.doubleQuotedStringLiterals = false;
    },
  );
}

DriftIsolate? _server;

/// Serves [executor] to other isolates in this process. All users, including
/// this isolate, go through the server, so they all see each other's writes
/// in their watched queries.
Future<Database> hostDatabase(QueryExecutor executor) async {
  await unhostDatabase();
  final server = _server = DriftIsolate.inCurrent(
    () => DatabaseConnection(executor),
  );
  IsolateNameServer.registerPortWithName(server.connectPort, _hostPortName);
  _logger.d('Hosting database');
  return Database(await server.connect());
}

/// Stops serving the database and closes it.
Future<void> unhostDatabase() async {
  IsolateNameServer.removePortNameMapping(_hostPortName);
  await _server?.shutdownAll();
  _server = null;
}

/// Connects to the database hosted by [hostDatabase], waiting up to [timeout]
/// for the host to appear.
Future<Database> connectToHostedDatabase({
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final SendPort? port = IsolateNameServer.lookupPortByName(_hostPortName);
    if (port != null) {
      final connection = await DriftIsolate.fromConnectPort(port)
          .connect(connectTimeout: timeout);
      _logger.d('Connected to hosted database');
      return Database(connection);
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('No hosted database after $timeout');
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
}
