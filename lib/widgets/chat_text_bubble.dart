import 'package:flutter/material.dart';

final class ChatTextBubble extends StatelessWidget {
  final double radius;
  final Color color;
  final Widget? stateIcon;
  final Widget child;

  const ChatTextBubble({
    super.key,
    required this.radius,
    required this.color,
    required this.stateIcon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: child,
          ),
          ?stateIcon,
        ],
      ),
    );
  }
}
