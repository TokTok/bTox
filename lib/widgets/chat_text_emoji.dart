import 'package:flutter/material.dart';

final class ChatTextEmoji extends StatelessWidget {
  final Positioned? stateIcon;
  final String emoji;
  final TextStyle textStyle;

  const ChatTextEmoji({
    super.key,
    required this.stateIcon,
    required this.emoji,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: stateIcon != null
              ? EdgeInsets.fromLTRB(0, 0, 0, 12)
              : EdgeInsets.zero,
          child: Text(
            emoji,
            style: textStyle.copyWith(fontSize: 48),
          ),
        ),
        ?stateIcon,
      ],
    );
  }
}
