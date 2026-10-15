import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart' show Profiles;
import 'package:btox/providers/bootstrap_nodes.dart';
import 'package:btox/providers/profiles.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_tile.g.dart';

/// Map tiles of [profile]'s chats, fetched through its proxy, if any, so
/// they don't give away where its user looks. None until its settings are
/// known.
@riverpod
TileProvider? mapTile(Ref ref, Id<Profiles> profile) {
  final network = ref.watch(
    profileProvider(profile).select((p) => p.value?.settings.network),
  );
  return network == null
      ? null
      : NetworkTileProvider(httpClient: ref.watch(httpClientProvider(network)));
}
