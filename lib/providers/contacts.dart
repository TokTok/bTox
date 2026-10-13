import 'package:btox/db/database.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final contactsForProfileProvider =
    StreamProvider.family<List<Contact>, Id<Profiles>>(
      (ref, id) => watchDb(ref, (db) => db.watchContactsFor(id)),
    );

final friendRequestsForProfileProvider =
    StreamProvider.family<List<FriendRequest>, Id<Profiles>>(
      (ref, id) => watchDb(ref, (db) => db.watchFriendRequestsFor(id)),
    );

final contactProvider = StreamProvider.family<Contact, Id<Contacts>>(
  (ref, id) => watchDb(ref, (db) => db.watchContact(id)),
);

final unreadCountsProvider =
    StreamProvider.family<Map<Id<Contacts>, int>, Id<Profiles>>(
      (ref, id) => watchDb(ref, (db) => db.watchUnreadCountsFor(id)),
    );
