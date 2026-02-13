import 'package:btox/db/database.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final contactsForProfileProvider =
    StreamProvider.family<List<Contact>, Id<Profiles>>((ref, profileId) async* {
      final db = await ref.watch(databaseProvider.future);
      yield* db.watchContactsFor(profileId);
    });

final contactProvider = StreamProvider.family<Contact, Id<Contacts>>((
  ref,
  contactId,
) async* {
  final db = await ref.watch(databaseProvider.future);
  yield* db.watchContact(contactId);
});
