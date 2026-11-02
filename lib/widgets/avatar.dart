import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/avatars.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Friends choose avatars, and Flutter may decode all their pixels however
// small it shows them.
const _maxPixels = 1 << 22;

/// Shows the identicon of [bytes] until [blob] can be shown.
final class Avatar extends ConsumerWidget {
  final Id<Profiles>? profile;
  final BlobId? blob;
  final CryptoBytes bytes;
  final double radius;

  const Avatar({
    super.key,
    required this.profile,
    required this.blob,
    required this.bytes,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identicon = CircleIdenticon(bytes: bytes, radius: radius);
    final (profile, blob) = (this.profile, this.blob);
    final image = profile == null || blob == null
        ? null
        : ref.watch(avatarProvider(profile, blob)).value;
    return image == null
        ? identicon
        : _Picture(image: image, radius: radius, fallback: identicon);
  }
}

/// Whether [image]'s header gives it no more than [_maxPixels] pixels.
Future<bool> _fits(Uint8List image) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(image);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final fits = descriptor.width * descriptor.height <= _maxPixels;
      descriptor.dispose();
      return fits;
    } finally {
      buffer.dispose();
    }
  } on Object {
    return false;
  }
}

final class _Picture extends HookWidget {
  final Uint8List image;
  final double radius;
  final Widget fallback;

  const _Picture({
    required this.image,
    required this.radius,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final fits = useFuture(useMemoized(() => _fits(image), [image]));
    if (fits.data != true) {
      return fallback;
    }
    final pixels = (radius * 2 * MediaQuery.devicePixelRatioOf(context))
        .round();
    return ClipOval(
      child: Image.memory(
        image,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        cacheWidth: pixels,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
