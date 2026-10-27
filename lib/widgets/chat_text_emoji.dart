import 'package:flutter/material.dart';

final class ChatTextEmoji extends StatelessWidget {
  final String emoji;
  final TextStyle textStyle;

  const ChatTextEmoji({
    super.key,
    required this.emoji,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) =>
      Text(emoji, style: textStyle.copyWith(fontSize: 48));
}
