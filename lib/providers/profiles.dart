import 'package:btox/db/database.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final profilesProvider = StreamProvider<List<Profile>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield* db.watchProfiles();
});

final activeProfileProvider = Provider<Profile?>((ref) {
  final allProfiles = ref.watch(profilesProvider).value ?? const [];
  return allProfiles.where((p) => p.active).firstOrNull;
});

final profileProvider = StreamProvider.family<Profile, Id<Profiles>>((
  ref,
  id,
) async* {
  final db = await ref.watch(databaseProvider.future);
  yield* db.watchProfile(id);
});
