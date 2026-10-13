import 'dart:convert';

import 'package:btox/models/app_defaults.dart';
import 'package:btox/models/bootstrap_nodes.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:drift/drift.dart';

export 'package:drift/drift.dart' show Value;

part 'database.g.dart';

@DriftDatabase(
  tables: [
    AppSettings,
    CachedBootstrapNodes,
    Contacts,
    FriendRequests,
    Messages,
    Profiles,
  ],
)
final class Database extends _$Database {
  Database(super.e);

  // Bump with every schema change, then run `tools/prepare`.
  @override
  int get schemaVersion => 1;

  Future<Id<Contacts>> acceptFriendRequest(FriendRequest request) =>
      transaction(() async {
        await deleteFriendRequest(request.id);
        return addContact(
          ContactsCompanion.insert(
            profileId: request.profileId,
            publicKey: request.publicKey,
          ),
        );
      });

  Future<Id<Contacts>> addContact(ContactsCompanion entry) async =>
      Id(await into(contacts).insert(entry));

  Future<void> addFriendRequest(FriendRequestsCompanion entry) async {
    await into(friendRequests).insert(
      entry,
      onConflict: DoUpdate(
        (_) => entry,
        target: [friendRequests.profileId, friendRequests.publicKey],
      ),
    );
  }

  Future<Id<Messages>> addMessage(MessagesCompanion entry) async =>
      Id(await into(messages).insert(entry));

  Future<Id<Profiles>> addProfile(ProfilesCompanion entry) async =>
      Id(await into(profiles).insert(entry));

  Future<void> cacheBootstrapNodes(BootstrapNodeList nodes) async {
    await into(cachedBootstrapNodes).insertOnConflictUpdate(
      CachedBootstrapNodesCompanion.insert(
        id: const Value(0),
        json: jsonEncode(nodes.toJson()),
      ),
    );
  }

  /// Toxcore forgets unfinished incoming files when it stops.
  Future<void> cancelIncomingFiles(Id<Profiles> profileId) async {
    await (update(messages)..where(
          (m) =>
              m.delivered.isNull() &
              m.fileState.isInValues([FileState.offered, FileState.active]) &
              m.contactId.isInQuery(_contactsOf(profileId)),
        ))
        .write(MessagesCompanion(fileState: Value(FileState.cancelled)));
  }

  Future<void> clearContactsOnline(Id<Profiles> profileId) async {
    await (update(contacts)..where((c) => c.profileId.equals(profileId.value)))
        .write(const ContactsCompanion(online: Value(false)));
  }

  Future<void> clearFriendRequest(Id<Contacts> id) async {
    await (update(contacts)..where((c) => c.id.equals(id.value))).write(
      const ContactsCompanion(
        friendRequestAddress: Value(null),
        friendRequestMessage: Value(null),
      ),
    );
  }

  Future<void> deleteContact(Id<Contacts> id) async {
    await transaction(() async {
      await (delete(messages)..where((m) => m.contactId.equals(id.value))).go();
      await (delete(contacts)..where((c) => c.id.equals(id.value))).go();
    });
  }

  Future<void> deleteFriendRequest(Id<FriendRequests> id) async {
    await (delete(friendRequests)..where((r) => r.id.equals(id.value))).go();
  }

  Future<void> deleteProfile(Id<Profiles> id) async {
    await transaction(() async {
      // Delete all their messages.
      await (delete(
        messages,
      )..where((m) => m.contactId.isInQuery(_contactsOf(id)))).go();
      // Delete the friend requests.
      await (delete(
        friendRequests,
      )..where((r) => r.profileId.equals(id.value))).go();
      // Then delete the contacts.
      await (delete(contacts)..where((c) => c.profileId.equals(id.value))).go();
      // Finally delete the profile.
      await (delete(profiles)..where((p) => p.id.equals(id.value))).go();
    });
  }

  Future<BootstrapNodeList?> getCachedBootstrapNodes() async {
    final row = await select(cachedBootstrapNodes).getSingleOrNull();
    return row == null
        ? null
        : BootstrapNodeList.fromJson(jsonDecode(row.json));
  }

  Future<Message> getMessage(Id<Messages> id) async =>
      (select(messages)..where((m) => m.id.equals(id.value))).getSingle();

  Future<void> markContactRead(Id<Contacts> id) async {
    await customUpdate(
      'UPDATE contacts SET last_read_message = '
      '(SELECT MAX(id) FROM messages WHERE contact_id = ?1) WHERE id = ?1',
      variables: [Variable(id.value)],
      updates: {contacts},
    );
  }

  Future<void> markMessageDelivered(Id<Messages> id) async {
    await (update(messages)..where((m) => m.id.equals(id.value))).write(
      const MessagesCompanion(delivered: Value(true)),
    );
  }

  Future<void> setFileState(
    Id<Messages> id,
    FileState state, {
    int? transferred,
  }) async {
    await (update(messages)..where((m) => m.id.equals(id.value))).write(
      MessagesCompanion(
        fileState: Value(state),
        fileTransferred: Value.absentIfNull(transferred),
      ),
    );
  }

