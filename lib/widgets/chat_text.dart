import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:btox/widgets/chat_text_emoji.dart';
import 'package:emoji_regex/emoji_regex.dart';
import 'package:flutter/material.dart';

/// Matches one single emoji.
final _emojiRegex = RegExp('^(?:${emojiRegex().pattern})\$');

bool _isEmoji(String s) {
  return _emojiRegex.hasMatch(s);
}

final class ChatText extends StatelessWidget {
  final Positioned? stateIcon;
  final String text;
  final Color color;
  final TextStyle textStyle;
  final double bubbleRadius;

  const ChatText({
    super.key,
    required this.stateIcon,
    required this.text,
    required this.color,
    required this.textStyle,
    required this.bubbleRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (_isEmoji(text)) {
      return ChatTextEmoji(
        stateIcon: stateIcon,
        emoji: text,
        textStyle: textStyle,
      );
    }
    return ChatTextBubble(
      radius: bubbleRadius,
      color: color,
      stateIcon: stateIcon,
      child: Text(
        text,
        style: textStyle,
      ),
    );
  }
}
