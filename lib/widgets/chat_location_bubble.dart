import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart' show Profiles;
import 'package:btox/providers/map_tile.dart';
import 'package:btox/widgets/bubble_footer.dart';
import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// How tall a map is in its bubble, under the sender's name if it has one.
const _kMapHeight = 188.0;

final class ChatLocationBubble extends StatelessWidget {
  // Whose proxy fetches the map.
  final Id<Profiles> profile;
  final BorderRadius corners;
  final Widget? header;
  final Color color;
  final BubbleFooter? footer;
  final double latitude;
  final double longitude;
  final TapCallback onTap;

  const ChatLocationBubble({
    super.key,
    required this.profile,
    required this.corners,
    this.header,
    required this.color,
    this.footer,
    required this.latitude,
    required this.longitude,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.6,
      ),
      child: ChatTextBubble(
        corners: corners,
        color: color,
        header: header,
        child: SizedBox(
          height: _kMapHeight,
          child: Stack(
            children: [
              LocationMap(
                profile: profile,
                latitude: latitude,
                longitude: longitude,
                onTap: onTap,
              ),
              if (footer case final footer?) footer.overMedia(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A still map with a pin on the location.
final class LocationMap extends ConsumerWidget {
  final Id<Profiles> profile;
  final double latitude;
  final double longitude;
  final TapCallback? onTap;

  const LocationMap({
    super.key,
    required this.profile,
    required this.latitude,
    required this.longitude,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = ref.watch(mapTileProvider(profile));
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(latitude, longitude),
        initialZoom: 13.0,
        interactionOptions: InteractionOptions(flags: InteractiveFlag.none),
        onTap: onTap,
      ),
      children: [
        if (tiles != null)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'chat.tox.btox',
            tileProvider: tiles,
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(latitude, longitude),
              child: Icon(Icons.location_on, color: Colors.red),
            ),
          ],
        ),
      ],
    );
  }
}
