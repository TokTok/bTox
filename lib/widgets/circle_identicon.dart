import 'package:btox/models/crypto.dart';
import 'package:btox/models/identicon.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final class CircleIdenticon extends ConsumerWidget {
  final CryptoBytes bytes;
  final double radius;

  const CircleIdenticon({super.key, required this.bytes, this.radius = 20});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ClipOval(
    child: CustomPaint(
      size: Size.square(radius * 2),
      painter: _IdenticonPainter(ref.watch(identiconProvider(bytes))),
    ),
  );
}

final class _IdenticonPainter extends CustomPainter {
  final Identicon identicon;

  const _IdenticonPainter(this.identicon);

  @override
  void paint(Canvas canvas, Size size) {
    final blocks = identicon.blocks;
    final side = size.width / blocks.length;
    // Without anti-aliasing, neighbouring blocks meet without a seam.
    final paint = Paint()..isAntiAlias = false;
    for (final (row, colors) in blocks.indexed) {
      for (final (col, color) in colors.indexed) {
        canvas.drawRect(
          Rect.fromLTWH(col * side, row * side, side, side),
          paint..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_IdenticonPainter old) => old.identicon != identicon;
}
