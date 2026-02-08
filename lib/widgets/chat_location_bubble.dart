import 'package:btox/providers/map_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

final class ChatLocationBubble extends ConsumerWidget {
  final double radius;
  final Color color;
  final Widget? stateIcon;
  final double latitude;
  final double longitude;
  final TapCallback onTap;

  const ChatLocationBubble({
    super.key,
    required this.radius,
    required this.color,
    required this.stateIcon,
    required this.latitude,
    required this.longitude,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.6,
        maxHeight: 200,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: stateIcon != null
                ? EdgeInsets.fromLTRB(12, 6, 28, 6)
                : EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(latitude, longitude),
                initialZoom: 13.0,
                interactionOptions: InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
                onTap: onTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  tileProvider: ref.read(mapTileProvider),
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: LatLng(latitude, longitude),
                    child: Icon(Icons.location_on, color: Colors.red),
                  ),
                ]),
              ],
            ),
          ),
          ?stateIcon,
        ],
      ),
    );
  }
}