  Future<void> setFileTransferred(Id<Messages> id, int transferred) async {
    await (update(messages)..where((m) => m.id.equals(id.value))).write(
      MessagesCompanion(fileTransferred: Value(transferred)),
    );
  }

  /// Signs the profile in and shows it.
  Future<void> signIn(Id<Profiles> id) => transaction(() async {
    await (update(profiles)..where((p) => p.id.equals(id.value))).write(
      ProfilesCompanion(signedIn: Value(true)),
    );
    await updateAppSettings(AppSettingsCompanion(currentProfile: Value(id)));
  });

  Future<void> signOut(Id<Profiles> id) async {
    await (update(profiles)..where((p) => p.id.equals(id.value))).write(
      ProfilesCompanion(signedIn: Value(false)),
    );
  }

  Future<void> updateAppSettings(AppSettingsCompanion settings) async {
    await into(appSettings).insert(
      settings.copyWith(id: const Value(0)),
      onConflict: DoUpdate((_) => settings),
    );
  }

  Future<void> updateContactName(
    Id<Profiles> profileId,
    PublicKey publicKey,
    String name,
  ) async {
    await (update(contacts)..where(
          (c) =>
              c.profileId.equals(profileId.value) &
              c.publicKey.equals(publicKey.toJson()),
        ))
        .write(ContactsCompanion(name: Value(name.isEmpty ? null : name)));
  }

  Future<void> updateContactOnline(
    Id<Profiles> profileId,
    PublicKey publicKey,
    bool online,
  ) async {
    await (update(contacts)..where(
          (c) =>
              c.profileId.equals(profileId.value) &
              c.publicKey.equals(publicKey.toJson()),
        ))
        .write(ContactsCompanion(online: Value(online)));
  }

  Future<void> updateProfileSettings(
    Id<Profiles> id,
    ProfileSettings settings,
  ) async {
    await (update(profiles)..where((p) => p.id.equals(id.value))).write(
      ProfilesCompanion(settings: Value(settings)),
    );
  }

  Stream<AppSetting> watchAppSettings() =>
      select(appSettings).watchSingleOrNull().map(
        (settings) =>
            settings ??
            const AppSetting(
              id: 0,
              stayOnline: true,
              autoAcceptFileSize: defaultAutoAcceptFileSize,
            ),
      );

  Stream<Contact> watchContact(Id<Contacts> id) =>
      (select(contacts)..where((c) => c.id.equals(id.value))).watchSingle();

  Stream<List<Contact>> watchContactsFor(Id<Profiles> id) =>
      (select(contacts)
            ..where((c) => c.profileId.equals(id.value))
            ..orderBy([(c) => OrderingTerm(expression: c.name)]))
          .watch();

  Stream<List<FriendRequest>> watchFriendRequestsFor(Id<Profiles> id) =>
      (select(friendRequests)
            ..where((r) => r.profileId.equals(id.value))
            ..orderBy([(r) => OrderingTerm(expression: r.timestamp)]))
          .watch();

  /// Files offered to us or being received, with their state.
  Stream<List<Message>> watchIncomingFilesFor(Id<Profiles> id) =>
      (select(messages)..where(
            (m) =>
                m.delivered.isNull() &
                m.fileState.isNotNull() &
                m.contactId.isInQuery(_contactsOf(id)),
          ))
          .watch();

  Stream<List<Message>> watchMessagesFor(Id<Contacts> id) =>
      (select(messages)..where((m) => m.contactId.equals(id.value))).watch();

  Stream<Profile> watchProfile(Id<Profiles> id) =>
      (select(profiles)..where((p) => p.id.equals(id.value))).watchSingle();

  Stream<List<Profile>> watchProfiles() => select(profiles).watch();

  Stream<Map<Id<Contacts>, int>> watchUnreadCountsFor(Id<Profiles> id) {
    final unread = messages.id.count();
    final query =
        selectOnly(messages).join([
            innerJoin(contacts, contacts.id.equalsExp(messages.contactId)),
            innerJoin(profiles, profiles.id.equalsExp(contacts.profileId)),
          ])
          ..addColumns([contacts.id, unread])
          ..where(
            contacts.profileId.equals(id.value) &
                messages.author.equalsExp(profiles.publicKey).not() &
                messages.id.isBiggerThan(
                  coalesce([contacts.lastReadMessage, const Constant(0)]),
                ),
          )
          ..groupBy([contacts.id]);
    return query.watch().map(
      (rows) => {
        for (final row in rows)
          row.readWithConverter(contacts.id)!: row.read(unread)!,
      },
    );
  }

  Stream<List<Message>> watchUndeliveredMessagesFor(Id<Profiles> id) =>
      (select(messages)
            ..where(
              (m) =>
                  m.delivered.equals(false) &
                  m.contactId.isInQuery(_contactsOf(id)),
            )
            ..orderBy([(m) => OrderingTerm(expression: m.id)]))
          .watch();

  BaseSelectStatement _contactsOf(Id<Profiles> id) => selectOnly(contacts)
    ..addColumns([contacts.id])
    ..where(contacts.profileId.equals(id.value));
}
