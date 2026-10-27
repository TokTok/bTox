import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/attachments/attachments.dart';
import 'package:btox/db/database.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:drift/drift.dart' show DriftSqlType, Variable;

const _format = 'btox-backup';

/// Tables of the profiles' own rows, by profile ID. Online states are left
/// out: they're only true while Tox runs.
Iterable<String> _ownedTables(Database db) => [
  for (final table in db.allTables)
    if (table.columnsByName.containsKey('profile_id') && table != db.liveFacts)
      table.actualTableName,
];

/// The rows of [profiles] and everything that belongs to them, as JSON.
Future<Uint8List> exportBackup(Database db, Set<Id<Profiles>> profiles) {
  final ids = profiles.map((p) => p.value).join(', ');
  Future<List<Map<String, Object?>>> rows(String table, [String where = '1']) =>
      db
          .customSelect('SELECT * FROM "$table" WHERE $where')
          .map(
            (row) => row.data.map(
              (column, value) => MapEntry(
                column,
                value is Uint8List ? base64Encode(value) : value,
              ),
            ),
          )
          .get();
  Future<List<Map<String, Object?>>> owned(String table) =>
      rows(table, 'profile_id IN ($ids)');

  return db.transaction(() async {
    return utf8.encode(
      jsonEncode({
        'format': _format,
        'schema': db.schemaVersion,
        'tables': {
          'app_settings': await rows('app_settings'),
          'cached_bootstrap_nodes': await rows('cached_bootstrap_nodes'),
          'profiles': await rows('profiles', 'id IN ($ids)'),
          for (final table in _ownedTables(db)) table: await owned(table),
        },
      }),
    );
  });
}

/// A backup's tables, from the database's schema [version].
typedef Backup = ({int version, Map<String, dynamic> tables});

/// The backup [bytes] are, if they are one.
Backup? readBackup(Uint8List bytes) {
  try {
    if (jsonDecode(utf8.decode(bytes)) case {
      'format': _format,
      'schema': final int version,
      'tables': final Map<String, dynamic> tables,
    }) {
      return (version: version, tables: tables);
    }
    return null;
  } on FormatException {
    return null;
  }
}

/// The nicknames of the accounts in a backup, by their ID in it.
Map<Object?, String> backupAccounts(Map<String, dynamic> tables) => {
  for (final Map p in tables['profiles'] as List)
    p['id']: jsonDecode(p['settings'] as String)['nickname'] as String,
};

/// Adds the [accounts] from a backup that the database doesn't have yet,
/// with new IDs. Columns the schema no longer has are dropped, and new ones
/// get their defaults. Returns how many accounts were added.
Future<int> restoreBackup(Database db, Backup backup, Set<Object?> accounts) {
  final tables = backup.tables;
  return db.transaction(() async {
    final existing = {
      for (final row
          in await db.customSelect('SELECT public_key FROM profiles').get())
        row.data['public_key'],
    };

    /// Inserts the rows of [table] and returns their new IDs by old ID.
    /// Rows whose [owner] wasn't added are skipped, and [later] columns are
    /// left for [relink].
    Future<Map<Object?, int>> insert(
      String table, {
      bool Function(Map row)? where,
      (String, Map<Object?, int>)? owner,
      Set<String> later = const {},
      bool keepIds = false,
    }) async {
      final info = db.allTables.firstWhere((t) => t.actualTableName == table);
      final columns = {for (final c in info.$columns) c.name}..removeAll(later);
      if (!keepIds) {
        columns.remove('id');
      }
      final blobs = {
        for (final c in info.$columns)
          if (c.type == DriftSqlType.blob) c.name,
      };
      final ids = <Object?, int>{};
      for (final Map row in tables[table] as List? ?? const []) {
        final values = {
          for (final column in columns)
            if (row.containsKey(column))
              column: switch (row[column]) {
                final String blob when blobs.contains(column) => base64Decode(
                  blob,
                ),
                final value => value,
              },
        };
        if (owner case (final column, final owners)) {
          if (owners[row[column]] case final id?) {
            values[column] = id;
          } else {
            continue;
          }
        }
        if (where?.call(row) == false) {
          continue;
        }
        ids[row['id']] = await db.customInsert(
          'INSERT OR REPLACE INTO "$table" '
          '(${values.keys.map((k) => '"$k"').join(', ')}) '
          'VALUES (${List.filled(values.length, '?').join(', ')})',
          variables: [for (final v in values.values) Variable<Object>(v)],
          updates: {info},
        );
      }
      return ids;
    }

    /// Points [column] of the added rows of [table] at the added targets.
    Future<void> relink(
      String table,
      Map<Object?, int> ids,
      String column,
      Map<Object?, int> targets,
    ) async {
      final info = db.allTables.firstWhere((t) => t.actualTableName == table);
      for (final Map row in tables[table] as List? ?? const []) {
        if ((ids[row['id']], targets[row[column]]) case (
          final id?,
          final target?,
        )) {
          await db.customUpdate(
            'UPDATE "$table" SET "$column" = ? WHERE id = ?',
            variables: [Variable<int>(target), Variable<int>(id)],
            updates: {info},
          );
        }
      }
    }

    final fresh = existing.isEmpty;
    final profiles = await insert(
      'profiles',
      where: (p) =>
          accounts.contains(p['id']) && !existing.contains(p['public_key']),
    );
    for (final table in _ownedTables(db)) {
      await insert(
        table,
        owner: ('profile_id', profiles),
        // Not the files the backup didn't bring.
        where: table == 'transfers'
            ? (row) => attachmentExists(row['path'] as String)
            : null,
        // An event's ID is its hash, not a row number.
        keepIds: table == 'sync_events',
      );
    }
    await insert('cached_bootstrap_nodes', keepIds: true);
    // A bTox with accounts keeps its own app settings.
    final settings = await insert(
      'app_settings',
      where: (_) => fresh,
      later: {'current_profile'},
      keepIds: true,
    );
    await relink('app_settings', settings, 'current_profile', profiles);
    return profiles.length;
  });
}
