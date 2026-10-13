import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:drift/drift.dart' show Variable;

const _format = 'btox-backup';

/// The rows of [profiles] and everything that belongs to them, as JSON.
Future<Uint8List> exportBackup(Database db, Set<Id<Profiles>> profiles) {
  final ids = profiles.map((p) => p.value).join(', ');
  Future<List<Map<String, Object?>>> rows(String table, [String where = '1']) =>
      db
          .customSelect('SELECT * FROM "$table" WHERE $where')
          .map((row) => row.data)
          .get();

  return db.transaction(() async {
    return utf8.encode(
      jsonEncode({
        'format': _format,
        'tables': {
          'app_settings': await rows('app_settings'),
          'cached_bootstrap_nodes': await rows('cached_bootstrap_nodes'),
          'profiles': await rows('profiles', 'id IN ($ids)'),
          'contacts': await rows('contacts', 'profile_id IN ($ids)'),
          'friend_requests': await rows(
            'friend_requests',
            'profile_id IN ($ids)',
          ),
          'messages': await rows(
            'messages',
            'contact_id IN (SELECT id FROM contacts WHERE profile_id IN ($ids))',
          ),
        },
      }),
    );
  });
}

/// The tables in [bytes] if they are a backup.
Map<String, dynamic>? readBackup(Uint8List bytes) {
  try {
    final json = jsonDecode(utf8.decode(bytes));
    return json is Map<String, dynamic> && json['format'] == _format
        ? json['tables'] as Map<String, dynamic>
        : null;
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
Future<int> restoreBackup(
  Database db,
  Map<String, dynamic> tables,
  Set<Object?> accounts,
) {
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
      final ids = <Object?, int>{};
      for (final Map row in tables[table] as List? ?? const []) {
        final values = {
          for (final column in columns)
            if (row.containsKey(column)) column: row[column],
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
    final contacts = await insert(
      'contacts',
      owner: ('profile_id', profiles),
      later: {'last_read_message'},
    );
    await insert('friend_requests', owner: ('profile_id', profiles));
    final messages = await insert(
      'messages',
      owner: ('contact_id', contacts),
      later: {'parent', 'merged'},
    );
    await relink('contacts', contacts, 'last_read_message', messages);
    await relink('messages', messages, 'parent', messages);
    await relink('messages', messages, 'merged', messages);
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
