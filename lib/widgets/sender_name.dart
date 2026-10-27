import 'dart:convert';

import 'package:btox/models/crypto.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

/// Who wrote a message in a group chat, in a colour of their own: the same
/// everywhere for the same [author], whatever they're called, or for the
/// same name where there's no key.
final class SenderName extends StatelessWidget {
  final String name;
  final PublicKey? author;

  const SenderName(this.name, {super.key, this.author});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hash = sha256.convert(author?.bytes ?? utf8.encode(name)).bytes;
    final hue = (hash[0] << 8 | hash[1]) / 0xffff * 360;
    final light = theme.brightness == Brightness.dark;
    return Text(
      name,
      style: theme.textTheme.labelLarge?.copyWith(
        color: HSLColor.fromAHSL(1, hue, 0.6, light ? 0.75 : 0.4).toColor(),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
