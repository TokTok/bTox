import 'package:btox/models/crypto.dart';
import 'package:btox/models/identicon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class CircleIdenticon extends ConsumerWidget {
  final PublicKey publicKey;

  const CircleIdenticon({super.key, required this.publicKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CircleAvatar(
      backgroundImage: ref.watch(identiconProvider(publicKey)),
    );
  }
}
