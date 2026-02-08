import 'package:flutter_map/flutter_map.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_tile.g.dart';

@riverpod
TileProvider mapTile(Ref ref) {
  return NetworkTileProvider();
}
