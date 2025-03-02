import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:drift/drift.dart';

export 'package:drift/drift.dart' show Value;

part 'database.g.dart';

@DriftDatabase(tables: [
  Contacts,
  Messages,
  Profiles,
])
final class Database extends _$Database {
  Database(super.e);

  // TODO(robinlinden): Remove before first real release.
  @override
  MigrationStrategy get migration => destructiveFallback;

  @override
  int get schemaVersion => 1;

  Future<void> activateProfile(Id<Profiles> id) async {
    // Currently we only support 1 active profile at a time.
    await deactivateProfiles();

    await (update(profiles)..where((p) => p.id.equals(id.value)))
        .write(ProfilesCompanion(
      active: Value(true),
    ));
  }

  Future<Id<Contacts>> addContact(ContactsCompanion entry) async =>
      Id(await into(contacts).insert(entry));

  Future<Id<Messages>> addMessage(MessagesCompanion entry) async =>
      Id(await into(messages).insert(entry));

  Future<Id<Profiles>> addProfile(ProfilesCompanion entry) async =>
      Id(await into(profiles).insert(entry));

  Future<void> deactivateProfiles() async {
    await update(profiles).write(ProfilesCompanion(
      active: Value(false),
    ));
  }

  Future<void> deleteProfile(Id<Profiles> id) async {
    transaction(() async {
      // Find all the contacts for the profile.
      final contactsForProfile = await (select(contacts)
            ..where((c) => c.profileId.equals(id.value)))
          .get();
      // Delete all their messages.
      batch((batch) {
        for (final contact in contactsForProfile) {
          batch.deleteWhere(
            messages,
            (m) => m.contactId.equals(contact.id.value),
          );
        }
      });
      // Then delete the contacts.
      await (delete(contacts)..where((c) => c.profileId.equals(id.value))).go();
      // Finally delete the profile.
      await (delete(profiles)..where((p) => p.id.equals(id.value))).go();
    });
  }

  Future<Message> getMessage(Id<Messages> id) async =>
      (select(messages)..where((m) => m.id.equals(id.value))).getSingle();

  Future<void> updateProfileSettings(
      Id<Profiles> id, ProfileSettings settings) async {
    await (update(profiles)..where((p) => p.id.equals(id.value))).write(
      ProfilesCompanion(
        settings: Value(settings),
      ),
    );
  }

  Stream<Contact> watchContact(Id<Contacts> id) =>
      (select(contacts)..where((c) => c.id.equals(id.value))).watchSingle();

  Stream<List<Contact>> watchContactsFor(Id<Profiles> id) => (select(contacts)
        ..where((c) => c.profileId.equals(id.value))
        ..orderBy([
          (c) => OrderingTerm(expression: c.name),
        ]))
      .watch();

  Stream<List<Message>> watchMessagesFor(Id<Contacts> id) =>
      (select(messages)..where((m) => m.contactId.equals(id.value))).watch();

  Stream<Profile> watchProfile(Id<Profiles> id) =>
      (select(profiles)..where((p) => p.id.equals(id.value))).watchSingle();

  Stream<List<Profile>> watchProfiles() => select(profiles).watch();
}
