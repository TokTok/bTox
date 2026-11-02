import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:btox/sync/avatar_files.dart';

const _maxPixels = 1 << 26;

// Tried in turn until the avatar fits in [maxAvatarSize].
const _sides = [256, 192, 128, 96, 64];

/// [picture]'s centre square as a PNG of at most [maxAvatarSize] bytes, if
/// it can be made one.
Future<Uint8List?> avatarPicture(Uint8List picture) async {
  final ui.ImmutableBuffer buffer;
  final ui.ImageDescriptor descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(picture);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } on Object {
    return null;
  }
  try {
    final (width, height) = (descriptor.width, descriptor.height);
    if (width == 0 || height == 0 || width * height > _maxPixels) {
      return null;
    }
    final short = width < height ? width : height;
    for (final side in _sides) {
      // Its short side scaled down to [side].
      final scale = side < short ? side / short : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (width * scale).ceil(),
        targetHeight: (height * scale).ceil(),
      );
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final png = await _square(image, side < short ? side : short);
      image.dispose();
      if (png != null && png.length <= maxAvatarSize) {
        return png;
      }
    }
    return null;
  } on Object {
    return null;
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}

/// [image]'s centre [side]-pixel square, as a PNG.
Future<Uint8List?> _square(ui.Image image, int side) async {
  final recorder = ui.PictureRecorder();
  final left = (image.width - side) / 2;
  final top = (image.height - side) / 2;
  ui.Canvas(recorder).drawImageRect(
    image,
    ui.Rect.fromLTWH(left, top, side.toDouble(), side.toDouble()),
    ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final square = await recorder.endRecording().toImage(side, side);
  final bytes = await square.toByteData(format: ui.ImageByteFormat.png);
  square.dispose();
  return bytes?.buffer.asUint8List();
}
