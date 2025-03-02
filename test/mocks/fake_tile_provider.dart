import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

final class FakeTileProvider extends TileProvider {
  final List<TileCoordinates> requests = [];

  @override
  ImageProvider<int> getImage(TileCoordinates coordinates, TileLayer options) {
    requests.add(coordinates);
    return FakeImageProvider();
  }
}

final class FakeImageProvider extends ImageProvider<int> {
  @override
  Future<int> obtainKey(ImageConfiguration configuration) async {
    return 0;
  }
}
