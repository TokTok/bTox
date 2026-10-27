import 'package:flutter/material.dart';

/// Leaves swipes that start where the system takes them to the system:
/// horizontal ones at the sides, as Android's back gesture, and any at the
/// bottom, as going home or to another app. The app would otherwise see them
/// begin, and scroll a little before the system takes over. Taps there, and
/// vertical drags at the sides, still reach the app.
Widget leaveSystemSwipes(BuildContext context, Widget? child) {
  final insets = MediaQuery.systemGestureInsetsOf(context);
  Widget zone({bool vertical = false}) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) {},
    onVerticalDragStart: vertical ? (_) {} : null,
  );
  return Stack(
    children: [
      ?child,
      if (insets.left > 0)
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: insets.left,
          child: zone(),
        ),
      if (insets.right > 0)
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: insets.right,
          child: zone(),
        ),
      if (insets.bottom > 0)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: insets.bottom,
          child: zone(vertical: true),
        ),
    ],
  );
}
