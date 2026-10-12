import 'package:btox/db/database.steps.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:drift/drift.dart';

export 'package:drift/drift.dart' show Value;

part 'database.g.dart';

@DriftDatabase(tables: [Contacts, FriendRequests, Messages, Profiles])
final class Database extends _$Database {
  Database(super.e);

  // Bump with every schema change, then run `tools/prepare`.
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.addColumn(
          schema.contacts,
          schema.contacts.friendRequestAddress,
        );
        await m.addColumn(
          schema.contacts,
          schema.contacts.friendRequestMessage,
        );
        await m.addColumn(schema.messages, schema.messages.delivered);
      },
      from2To3: (m, schema) async {
        await m.createTable(schema.friendRequests);
      },
      from3To4: (m, schema) async {
        await m.addColumn(schema.contacts, schema.contacts.online);
      },
    ),
  );

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

  Future<void> activateProfile(Id<Profiles> id) async {
    // Currently we only support 1 active profile at a time.
    await deactivateProfiles();

    await (update(profiles)..where((p) => p.id.equals(id.value))).write(
      ProfilesCompanion(active: Value(true)),
    );
  }

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

  Future<void> deactivateProfiles() async {
    await update(profiles).write(ProfilesCompanion(active: Value(false)));
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
      // Find all the contacts for the profile.
      final contactsForProfile = await (select(
        contacts,
      )..where((c) => c.profileId.equals(id.value))).get();
      // Delete all their messages.
      batch((batch) {
        for (final contact in contactsForProfile) {
          batch.deleteWhere(
            messages,
            (m) => m.contactId.equals(contact.id.value),
          );
        }
      });
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

  Future<Message> getMessage(Id<Messages> id) async =>
      (select(messages)..where((m) => m.id.equals(id.value))).getSingle();

  Future<void> markMessageDelivered(Id<Messages> id) async {
    await (update(messages)..where((m) => m.id.equals(id.value))).write(
      const MessagesCompanion(delivered: Value(true)),
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

  Stream<List<Message>> watchMessagesFor(Id<Contacts> id) =>
      (select(messages)..where((m) => m.contactId.equals(id.value))).watch();

  Stream<Profile> watchProfile(Id<Profiles> id) =>
      (select(profiles)..where((p) => p.id.equals(id.value))).watchSingle();

  Stream<List<Profile>> watchProfiles() => select(profiles).watch();

  Stream<List<Message>> watchUndeliveredMessagesFor(Id<Profiles> id) =>
      (select(messages).join([
              innerJoin(contacts, contacts.id.equalsExp(messages.contactId)),
            ])
            ..where(
              messages.delivered.equals(false) &
                  contacts.profileId.equals(id.value),
            )
            ..orderBy([OrderingTerm(expression: messages.id)]))
          .map((row) => row.readTable(messages))
          .watch();
}
