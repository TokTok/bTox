import 'package:btox/attachments/attachments.dart';
import 'package:flutter/material.dart';

/// A picture on the whole screen, to zoom into.
final class PictureView extends StatelessWidget {
  final String path;

  const PictureView({super.key, required this.path});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
    ),
    body: InteractiveViewer(maxScale: 8, child: Center(child: picture(path))),
  );
}
