import 'package:btox/db/database.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final messagesForContactProvider =
    StreamProvider.family<List<Message>, Id<Contacts>>(
      (ref, id) => watchDb(ref, (db) => db.watchMessagesFor(id)),
    );
